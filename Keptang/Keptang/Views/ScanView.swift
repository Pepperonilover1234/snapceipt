import PhotosUI
import SwiftData
import SwiftUI

struct ScanView: View {
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var phase: Phase = .start
    @State private var step: ReceiptReader.Step = .straightening
    @State private var draft = ParsedReceipt()
    @State private var showingCamera = false
    /// Why the camera can't open right now, shown as an alert with a way forward.
    @State private var cameraProblem: CameraGate?
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?
    /// A saved receipt that looks like the one being saved.
    @State private var duplicate: Receipt?
    @State private var openedReceipt: Receipt?
    /// A photo sent through a chat bot, being read and checked right now.
    @State private var inboxPhoto: CloudSync.WaitingPhoto?
    @State private var openingInbox: String?
    /// A photo shared in from another app, being read and checked right now.
    @State private var sharedItem: SharedInbox.Item?
    /// The "Type it" screen.
    @State private var typing = LaunchOption.string("add") == "type"

    enum Phase {
        case start
        case reading(UIImage)
        case review
    }

    var body: some View {
        Group {
            switch phase {
            case .start:
                startScreen
            case .reading(let image):
                ReadingView(image: image, step: step)
            case .review:
                ReceiptReviewView(draft: $draft, onSave: save, onDiscard: {
                    // A discarded chat or shared photo stays in the inbox for later.
                    inboxPhoto = nil
                    sharedItem = nil
                    withAnimation { phase = .start }
                })
            }
        }
        .background(Theme.paper)
        .navigationTitle("Add")
        .navigationDestination(isPresented: $typing) { QuickEntryView(onSaved: onSaved) }
        .onChange(of: SharedInbox.shared.toOpen, initial: true) { _, item in
            // Something was just shared in: read it straight away and show the check.
            guard let item, case .start = phase else { return }
            SharedInbox.shared.toOpen = nil
            typing = false
            openShared(item)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentScanner(
                onFinish: { pages in
                    showingCamera = false
                    if let first = pages.first { process(first, alreadyStraight: true) }
                },
                onCancel: { showingCamera = false },
                onError: { error in
                    showingCamera = false
                    errorMessage = "The camera stopped: \(error.localizedDescription) You can choose a photo instead."
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    process(image, alreadyStraight: false)
                }
                photoItem = nil
            }
        }
        .confirmationDialog(
            "This receipt may already be saved",
            isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
            titleVisibility: .visible,
            presenting: duplicate
        ) { saved in
            Button("Open saved receipt") { openedReceipt = saved }
            Button("Save anyway") { commit() }
            Button("Cancel", role: .cancel) {}
        } message: { saved in
            Text("\(saved.shopName), \(saved.total.baht) on \(saved.date.formatted(date: .abbreviated, time: .shortened)) is already in your receipts. Saving again would count it twice.")
        }
        .navigationDestination(item: $openedReceipt) { ReceiptDetailView(receipt: $0) }
        .alert(cameraTitle, isPresented: Binding(get: { cameraProblem != nil }, set: { if !$0 { cameraProblem = nil } }),
               presenting: cameraProblem) { problem in
            if problem == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button("Try a sample receipt") { process(SampleReceipt.allCases[0].image(), alreadyStraight: true) }
            Button("OK", role: .cancel) {}
        } message: { problem in
            Text(cameraMessage(problem))
        }
        .alert("Couldn't read that receipt", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            ReceiptAI.prewarm()
            if let name = LaunchOption.string("sampleScan"), let sample = SampleReceipt(rawValue: name), case .start = phase {
                process(sample.image(), alreadyStraight: true)
            }
        }
    }

    /// Three ways in: scan with the camera, pick a photo from the album, or type it.
    private var startScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add money in or out")
                    .font(.system(.title, design: Skin.current.design, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
                Text("Scan a receipt, pick a photo of one, or just type “Pop corn 60”. Everything is read on this device, in Thai or English.")
                    .font(.body)
                    .foregroundStyle(Theme.muted)

                Button { Task { await openCamera() } } label: {
                    choice("Scan", detail: "Point the camera at a receipt or bill", symbol: "camera.viewfinder", fill: Theme.accent)
                }
                .buttonStyle(.plain)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    choice("Photo album", detail: "Pick a photo of a receipt you already took", symbol: "photo.on.rectangle", fill: Theme.sky)
                }
                .buttonStyle(.plain)
                if !CloudSync.shared.waitingPhotos.isEmpty || !SharedInbox.shared.items.isEmpty { inboxList }
                Button { typing = true } label: {
                    choice("Type it", detail: "“Pop corn 60”, “เงินเดือน 30000”: spending or income", symbol: "keyboard", fill: Theme.lime)
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(SampleReceipt.allCases) { sample in
                        Button { process(sample.image(), alreadyStraight: true) } label: {
                            Label(sample.title, systemImage: sample.symbol)
                        }
                    }
                } label: {
                    Label("Try a sample Thai receipt", systemImage: "sparkles")
                }
                .menuStyle(.button)
                .buttonStyle(BlockButtonStyle())

                VStack(alignment: .leading, spacing: 10) {
                    Label(OnDeviceAI.statusText, systemImage: OnDeviceAI.isAvailable ? "apple.intelligence" : "text.viewfinder")
                    Label("VAT 7% is worked out for every scanned receipt, and full tax invoices are flagged for your tax deduction.", systemImage: "percent")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .refreshable { await CloudSync.shared.sync(context) }
    }

    /// Receipt photos sent through a chat bot, waiting to be read here and checked.
    private var inboxList: some View {
        VStack(alignment: .leading, spacing: 8) {
            TitleChip("Inbox · shared with Snapceipt", tint: Theme.purple)
            ForEach(SharedInbox.shared.items) { item in
                HStack(spacing: 8) {
                    Button { openShared(item) } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let data = SharedInbox.shared.data(item), let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "photo").foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: min(Theme.radius, 10), style: .continuous))
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Shared receipt photo").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                Text(item.arrived.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            Text("Read").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accentText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Reads it and lets you check it before saving")
                    Button { SharedInbox.shared.remove(item) } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.quiet)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this shared photo")
                }
                .padding(.leading, 12)
                .padding(.vertical, 6)
                .block()
            }
            ForEach(CloudSync.shared.waitingPhotos) { photo in
                Button { open(photo) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.badge.arrow.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.onBright)
                            .frame(width: 44, height: 44)
                            .background(Theme.purple, in: RoundedRectangle(cornerRadius: min(Theme.radius, 14), style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Receipt photo from \(photo.origin == "line" ? "LINE" : "Discord")").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text((photo.caption.map { "“\($0)” · " } ?? "") + photo.sent.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if openingInbox == photo.id { ProgressView() } else {
                            Text("Read").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accentText)
                        }
                    }
                    .padding(12)
                    .block()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(openingInbox != nil)
                .accessibilityHint("Reads it and lets you check it before saving")
            }
        }
    }

    private func openShared(_ item: SharedInbox.Item) {
        guard let data = SharedInbox.shared.data(item), let image = UIImage(data: data) else {
            SharedInbox.shared.remove(item)
            errorMessage = "That shared file couldn’t be opened as a photo."
            return
        }
        sharedItem = item
        process(image, alreadyStraight: false)
    }

    private func open(_ photo: CloudSync.WaitingPhoto) {
        openingInbox = photo.id
        Task {
            defer { openingInbox = nil }
            do {
                let data = try await CloudSync.shared.photoData(photo)
                guard let image = UIImage(data: data) else { throw CloudError.http(0, "That file isn’t a photo.") }
                inboxPhoto = photo
                process(image, alreadyStraight: false)
            } catch {
                errorMessage = "Couldn’t get the photo from the cloud: \(error.localizedDescription)"
            }
        }
    }

    /// One big choice: an icon tile, a title and a line about it.
    private func choice(_ title: String, detail: String, symbol: String, fill: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.onBright)
                .frame(width: 56, height: 56)
                .background(fill, in: RoundedRectangle(cornerRadius: min(Theme.radius + 4, 28), style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(Skin.current == .gruv ? title.uppercased() : title)
                    .font(.system(.title3, design: Skin.current.design, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .block()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Opens the document camera, asking for permission first if needed, or explains why it can't.
    private func openCamera() async {
        switch CameraGate.current {
        case .open:
            showingCamera = true
        case .ask:
            if await CameraGate.requestAccess() { showingCamera = true } else { cameraProblem = .denied }
        case let problem:
            cameraProblem = problem
        }
    }

    private var cameraTitle: String {
        switch cameraProblem {
        case .unavailable: "No camera on this device"
        case .denied: "Camera access is off"
        case .restricted: "The camera is restricted"
        default: "Camera"
        }
    }

    private func cameraMessage(_ problem: CameraGate) -> String {
        switch problem {
        case .unavailable: "This device has no camera (the Simulator doesn't). Choose a photo of a receipt, or try a sample receipt."
        case .denied: "Turn on Camera for Snapceipt in Settings to scan receipts. Until then, you can choose a photo."
        case .restricted: "A Screen Time or device setting blocks the camera. You can still choose a photo."
        default: ""
        }
    }

    private func process(_ image: UIImage, alreadyStraight: Bool) {
        step = .straightening
        withAnimation { phase = .reading(image) }
        Task {
            do {
                let result = try await ReceiptReader.read(image, alreadyStraight: alreadyStraight) { newStep in
                    withAnimation { step = newStep }
                }
                draft = result
                #if DEBUG
                print(result.debugSummary)
                #endif
                withAnimation { phase = .review }
            } catch {
                errorMessage = error.localizedDescription
                withAnimation { phase = .start }
            }
        }
    }

    private func save() {
        if let saved = savedDuplicate() {
            duplicate = saved
        } else {
            commit()
        }
    }

    /// A receipt already saved with the same shop, total and time, if there is one.
    private func savedDuplicate() -> Receipt? {
        let window = DuplicateCheck.searchWindow(around: draft.date)
        let start = window.start
        let end = window.end
        let nearby = (try? context.fetch(FetchDescriptor<Receipt>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        return DuplicateCheck.firstMatch(shop: draft.shopName, total: draft.total, date: draft.date,
                                         among: nearby.map(\.duplicateCandidate)).map { nearby[$0] }
    }

    private func commit() {
        learnCorrections()
        Receipt.insert(draft, into: context)
        do {
            try context.save()
        } catch {
            errorMessage = "The receipt couldn't be saved: \(error.localizedDescription)"
            return
        }
        draft = ParsedReceipt()
        phase = .start
        if let photo = inboxPhoto {
            inboxPhoto = nil
            Task { await CloudSync.shared.finished(photo, saved: true) }
        }
        if let item = sharedItem {
            sharedItem = nil
            SharedInbox.shared.remove(item)
        }
        onSaved()
    }

    /// Remembers each re-sorted item, and the merchant when every item was moved to the same category.
    private func learnCorrections() {
        let learner = CategoryLearner.shared
        for item in draft.items where item.category != item.suggestedCategory && !item.name.isEmpty {
            learner.learn(item.name, as: item.category)
        }
        let products = draft.items.filter { !$0.name.isEmpty && !ReceiptReader.isAdjustment($0) }
        if !draft.kind.isBill, !products.isEmpty,
           products.allSatisfy({ $0.category != $0.suggestedCategory }),
           let category = products.first?.category, products.allSatisfy({ $0.category == category }) {
            learner.learnMerchant(draft.shopName, as: category)
        }
    }
}

struct ReadingView: View {
    let image: UIImage
    let step: ReceiptReader.Step

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityLabel("The receipt being read")

                VStack(alignment: .leading, spacing: 14) {
                    ScanningLED()
                    ForEach(ReceiptReader.Step.allCases, id: \.self) { item in
                        HStack(spacing: 12) {
                            Group {
                                if item.rawValue < step.rawValue {
                                    Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.ink)
                                } else if item == step {
                                    ProgressView().tint(Theme.ink)
                                } else {
                                    Image(systemName: "square").foregroundStyle(Theme.quiet)
                                }
                            }
                            .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(.headline, weight: .semibold)).foregroundStyle(Theme.ink)
                                Text(item.detail).font(.subheadline).foregroundStyle(Theme.muted)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(item.rawValue < step.rawValue ? "Done" : item == step ? "In progress" : "Waiting")
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
    }
}

struct ReceiptReviewView: View {
    @Binding var draft: ParsedReceipt
    var onSave: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        CardPage {
            CardSection(title: "Receipt", color: .orange) {
                HStack(alignment: .top, spacing: 14) {
                    if let data = draft.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Check and save").font(Theme.label).foregroundStyle(Theme.ink)
                        Text("Read by \(draft.reader.rawValue). Fix anything that looks wrong.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        if draft.isFullTaxInvoice { Badge(text: "Full tax invoice", fill: Theme.lime) }
                    }
                }
                .padding(.vertical, 10)
                LabeledContent("Shop") {
                    TextField("Shop name", text: $draft.shopName)
                        .multilineTextAlignment(.trailing)
                        .font(.body.weight(.semibold))
                }
                DateField(title: "Date", date: $draft.date)
                LabeledContent("Type") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ReceiptKind.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden()
                }
                if draft.kind.isBill, let unit = draft.kind.unit {
                    LabeledContent("Used (\(unit))") {
                        TextField("0", value: $draft.billUnits, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(Theme.figure())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                CardSection(title: "\(draft.items.count) items", color: .pink) {
                    ForEach($draft.items) { $item in
                        DraftItemRow(item: $item)
                            .contextMenu {
                                Button("Remove item", systemImage: "trash", role: .destructive) { remove(item) }
                            }
                            .accessibilityAction(named: "Remove item") { remove(item) }
                    }
                    RowButton(title: "Add item", symbol: "plus") {
                        draft.items.append(ParsedItem(name: "", total: 0))
                    }
                }
                itemsCheck
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 4)
                Text("Touch and hold an item to remove it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }

            CardSection(title: "Totals and tax", color: .yellow) {
                LabeledContent("Total paid") {
                    BahtField(title: "Total paid", value: $draft.total, style: .headline)
                }
                AmountRow("Price before VAT", (draft.total - draft.vat).baht)
                AmountRow("VAT 7% included", draft.vat.baht)
                Toggle("Full tax invoice (ใบกำกับภาษีเต็มรูป)", isOn: $draft.isFullTaxInvoice)
                if !draft.sellerTaxID.isEmpty {
                    AmountRow("Seller tax ID", draft.sellerTaxID)
                }
            }

            if !draft.rawText.isEmpty {
                CardSection {
                    DisclosureGroup("Text read from the photo") {
                        Text(draft.rawText).font(.caption.monospaced())
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard", role: .destructive, action: onDiscard)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: onSave).bold()
            }
        }
        .onChange(of: draft.total) { oldTotal, newTotal in
            // Keep VAT in step when the total is corrected by hand.
            if abs(draft.vat - ThaiTax.vatIncluded(in: oldTotal)) < 0.02 {
                draft.vat = ThaiTax.vatIncluded(in: newTotal)
            }
        }
    }

    private func remove(_ item: ParsedItem) {
        draft.items.removeAll { $0.id == item.id }
    }

    @ViewBuilder
    private var itemsCheck: some View {
        let difference = draft.itemsTotal - draft.total
        if abs(difference) < 0.5 {
            Label("Items add up to the total", systemImage: "checkmark.square.fill")
                .foregroundStyle(Theme.down)
        } else {
            Label("Items add up to \(draft.itemsTotal.baht), \(abs(difference).baht) \(difference > 0 ? "more" : "less") than the total",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.up)
        }
    }
}

struct DraftItemRow: View {
    @Binding var item: ParsedItem

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Category", selection: $item.category) {
                    ForEach(SpendCategory.selectable) { Label($0.name, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                CategoryIcon(symbol: item.category.symbol, size: 34, fill: item.category.color)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Category: \(item.category.name)")
            .accessibilityHint("Changes this item's category")
            VStack(alignment: .leading, spacing: 2) {
                TextField("Item", text: $item.name)
                HStack(spacing: 4) {
                    Text(item.category.name)
                    if item.quantity != 1 {
                        Text("· \(item.quantity.formatted()) × \(item.unitPrice.baht)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            }
            BahtField(title: "Price of \(item.name.isEmpty ? "item" : item.name)", value: $item.total, style: .subheadline)
        }
    }
}

/// An orange LED that pulses while a receipt is being read.
struct ScanningLED: View {
    @State private var bright = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            LED(on: bright || reduceMotion)
            Text("reading").font(.system(.caption, design: Skin.current.design, weight: .medium)).foregroundStyle(Theme.muted)
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                bright.toggle()
            }
        }
        .accessibilityHidden(true)
    }
}
