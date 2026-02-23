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
    private static let defaultOperationTimeoutSeconds: TimeInterval = 120

    public init() {}

    public func metadata(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if canImport(AVFoundation)
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("media.metadata.read requires path")
        }

        let url = try context.pathPolicy.resolve(path: path)
        let loaded = try waitForAsyncOperation {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.load(.tracks)

            var summaries: [JSONValue] = []
            summaries.reserveCapacity(tracks.count)

            for track in tracks {
                let naturalSize = try await track.load(.naturalSize)
                let estimatedDataRate = try await track.load(.estimatedDataRate)
                summaries.append(
                    .object([
                        "mediaType": .string(track.mediaType.rawValue),
                        "naturalWidth": .number(Double(naturalSize.width)),
                        "naturalHeight": .number(Double(naturalSize.height)),
                        "estimatedDataRate": .number(Double(estimatedDataRate)),
                    ])
                )
            }

            return (duration: duration, tracks: summaries)
        }

        let durationSeconds = CMTimeGetSeconds(loaded.duration)
        return .object([
            "path": .string(url.path),
            "durationSeconds": .number(durationSeconds.isFinite ? durationSeconds : 0),
            "tracks": .array(loaded.tracks),
        ])
        #else
        _ = arguments
        _ = context
        throw BridgeError.unsupportedPlatform("AVFoundation")
        #endif
    }

    public func extractFrame(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if canImport(AVFoundation) && canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
        guard let inputPath = arguments.string("path") else {
            throw BridgeError.invalidArguments("media.frame.extract requires path")
        }

        let inputURL = try context.pathPolicy.resolve(path: inputPath)
        let outputPath = arguments.string("outputPath") ?? "tmp:frame-\(UUID().uuidString).jpg"
        let outputURL = try context.pathPolicy.resolve(path: outputPath)
        let timeMs = arguments.double("timeMs") ?? 0

        let cgImage = try waitForAsyncOperation {
            let asset = AVURLAsset(url: inputURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            let cmTime = CMTime(seconds: timeMs / 1_000, preferredTimescale: 600)
            return try await generator.image(at: cmTime).image
        }

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
        _ = context
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

        try waitForAsyncOperation(timeoutSeconds: 300) {
            let asset = AVURLAsset(url: inputURL)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
                throw BridgeError.nativeFailure("Unable to create export session for preset \(preset)")
            }

            exporter.shouldOptimizeForNetworkUse = true
            try await exporter.export(to: outputURL, as: .mp4)
            return ()
        }

        let artifact = try context.artifactStore.register(url: outputURL, mimeType: "video/mp4")
        return .object([
            "path": .string(outputURL.path),
            "artifactID": .string(artifact.id),
            "preset": .string(preset),
        ])
        #else
        _ = arguments
        _ = context
        throw BridgeError.unsupportedPlatform("AVFoundation transcode")
        #endif
    }

    private func waitForAsyncOperation<T: Sendable>(
        timeoutSeconds: TimeInterval = MediaBridge.defaultOperationTimeoutSeconds,
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SynchronizedBox<Result<T, Error>?>(nil)

        let task = Task(priority: .userInitiated) {
            do {
                let value = try await operation()
                resultBox.set(.success(value))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            task.cancel()
            throw BridgeError.timeout(milliseconds: Int(timeoutSeconds * 1_000))
        }

        guard let result = resultBox.get() else {
            throw BridgeError.nativeFailure("Media operation produced no result")
        }

        return try result.get()
    }
}
