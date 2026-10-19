import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmingReset = false
    @Query(sort: \Receipt.date) private var allReceipts: [Receipt]
    @AppStorage("exportPhotos") private var exportPhotos = false
    @State private var exportFile: ExportFile?
    @State private var importing = false
    @State private var importMessage: String?
    @State private var confirmingClear = false
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("skin") private var skin: Skin = .console
    @AppStorage("colour") private var colour: Paint = .console
    @AppStorage("keyClicks") private var keyClicks = false
    /// `-sheet chatbots` opens Settings straight on Chat bots.
    @State private var showingChatBots = LaunchOption.string("sheet") == "chatbots"

    var body: some View {
        NavigationStack {
            CardPage {
                CardSection(title: "Colour", note: "Each colour has a light and a dark version.", color: .pink) {
                    ForEach(Paint.allCases) { option in
                        pickerRow(title: option.name, blurb: option.blurb, chosen: colour == option) {
                            HStack(spacing: 0) {
                                ForEach(Array(option.swatch.enumerated()), id: \.offset) { _, fill in
                                    Rectangle().fill(fill).frame(width: 12, height: 28)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        } action: { colour = option }
                    }
                }

                CardSection(title: "Style", note: "Type, spacing, corners and borders. Mix any style with any colour.", color: .sky) {
                    ForEach(Skin.allCases) { option in
                        pickerRow(title: option.name, blurb: option.blurb, chosen: skin == option) {
                            Text(option.cased("Aa"))
                                .font(.system(.title3, design: option.design, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 48, height: 30)
                                .background(Theme.paper, in: RoundedRectangle(cornerRadius: min(option.radius, 10), style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: min(option.radius, 10), style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: max(option.rule, 1)))
                        } action: { skin = option }
                    }
                }

                CardSection(title: "Appearance", note: "Text follows your device's text size, Bold Text and Increase Contrast settings.", color: .yellow) {
                    ForEach(Appearance.allCases) { option in
                        Button { appearance = option } label: {
                            HStack(spacing: 12) {
                                Label(option.name, systemImage: option.symbol)
                                Spacer(minLength: 8)
                                if appearance == option {
                                    Image(systemName: "checkmark").font(.body.weight(.heavy))
                                }
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(appearance == option ? .isSelected : [])
                    }
                }

                CardSection(title: "Chat bots", note: "Send receipts and “Pop corn 60” to Snapceipt from Discord.", color: .purple) {
                    Button { showingChatBots = true } label: {
                        HStack {
                            Label(CloudSync.shared.linked.isEmpty ? "Connect Discord" : "Discord connected", systemImage: "bubble.left.and.text.bubble.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                CardSection(title: "Sound", note: "A soft click when you press keys and turn the knob.") {
                    Toggle("Key clicks", isOn: $keyClicks)
                }

                CardSection(title: "On this device", note: "Photos, receipts and your tax details never leave this device.", color: .sky) {
                    LabeledContent("Apple Intelligence", value: OnDeviceAI.isAvailable ? "On" : "Off")
                    Text(OnDeviceAI.statusText).font(.subheadline).foregroundStyle(Theme.muted).padding(.vertical, 6)
                    LabeledContent("Text reading (Vision)", value: ReceiptOCR.languageSummary)
                    LabeledContent("Category model (Create ML)", value: CategoryLearner.shared.hasCreateMLModel ? "Loaded" : "Not added")
                    LabeledContent("Items you've re-sorted", value: "\(CategoryLearner.shared.learnedCount)")
                }

                CardSection(title: "How a scan works", color: .mint) {
                    Label("Document camera or Vision finds the receipt edges and flattens the photo", systemImage: "crop")
                    Label("Vision reads every printed line in Thai and English", systemImage: "text.viewfinder")
                    Label("Apple Intelligence turns the lines into items, prices, total and VAT with Guided Generation", systemImage: "sparkles")
                    Label("A Create ML model and your corrections sort each item into a category", systemImage: "square.grid.2x2")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ink)

                CardSection(title: "Your data", note: "A backup holds every receipt, income, item and your corrections, to keep or move to another device. The spreadsheet opens in Excel, Numbers or Google Sheets. Import takes a Snapceipt backup or a CSV (from a bank or another app); anything already here is skipped.", color: .sky) {
                    Toggle("Include receipt photos in backups", isOn: $exportPhotos)
                    RowButton(title: "Export backup (\(allReceipts.count) entries)", symbol: "square.and.arrow.up") { exportBackup() }
                    RowButton(title: "Export spreadsheet (CSV)", symbol: "tablecells") { exportSpreadsheet() }
                    RowButton(title: "Import a backup or CSV…", symbol: "square.and.arrow.down") { importing = true }
                }

                CardSection(title: "Data", color: .coral) {
                    RowButton(title: "Reload sample data", symbol: "arrow.clockwise") { confirmingReset = true }
                    RowButton(title: "Start empty", symbol: "trash", destructive: true) { confirmingClear = true }
                    RowButton(title: "Forget my category corrections", symbol: "arrow.uturn.backward") { CategoryLearner.shared.forgetAll() }
                }
            }
            .navigationTitle("Settings")
            .fileExporter(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
                          document: exportFile, contentType: exportFile?.type ?? .json,
                          defaultFilename: exportFile?.name) { result in
                if case .failure(let error) = result { importMessage = "Couldn’t save the file: \(error.localizedDescription)" }
                exportFile = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText, .plainText]) { result in
                importFrom(result)
            }
            .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(importMessage ?? "")
            }
            .navigationDestination(isPresented: $showingChatBots) { ChatBotsView() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Replace all receipts with six months of sample data?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reload sample data", role: .destructive) {
                    SampleData.reset(in: context)
                    dismiss()
                }
            }
            .confirmationDialog("Delete every receipt?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Delete all receipts", role: .destructive) {
                    SampleData.removeAll(in: context)
                    dismiss()
                }
            }
        }
    }

    private func pickerRow<Sample: View>(title: String, blurb: String, chosen: Bool,
                                         @ViewBuilder sample: () -> Sample, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                sample()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(blurb).font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                if chosen { Image(systemName: "checkmark").font(.body.weight(.heavy)) }
            }
            .foregroundStyle(Theme.ink)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var stamp: String { DateFormatter.fixed("yyyy-MM-dd").string(from: .now) }

    private func exportBackup() {
        do {
            let backup = DataTransfer.backup(of: allReceipts, includePhotos: exportPhotos)
            exportFile = ExportFile(data: try DataTransfer.encode(backup), type: .json, name: "Snapceipt backup \(stamp).json")
        } catch {
            importMessage = "Couldn’t make the backup: \(error.localizedDescription)"
        }
    }

    private func exportSpreadsheet() {
        exportFile = ExportFile(data: Data(DataTransfer.csv(of: allReceipts).utf8), type: .commaSeparatedText, name: "Snapceipt \(stamp).csv")
    }

    private func importFrom(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let outcome = try DataTransfer.importFile(try Data(contentsOf: url), into: context)
            importMessage = outcome.summary + "."
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

/// A file handed to the system's save sheet.
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    var type: UTType
    var name: String

    init(data: Data, type: UTType, name: String) {
        self.data = data
        self.type = type
        self.name = name
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = configuration.contentType
        name = "Snapceipt"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
