import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public final class MediaBridge: @unchecked Sendable {
    public init() {}

    public func metadata(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if canImport(AVFoundation)
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("media.metadata.read requires path")
        }

        let url = try context.pathPolicy.resolve(path: path)
        let asset = AVURLAsset(url: url)

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let tracks = asset.tracks.map { track in
            JSONValue.object([
                "mediaType": .string(track.mediaType.rawValue),
                "naturalWidth": .number(Double(track.naturalSize.width)),
                "naturalHeight": .number(Double(track.naturalSize.height)),
                "estimatedDataRate": .number(Double(track.estimatedDataRate)),
            ])
        }

        return .object([
            "path": .string(url.path),
            "durationSeconds": .number(durationSeconds.isFinite ? durationSeconds : 0),
            "tracks": .array(tracks),
        ])
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("AVFoundation")
        #endif
    }

    public func extractFrame(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if canImport(AVFoundation) && canImport(ImageIO) && canImport(CoreGraphics)
        guard let inputPath = arguments.string("path") else {
            throw BridgeError.invalidArguments("media.frame.extract requires path")
        }

        let inputURL = try context.pathPolicy.resolve(path: inputPath)
        let outputPath = arguments.string("outputPath") ?? "tmp:frame-\(UUID().uuidString).jpg"
        let outputURL = try context.pathPolicy.resolve(path: outputPath)

        let timeMs = arguments.double("timeMs") ?? 0
        let asset = AVURLAsset(url: inputURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let cmTime = CMTime(seconds: timeMs / 1000, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw BridgeError.nativeFailure("Unable to create image destination")
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BridgeError.nativeFailure("Unable to finalize image output")
        }

        let artifact = try context.artifactStore.register(url: outputURL, mimeType: "image/jpeg")
        return .object([
            "path": .string(outputURL.path),
            "artifactID": .string(artifact.id),
        ])
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("AVFoundation frame extraction")
        #endif
    }

    public func transcode(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if canImport(AVFoundation)
        guard let inputPath = arguments.string("path") else {
            throw BridgeError.invalidArguments("media.transcode requires path")
        }

        let inputURL = try context.pathPolicy.resolve(path: inputPath)
        let outputPath = arguments.string("outputPath") ?? "tmp:transcoded-\(UUID().uuidString).mp4"
        let outputURL = try context.pathPolicy.resolve(path: outputPath)
        let preset = arguments.string("preset") ?? AVAssetExportPresetMediumQuality

        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw BridgeError.nativeFailure("Unable to create export session for preset \(preset)")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        let semaphore = DispatchSemaphore(value: 0)
        exporter.exportAsynchronously {
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 120)

        guard exporter.status == .completed else {
            throw BridgeError.nativeFailure("Transcode failed: \(exporter.error?.localizedDescription ?? "unknown")")
        }

        let artifact = try context.artifactStore.register(url: outputURL, mimeType: "video/mp4")
        return .object([
            "path": .string(outputURL.path),
            "artifactID": .string(artifact.id),
            "preset": .string(preset),
        ])
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("AVFoundation transcode")
        #endif
    }
}
