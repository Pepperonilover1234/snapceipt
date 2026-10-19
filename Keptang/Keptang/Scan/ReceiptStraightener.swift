import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// Finds the receipt in a normal photo and flattens it, the way the document camera does.
/// Vision detects the paper's four corners; Core Image corrects the perspective.
enum ReceiptStraightener {
    private static let context = CIContext()

    static func straighten(_ image: UIImage) async -> UIImage {
        let upright = image.normalizedUp()
        guard let cgImage = upright.cgImage else { return image }

        return await Task.detached(priority: .userInitiated) { () -> UIImage in
            let request = VNDetectDocumentSegmentationRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let quad = request.results?.first,
                  quad.confidence > 0.5 else { return upright }

            // Already filling the frame: nothing to correct.
            let area = quad.boundingBox.width * quad.boundingBox.height
            if area > 0.95 { return upright }

            let input = CIImage(cgImage: cgImage)
            let size = input.extent.size
            func pixel(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * size.width, y: point.y * size.height)
            }

            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = input
            filter.topLeft = pixel(quad.topLeft)
            filter.topRight = pixel(quad.topRight)
            filter.bottomLeft = pixel(quad.bottomLeft)
            filter.bottomRight = pixel(quad.bottomRight)

            guard let output = filter.outputImage,
                  let corrected = context.createCGImage(output, from: output.extent) else { return upright }
            return UIImage(cgImage: corrected)
        }.value
    }
}
