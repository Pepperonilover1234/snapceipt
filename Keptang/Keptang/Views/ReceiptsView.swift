import SwiftData
import SwiftUI

struct ReceiptsView: View {
    enum Mode: String, CaseIterable {
        case types = "Receipt type", calendar = "Calendar"
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @State private var mode: Mode = LaunchOption.string("receipts") == "calendar" ? .calendar : .types
    @State private var listedCategory: SpendCategory?
    @State private var search = LaunchOption.string("search") ?? ""
    @State private var category: SpendCategory?
    /// Opens a receipt straight away, for screenshots: `-open latest`.
    @State private var opened: Receipt?

    /// The choosable categories, plus Home while saved items still use it.
    private var filterCategories: [SpendCategory] {
        let usesHome = receipts.contains { $0.items.contains { $0.category == .home } }
        return SpendCategory.selectable + (usesHome ? [.home] : [])
    }

    private struct MonthGroup: Identifiable {
        let month: Date
        let receipts: [Receipt]
        var id: Date { month }
        /// Money out only; money in is shown on its own.
        var total: Double { receipts.filter { !$0.isIncome }.reduce(0) { $0 + $1.total } }
        var income: Double { receipts.filter(\.isIncome).reduce(0) { $0 + $1.total } }
    }

    private var groups: [MonthGroup] {
        let filtered = receipts.filter { receipt in
            let matchesCategory = category == nil
                || (category == .utilities && receipt.kind.isBill)
                || receipt.items.contains { $0.category == category }
            return matchesCategory && ReceiptSearch.matches(search, receipt.searchFields)
        }
        return Dictionary(grouping: filtered) { $0.date.startOfMonth }
            .map { MonthGroup(month: $0.key, receipts: $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedBar(title: "View", options: Mode.allCases, selection: $mode, ) { $0.rawValue }
                .padding(.horizontal)
                .padding(.bottom, 8)
            switch mode {
            case .types: list
            case .calendar: SpendingCalendarView()
            }
        }
        .background(Theme.paper)
        .searchable(text: $search, prompt: "Shop, item, text or amount")
        .onChange(of: search) { _, text in
            // Search covers every receipt ever saved, so it shows the list.
            if !text.isEmpty, mode == .calendar { mode = .types }
        }
        .navigationTitle("Receipts")
        .navigationDestination(item: $opened) { ReceiptDetailView(receipt: $0) }
        .navigationDestination(item: $listedCategory) { CategoryReceiptList(category: $0) }
        .task {
            if LaunchOption.string("open") == "latest", opened == nil { opened = receipts.first }
        }
        .toolbar {
            Menu {
                Picker("Category", selection: $category) {
                    Text("All categories").tag(SpendCategory?.none)
                    ForEach(filterCategories) { item in
                        Label(item.name, systemImage: item.symbol).tag(Optional(item))
                    }
                }
            } label: {
                Label("Filter", systemImage: category == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }
    }

    /// The type tiles, then every receipt newest first. While searching or filtering, just the matches.
    private var list: some View {
        let browsing = search.isEmpty && category == nil
        return List {
            if browsing, !receipts.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    TypeTiles(rows: TypeTileRow.rows(SpendingAnalyzer(receipts.filter { !$0.isIncome }.map(ReceiptSnapshot.init))),
                              onSelect: { listedCategory = $0 })
                    ParameterLabel(number: 2, text: "recent receipts")
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.receipts) { receipt in
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            ReceiptRow(receipt: receipt)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(group.receipts[index]) }
                        try? context.save()
                    }
                    .listRowBackground(Theme.surface)
                } header: {
                    AdaptiveStack(spacing: 8) {
                        TitleChip(group.month.formatted(.dateTime.month(.wide).year()),
                                  tint: Theme.rainbow[(Calendar.app.component(.month, from: group.month) - 1) % Theme.rainbow.count])
                        Spacer(minLength: 8)
                        if group.income > 0 {
                            Text("+\(group.income.bahtWhole)").foregroundStyle(Theme.down).fixedSize()
                        }
                        Text(group.total.bahtWhole).fixedSize()
                    }
                    .font(Theme.label)
                    .textCase(nil)
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 6)
                    // Opaque, so rows don't show through while the header is pinned at the top.
                    .background { Theme.paper.padding(.horizontal, -40).padding(.vertical, -2) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.searchHighlight, search)
        .paperBackground()
        .overlay {
            if receipts.isEmpty {
                ContentUnavailableView("No receipts yet", systemImage: "doc.viewfinder",
                                       description: Text("Scan a receipt and it shows up here."))
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}

struct ReceiptDetailView: View {
    @Bindable var receipt: Receipt
    @State private var showingPhoto = false
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if receipt.isIncome { incomeBody } else { spendingBody }
    }

    /// Money in: where it came from, how much and when, all editable.
    private var incomeBody: some View {
        CardPage {
            CardSection(color: .mint) {
                VStack(alignment: .leading, spacing: 10) {
                    AdaptiveStack {
                        CategoryIcon(symbol: receipt.iconSymbol, size: 48, fill: receipt.iconColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Money in").font(Theme.label).foregroundStyle(Theme.down)
                            Text(receipt.shopName).font(.system(.title3, weight: .semibold)).foregroundStyle(Theme.ink)
                        }
                    }
                    Text(receipt.signedAmount).font(Theme.figure(.largeTitle)).fontWeight(.bold).foregroundStyle(Theme.down)
                    if !receipt.reader.isEmpty { Badge(text: receipt.reader == "Typed" ? "Typed in" : "Read by \(receipt.reader)") }
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
            CardSection(title: "Details", note: "Money in is kept apart from spending, VAT and your money goal.", color: .lime) {
                LabeledContent("Name") {
                    TextField("Name", text: $receipt.shopName).multilineTextAlignment(.trailing).font(.body.weight(.semibold))
                }
                LabeledContent("Came from") {
                    Picker("Came from", selection: $receipt.incomeSource) {
                        ForEach(IncomeSource.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden()
                }
                LabeledContent("Amount") { BahtField(title: "Amount", value: $receipt.total, style: .headline) }
                DateField(title: "Date", date: $receipt.date)
            }
            if !receipt.rawText.isEmpty {
                CardSection(title: "What you typed") {
                    Text(receipt.rawText).font(.body.monospaced()).foregroundStyle(Theme.ink).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(receipt.shopName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var spendingBody: some View {
        let color = receipt.kind.isBill ? receipt.kind.cardColor : receipt.mainCategory.cardColor
        return CardPage {
            CardSection(color: color) {
                VStack(alignment: .leading, spacing: 10) {
                    AdaptiveStack {
                        CategoryIcon(symbol: receipt.iconSymbol, size: 48, fill: receipt.iconColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(receipt.shopName).font(.system(.title3, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text(receipt.date, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    HeroFigure(text: receipt.total.baht, highlighted: true)
                        .environment(\.pageAccent, color.bright)
                    AdaptiveStack(spacing: 6) {
                        if receipt.isFullTaxInvoice { Badge(text: "Full tax invoice", fill: Theme.lime) }
                        if receipt.kind.isBill { Badge(text: receipt.kind.name, fill: receipt.kind.fill) }
                        if receipt.reader == "Sample" {
                            Badge(text: "Sample data")
                        } else if !receipt.reader.isEmpty {
                            Badge(text: "Read by \(receipt.reader)")
                        }
                    }
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }

            if let data = receipt.imageData, let image = UIImage(data: data) {
                CardSection(title: "Photo", color: .sky) {
                    Button { showingPhoto = true } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Receipt photo")
                    .accessibilityHint("Opens the photo full size")
                    .sheet(isPresented: $showingPhoto) {
                        NavigationStack {
                            ScrollView { Image(uiImage: image).resizable().scaledToFit() }
                                .toolbar { Button("Done") { showingPhoto = false } }
                        }
                    }
                }
            }

            CardSection(title: "\(receipt.items.count) items", note: "Tap an item's icon to change its category. Snapceipt remembers it for next time.", color: .pink) {
                ForEach(receipt.sortedItems) { item in
                    ItemRow(item: item)
                }
                if !receipt.kind.isBill {
                    Menu {
                        ForEach(SpendCategory.selectable) { category in
                            Button { setWholeReceipt(to: category) } label: {
                                Label(category.name, systemImage: category.symbol)
                            }
                        }
                    } label: {
                        Label("Set category for the whole receipt…", systemImage: "square.grid.2x2")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("Sorts every item into one category and remembers it for \(receipt.shopName)")
                }
            }

            CardSection(title: "Totals", color: .yellow) {
                AmountRow("Items", receipt.itemsTotal.baht)
                AmountRow("Price before VAT", (receipt.total - receipt.vat).baht)
                AmountRow("VAT 7%", receipt.vat.baht)
                AmountRow("Total paid", receipt.total.baht, emphasized: true)
            }

            CardSection(title: "Tax", note: "Only full tax invoices count toward the government's shopping tax deduction.", color: .lime) {
                Toggle("Full tax invoice (ใบกำกับภาษีเต็มรูป)", isOn: $receipt.isFullTaxInvoice)
                if !receipt.sellerTaxID.isEmpty {
                    AmountRow("Seller tax ID", receipt.sellerTaxID)
                }
                if receipt.kind.isBill, let unit = receipt.kind.unit, receipt.billUnits > 0 {
                    AmountRow("Used", "\(receipt.billUnits.formatted()) \(unit)")
                }
            }

            ConnectedReceiptsSection(receipt: receipt)

            RowButton(title: "Show in graph", symbol: "point.3.connected.trianglepath.dotted") { router.showInGraph(SpendingGraph.receiptID(receipt.graphKey)) }
                .padding(.horizontal, 16)
                .block(CardColor.lime.tint)

            if !receipt.rawText.isEmpty {
                CardSection {
                    DisclosureGroup("Text read from the photo") {
                        Text(receipt.rawText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(receipt.shopName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Every item into one category, remembered for this merchant's future receipts.
    private func setWholeReceipt(to category: SpendCategory) {
        for item in receipt.items { item.category = category }
        CategoryLearner.shared.learnMerchant(receipt.shopName, as: category)
        try? modelContext.save()
    }
}

struct ItemRow: View {
    @Bindable var item: LineItem

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SpendCategory.selectable) { category in
                    Button {
                        item.category = category
                        CategoryLearner.shared.learn(item.name, as: category)
                    } label: {
                        Label(category.name, systemImage: category.symbol)
                    }
                }
            } label: {
                CategoryIcon(symbol: item.category.symbol, size: 34, fill: item.category.color)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Category: \(item.category.name)")
            .accessibilityHint("Changes this item's category")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).foregroundStyle(Theme.ink)
                HStack(spacing: 4) {
                    Text(item.category.name)
                    if item.quantity != 1 {
                        Text("· \(item.quantity.formatted()) × \(item.unitPrice.baht)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(item.total.baht)
                .font(Theme.figure(.body))
                .foregroundStyle(item.total < 0 ? Theme.down : Theme.ink)
        }
    }
}

/// Receipts linked to this one: the same shop, shared items, links the person confirmed, and the
/// on-device model's suggestions with their reasons, marked as suggestions.
struct ConnectedReceiptsSection: View {
    let receipt: Receipt
    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }, sort: \Receipt.date, order: .reverse) private var all: [Receipt]
    @Query private var decisions: [LinkDecision]
    @State private var suggestions: [LinkSuggester.Suggestion] = []

    private struct Connection: Identifiable {
        let receipt: Receipt
        let why: String
        let suggested: Bool
        var id: PersistentIdentifier { receipt.persistentModelID }
    }

    private var connections: [Connection] {
        let key = receipt.graphKey
        let byKey = Dictionary(all.map { ($0.graphKey, $0) }, uniquingKeysWith: { a, _ in a })
        let decided = Dictionary(decisions.map { ($0.pairKey, $0.confirmed) }, uniquingKeysWith: { _, last in last })
        var result: [Connection] = []
        var seen: Set<PersistentIdentifier> = [receipt.persistentModelID]
        func add(_ other: Receipt, _ why: String, suggested: Bool = false) {
            guard seen.insert(other.persistentModelID).inserted else { return }
            result.append(Connection(receipt: other, why: why, suggested: suggested))
        }
        for (pair, confirmed) in decided where confirmed {
            let keys = pair.split(separator: "|").map(String.init)
            guard keys.contains(key), let otherKey = keys.first(where: { $0 != key }), let other = byKey[otherKey] else { continue }
            add(other, "Linked by you")
        }
        let shop = MerchantCategorizer.normalize(receipt.shopName)
        for other in all where MerchantCategorizer.normalize(other.shopName) == shop && !SpendingGraph.isUnknownShop(other.shopName, kind: other.kind) {
            if result.filter({ $0.why.hasPrefix("Same shop") }).count >= 3 { break }
            add(other, "Same shop")
        }
        let items = Set(receipt.items.map { CategoryLearner.normalize($0.name) })
        if !items.isEmpty {
            for other in all where other.shopName != receipt.shopName {
                let shared = items.intersection(other.items.map { CategoryLearner.normalize($0.name) })
                if let first = shared.first { add(other, "Also has \(first)") }
                if result.filter({ $0.why.hasPrefix("Also has") }).count >= 3 { break }
            }
        }
        // Only suggestions as strong as the graph's "Match strength" setting shows.
        let threshold = SpendingGraphSettings.load().filter.minimumScore
        for suggestion in suggestions where (suggestion.a == key || suggestion.b == key) && decided[suggestion.pairKey] == nil
            && suggestion.score >= threshold {
            if let other = byKey[suggestion.a == key ? suggestion.b : suggestion.a] {
                add(other, "\(suggestion.reason) · \(suggestion.score.percent) match", suggested: true)
            }
        }
        return result
    }

    var body: some View {
        let list = connections
        CardSection(title: "Connected receipts", note: list.contains(where: \.suggested) ? "Suggested links come from a model on this device. Confirm or dismiss them in the graph." : nil, color: .sky) {
            if list.isEmpty {
                Text("Nothing connected yet.").foregroundStyle(Theme.muted)
            }
            ForEach(list) { connection in
                NavigationLink {
                    ReceiptDetailView(receipt: connection.receipt)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ReceiptRow(receipt: connection.receipt)
                        AdaptiveStack(spacing: 6) {
                            if connection.suggested { Badge(text: "Suggested", fill: Theme.purple) }
                            Text(connection.why).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: all.count) {
            let receipts = all.map { $0.graphReceipt() }
            let duplicates = SpendingGraph.duplicates(in: receipts)
            suggestions = await LinkSuggestionEngine.shared.suggestions(for: receipts, excluding: duplicates)
        }
    }
}
