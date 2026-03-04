import Foundation

#if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
import Vision
import ImageIO
import CoreGraphics
#endif

public final class VisionBridge: @unchecked Sendable {
    public init() {}

    public func analyzeImage(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path"), path.isEmpty == false else {
            throw BridgeError.invalidArguments("vision.image.analyze requires path")
        }

        let maxResults = max(1, arguments.int("maxResults") ?? 5)
        let featureList = arguments.array("features")?.compactMap(\.stringValue).map { $0.lowercased() } ?? ["labels", "text"]
        let features = Set(featureList)

        #if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
        let url = try context.pathPolicy.resolve(path: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw BridgeError.nativeFailure("vision.image.analyze could not load image at \(url.path)")
        }

        var payload: [String: JSONValue] = [
            "path": .string(url.path),
            "features": .array(features.sorted().map { .string($0) }),
        ]

        if features.contains("labels") || features.contains("classify") {
            let request = VNClassifyImageRequest()
            try perform(image: image, request: request)
            let observations = (request.results ?? [])
                .prefix(maxResults)
                .map { observation in
                    JSONValue.object([
                        "identifier": .string(observation.identifier),
                        "confidence": .number(Double(observation.confidence)),
                    ])
                }
            payload["labels"] = .array(Array(observations))
        }

        if features.contains("text") {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try perform(image: image, request: request)
            let observations = (request.results ?? [])
                .prefix(maxResults)
                .compactMap { observation -> JSONValue? in
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }
                    return .object([
                        "text": .string(candidate.string),
                        "confidence": .number(Double(candidate.confidence)),
                        "boundingBox": .object([
                            "x": .number(Double(observation.boundingBox.origin.x)),
                            "y": .number(Double(observation.boundingBox.origin.y)),
                            "width": .number(Double(observation.boundingBox.size.width)),
                            "height": .number(Double(observation.boundingBox.size.height)),
                        ]),
                    ])
                }
            payload["text"] = .array(Array(observations))
        }

        if features.contains("barcodes") || features.contains("barcode") {
            let request = VNDetectBarcodesRequest()
            try perform(image: image, request: request)
            let observations = (request.results ?? [])
                .prefix(maxResults)
                .map { observation in
                    JSONValue.object([
                        "payload": .string(observation.payloadStringValue ?? ""),
                        "symbology": .string(observation.symbology.rawValue),
                        "confidence": .number(Double(observation.confidence)),
                    ])
                }
            payload["barcodes"] = .array(Array(observations))
        }

        return .object(payload)
        #else
        _ = context
        throw BridgeError.unsupportedPlatform("Vision")
        #endif
    }

    #if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
    private func perform(image: CGImage, request: VNRequest) throws {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw BridgeError.nativeFailure("vision.image.analyze failed: \(error.localizedDescription)")
        }
    }
    #endif
}
