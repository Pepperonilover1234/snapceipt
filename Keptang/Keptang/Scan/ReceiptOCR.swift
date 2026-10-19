import UIKit
import Vision

/// Reads the printed text on a receipt with Vision, on the device.
enum ReceiptOCR {
    enum OCRError: LocalizedError {
        case noImage, noText

        var errorDescription: String? {
            switch self {
            case .noImage: "The photo couldn't be opened."
            case .noText: "No text was found. Try a sharper photo with the whole receipt in view."
            }
        }
    }

    /// Thai first so Thai shop and item names win when a line is ambiguous.
    static let preferredLanguages = ["th-TH", "en-US"]

    static var supportedLanguages: [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    static var languageSummary: String {
        supportedLanguages.contains("th-TH") ? "Thai + English" : "English only on this system"
    }

    /// Returns the receipt's text as printed rows, top to bottom.
    /// Words Vision finds on the same row ("Milk", "2 x 45.00", "90.00") are joined into one line.
    static func lines(in image: UIImage) async throws -> [String] {
        let upright = image.normalizedUp()
        guard let cgImage = upright.cgImage else { throw OCRError.noImage }

        let lines = try await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let languages = preferredLanguages.filter(supported.contains)
            if !languages.isEmpty { request.recognitionLanguages = languages }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            return groupIntoRows(request.results ?? [])
        }.value

        guard !lines.isEmpty else { throw OCRError.noText }
        return lines
    }

    static func groupIntoRows(_ observations: [VNRecognizedTextObservation]) -> [String] {
        let pieces: [(text: String, box: CGRect)] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, observation.boundingBox)
        }
        // Vision's origin is bottom-left, so higher midY means higher on the page.
        .sorted { $0.box.midY > $1.box.midY }

        var rows: [[(text: String, box: CGRect)]] = []
        for piece in pieces {
            if let anchor = rows.last?.first,
               abs(anchor.box.midY - piece.box.midY) < max(anchor.box.height, piece.box.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ")
        }
    }
}

extension UIImage {
    /// Redraws the image so its pixels are upright, which keeps Vision and Core Image coordinates simple.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Shrinks very large camera photos before storing or reading them.
    func limited(toLongSide maxSide: CGFloat) -> UIImage {
        let longSide = max(size.width, size.height) * scale
        guard longSide > maxSide else { return self }
        let factor = maxSide / longSide
        let newSize = CGSize(width: size.width * scale * factor, height: size.height * scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
