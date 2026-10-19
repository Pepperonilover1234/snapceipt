import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share → Snapceipt" from Photos, LINE, Files, Mail or Safari. Each photo, screenshot or PDF is
/// saved as a JPEG in the folder the app and this extension share; the app reads it on the phone
/// and shows the usual check before anything is saved.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareCard(model: model, onDone: { [weak self] in self?.finish() },
                                                           onOpen: { [weak self] in self?.openApp() }))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await receive() }
    }

    private func receive() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var saved = 0
        for provider in providers {
            if let jpeg = await SharedFiles.jpeg(from: provider), SharedFiles.save(jpeg) { saved += 1 }
        }
        await MainActor.run { model.saved = saved; model.done = true }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Opens Snapceipt on what was just shared. Share extensions have no direct way to open their
    /// app, so this walks up to the application object; if that's not allowed, the app still
    /// picks the photos up the next time it opens.
    private func openApp() {
        guard let url = URL(string: "snapceipt://shared") else { return finish() }
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = current.next
        }
        finish()
    }
}

@Observable
final class ShareModel {
    var done = false
    var saved = 0
}

struct ShareCard: View {
    let model: ShareModel
    let onDone: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: model.done ? (model.saved > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") : "doc.viewfinder")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(model.done && model.saved == 0 ? .red : Color(red: 1, green: 0.353, blue: 0))
                Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if model.done && model.saved > 0 {
                    Button(action: onOpen) {
                        Text("Check it in Snapceipt").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 1, green: 0.353, blue: 0))
                }
                Button(model.done ? "Done" : "Cancel", action: onDone)
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding()
            Spacer()
        }
    }

    private var title: String {
        guard model.done else { return "Sending to Snapceipt…" }
        if model.saved == 0 { return "Nothing to send" }
        return model.saved == 1 ? "Sent to Snapceipt" : "\(model.saved) receipts sent to Snapceipt"
    }

    private var detail: String {
        guard model.done else { return "" }
        if model.saved == 0 { return "Share a photo, screenshot or PDF of a receipt." }
        return "Snapceipt reads \(model.saved == 1 ? "it" : "them") on this device and asks you to check before saving."
    }
}

/// The folder the app and the extension share, and how files are put there.
enum SharedFiles {
    static let group = "group.com.pepperonilover1234.keptang"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("SharedInbox", isDirectory: true)
    }

    static func save(_ jpeg: Data) -> Bool {
        guard let folder else { return false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(Int(Date.now.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).jpg"
        return (try? jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil
    }

    /// A JPEG of the shared item: photos as they are (HEIC and PNG converted), a PDF's first page drawn.
    static func jpeg(from provider: NSItemProvider) async -> Data? {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
           let data = await load(provider, type: .pdf), let page = PDFDocument(data: data)?.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(2400 / max(bounds.width, bounds.height), 4)
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            return image.jpegData(compressionQuality: 0.85)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let data = await load(provider, type: .image), let image = UIImage(data: data) {
            return downscaled(image).jpegData(compressionQuality: 0.85)
        }
        return nil
    }

    private static func load(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// At most 3000 points on the long side: plenty to read, small enough to keep.
    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 3000 else { return image }
        let scale = 3000 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
