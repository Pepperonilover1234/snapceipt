import SwiftData
import SwiftUI

/// Type it instead of scanning: one line in Thai or English, read on the device, then a checklist
/// of what was understood. Each line is ticked (or fixed, which ticks it) before saving, so the
/// app and the person agree on what's being saved.
struct QuickEntryView: View {
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var text = LaunchOption.string("quick") ?? ""
    /// What was read. Kept non-optional so the checklist's bindings never point at nothing;
    /// `isRead` says whether there's a reading to show.
    @State private var entry = QuickEntry.empty
    @State private var isRead = false
    @State private var reading = false
    @State private var checked: Set<CheckRow> = []
    @State private var saveError: String?
    @FocusState private var typing: Bool

    enum CheckRow: Hashable {
        case flow, item(UUID), category(UUID), source, date
    }

    private let examples = ["Pop corn 60", "ข้าวมันไก่ 50", "grab 120 yesterday", "coffee 45, cake 80", "เงินเดือน 30000", "+500 sold old shoes"]

    var body: some View {
        CardPage {
            CardSection(title: "Type it", note: "One line in Thai or English, like “Pop corn 60”. Press return and Snapceipt reads it on this device.", color: .pink) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard").foregroundStyle(Theme.muted).accessibilityHidden(true)
                    TextField("Pop corn 60", text: $text)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .submitLabel(.done)
                        .focused($typing)
                        .onSubmit(read)
                        .accessibilityLabel("What you spent or got")
                    if !text.isEmpty {
                        Button { text = ""; isRead = false } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.quiet)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(examples, id: \.self) { example in
                            Button { text = example; read() } label: {
                                Text(example)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 32)
                                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: min(Theme.controlRadius, 16), style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: min(Theme.controlRadius, 16), style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Tries this example")
                        }
                    }
                }
            }

            Button(action: read) {
                Label(reading ? "Reading…" : "Read it", systemImage: "sparkles")
            }
            .buttonStyle(BlockButtonStyle(prominent: !isRead))
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || reading)

            if reading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(OnDeviceAI.isAvailable ? "Apple Intelligence is reading it…" : "Reading it…").foregroundStyle(Theme.muted)
                }
            }

            if isRead {
                understood(entry)
                checklist
                saveButton
            }
        }
        .navigationTitle("Type it")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if text.isEmpty { typing = true } else if !isRead { read() }
        }
        .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: Reading

    private func read() {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        typing = false
        reading = true
        Task {
            let result = await QuickEntryReader.read(typed)
            withAnimation(.snappy) {
                entry = result
                isRead = true
                checked = []
                reading = false
            }
            // `-quickAutoSave YES`: tick every line and save, for checking the whole flow.
            if LaunchOption.string("quickAutoSave") == "YES" {
                try? await Task.sleep(for: .seconds(1))
                checked = Set(allRows)
                try? await Task.sleep(for: .seconds(1))
                save()
            }
        }
    }

    // MARK: What was understood

    /// The reading as one plain sentence, so a misunderstanding is obvious at a glance.
    private func understood(_ entry: QuickEntry) -> some View {
        CardSection(title: "Snapceipt understood", note: "Read by \(entry.reader.rawValue) · typed in \(entry.language)", color: .sky) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.flow == .moneyIn ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.title)
                    .foregroundStyle(entry.flow == .moneyIn ? Theme.down : Theme.up)
                    .accessibilityHidden(true)
                Text(sentence(entry))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
    }

    private func sentence(_ entry: QuickEntry) -> String {
        let when = dayWords(entry.date)
        if entry.flow == .moneyIn {
            return "You got \(entry.total.baht) from \(entry.source.name.lowercased())\(entry.items.first.map { $0.name.isEmpty || $0.name == entry.source.name ? "" : " (\($0.name))" } ?? "") \(when)."
        }
        let things = entry.items.map { "\($0.name.isEmpty ? "something" : $0.name) (\($0.category.name))" }
        let list = things.count <= 1 ? (things.first ?? "something")
            : things.dropLast().joined(separator: ", ") + " and " + things.last!
        return "You spent \(entry.total.baht) on \(list) \(when)."
    }

    private func dayWords(_ date: Date) -> String {
        let calendar = Calendar.app
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return "on \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
    }

    // MARK: Checklist

    private var allRows: [CheckRow] {
        guard isRead else { return [] }
        var rows: [CheckRow] = [.flow]
        for item in entry.items {
            rows.append(.item(item.id))
            if entry.flow == .moneyOut { rows.append(.category(item.id)) }
        }
        if entry.flow == .moneyIn { rows.append(.source) }
        rows.append(.date)
        return rows
    }

    private var checklist: some View {
        let done = allRows.filter(checked.contains).count
        let binding = $entry
        // Its own plain container: the rows' tick boxes must redraw the moment they change.
        return VStack(alignment: .leading, spacing: 10) {
            TitleChip("Check each line", tint: CardColor.lime.bright)
            VStack(alignment: .leading, spacing: 4) {
                checkRow(.flow, title: "Money in or out") {
                    HStack(spacing: 6) {
                        flowKey("Money out", .moneyOut, binding)
                        flowKey("Money in", .moneyIn, binding)
                    }
                }
                ForEach(binding.items) { $item in
                    checkRow(.item(item.id), title: binding.wrappedValue.flow == .moneyIn ? "What it was" : "Item") {
                        HStack(spacing: 8) {
                            TextField("Name", text: $item.name)
                                .font(.body.weight(.semibold))
                                .onChange(of: item.name) { checked.insert(.item(item.id)) }
                            BahtField(title: "Amount of \(item.name)", value: $item.amount, style: .headline)
                                .onChange(of: item.amount) { checked.insert(.item(item.id)) }
                        }
                    }
                    if binding.wrappedValue.flow == .moneyOut {
                        checkRow(.category(item.id), title: "Category") {
                            Menu {
                                Picker("Category", selection: $item.category) {
                                    ForEach(SpendCategory.selectable) { Label($0.name, systemImage: $0.symbol).tag($0) }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    CategoryIcon(symbol: item.category.symbol, size: 26, fill: item.category.color)
                                    Text(item.category.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                            .onChange(of: item.category) { checked.insert(.category(item.id)) }
                            .accessibilityLabel("Category: \(item.category.name)")
                        }
                    }
                }
                if binding.wrappedValue.flow == .moneyIn {
                    checkRow(.source, title: "Came from") {
                        Menu {
                            Picker("Came from", selection: binding.source) {
                                ForEach(IncomeSource.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: binding.wrappedValue.source.symbol).foregroundStyle(Theme.down)
                                Text(binding.wrappedValue.source.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        .onChange(of: binding.wrappedValue.source) { checked.insert(.source) }
                        .accessibilityLabel("Came from: \(binding.wrappedValue.source.name)")
                    }
                }
                checkRow(.date, title: "When") {
                    DatePicker("When", selection: binding.date, in: ...Date.now)
                        .labelsHidden()
                        .onChange(of: binding.wrappedValue.date) { checked.insert(.date) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .block()
            SectionNote("Tick what's right, or change it; changing a line ticks it. \(done) of \(allRows.count) checked.")
                .padding(.horizontal, 4)
        }
    }

    private func flowKey(_ title: String, _ flow: QuickEntry.Flow, _ entry: Binding<QuickEntry>) -> some View {
        let isOn = entry.wrappedValue.flow == flow
        return Button {
            guard !isOn else { checked.insert(.flow); return }
            var changed = entry.wrappedValue
            let total = changed.total
            changed.flow = flow
            if flow == .moneyIn {
                // One amount for money in, named after the words that were typed.
                let name = changed.items.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
                changed.source = QuickEntryRules.incomeSource(in: changed.text) ?? .other
                changed.items = [QuickItem(name: name.isEmpty ? changed.source.name : name, amount: total, category: .other, suggested: .other)]
            } else {
                changed.items = changed.items.map { item in
                    let category = QuickEntryRules.category(for: item.name, aiGuess: nil)
                    return QuickItem(id: item.id, name: item.name, amount: item.amount, category: category, suggested: category)
                }
            }
            withAnimation(.snappy) {
                entry.wrappedValue = changed
                checked = [.flow]
            }
        } label: {
            Label(title, systemImage: flow == .moneyIn ? "arrow.down.left" : "arrow.up.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(isOn ? (flow == .moneyIn ? Theme.keyGreen : Theme.accent) : Theme.paper,
                            in: RoundedRectangle(cornerRadius: min(Theme.controlRadius, 18), style: .continuous))
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// A tick box, what the row is, and the value to check or change.
    private func checkRow<Value: View>(_ row: CheckRow, title: String, @ViewBuilder value: () -> Value) -> some View {
        let isChecked = checked.contains(row)
        return HStack(spacing: 12) {
            Button {
                KeyClick.play()
                if isChecked { checked.remove(row) } else { checked.insert(row) }
            } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(isChecked ? Theme.down : Theme.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) is right")
            .accessibilityValue(isChecked ? "Checked" : "Not checked")
            VStack(alignment: .leading, spacing: 4) {
                Text(Theme.cased(title)).font(Theme.label).foregroundStyle(Theme.muted)
                value()
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .sensoryFeedback(.selection, trigger: isChecked)
    }

    // MARK: Saving

    private var saveButton: some View {
        let ready = !allRows.isEmpty && allRows.allSatisfy(checked.contains) && entry.total > 0
        return VStack(spacing: 8) {
            Button(action: save) {
                Label(entry.flow == .moneyIn ? "Save money in" : "Save money out", systemImage: "checkmark")
            }
            .buttonStyle(BlockButtonStyle(prominent: true))
            .disabled(!ready)
            if !ready {
                Text(entry.total > 0 ? "Check every line to save." : "Add an amount to save.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    private func save() {
        guard isRead else { return }
        QuickEntryStore.save(entry, in: context)
        do {
            try context.save()
        } catch {
            saveError = error.localizedDescription
            return
        }
        text = ""
        isRead = false
        checked = []
        entry = .empty
        onSaved()
    }
}

/// Turns a checked reading into a saved entry and learns from any category the person changed.
enum QuickEntryStore {
    @discardableResult
    static func save(_ entry: QuickEntry, in context: ModelContext, learner: CategoryLearner = .shared) -> Receipt {
        let names = entry.items.map(\.name).filter { !$0.isEmpty }
        let receipt = Receipt(
            shopName: entry.flow == .moneyIn ? (names.first ?? entry.source.name) : (names.isEmpty ? "Typed entry" : names.joined(separator: ", ")),
            date: entry.date,
            total: entry.total,
            vat: 0,
            kind: .purchase,
            isFullTaxInvoice: false,
            reader: "Typed",
            rawText: entry.text
        )
        receipt.isIncome = entry.flow == .moneyIn
        receipt.incomeSource = entry.flow == .moneyIn ? entry.source : .other
        if entry.flow == .moneyOut { receipt.incomeSourceRaw = "" }
        context.insert(receipt)
        if entry.flow == .moneyOut {
            for (index, item) in entry.items.enumerated() {
                let line = LineItem(name: item.name.isEmpty ? "Item" : item.name, total: item.amount, category: item.category, position: index)
                context.insert(line)
                line.receipt = receipt
                if item.category != item.suggested, !item.name.isEmpty { learner.learn(item.name, as: item.category) }
            }
        }
        return receipt
    }
}
