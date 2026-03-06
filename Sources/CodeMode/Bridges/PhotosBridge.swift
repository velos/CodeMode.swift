import Foundation

#if canImport(Photos)
import Photos
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public final class PhotosBridge: @unchecked Sendable {
    public init() {}

    public func read(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.photoLibrary)
        }

        #if canImport(Photos)
        let limit = max(1, arguments.int("limit") ?? 50)
        let mediaTypeFilter = (arguments.string("mediaType") ?? "any").lowercased()

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets: PHFetchResult<PHAsset>
        switch mediaTypeFilter {
        case "image", "photo":
            assets = PHAsset.fetchAssets(with: .image, options: options)
        case "video":
            assets = PHAsset.fetchAssets(with: .video, options: options)
        default:
            assets = PHAsset.fetchAssets(with: options)
        }

        var entries: [JSONValue] = []
        entries.reserveCapacity(limit)

        assets.enumerateObjects { asset, _, stop in
            entries.append(
                .object([
                    "localIdentifier": .string(asset.localIdentifier),
                    "mediaType": .string(self.mediaTypeString(asset.mediaType)),
                    "pixelWidth": .number(Double(asset.pixelWidth)),
                    "pixelHeight": .number(Double(asset.pixelHeight)),
                    "durationSeconds": .number(asset.mediaType == .video ? asset.duration : 0),
                    "creationDate": .string(asset.creationDate?.ISO8601Format() ?? ""),
                    "modificationDate": .string(asset.modificationDate?.ISO8601Format() ?? ""),
                ])
            )

            if entries.count >= limit {
                stop.pointee = true
            }
        }

        return .array(entries)
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("Photos")
        #endif
    }

    public func export(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let localIdentifier = arguments.string("localIdentifier"), localIdentifier.isEmpty == false else {
            throw BridgeError.invalidArguments("photos.export requires localIdentifier")
        }

        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.photoLibrary)
        }

        #if canImport(Photos)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else {
            throw BridgeError.invalidArguments("photos.export could not find asset for localIdentifier \(localIdentifier)")
        }

        let outputPath = arguments.string("outputPath") ?? defaultOutputPath(for: asset)
        let outputURL = try context.pathPolicy.resolve(path: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let resource = try preferredResource(for: asset)
        let requestOptions = PHAssetResourceRequestOptions()
        requestOptions.isNetworkAccessAllowed = true

        let semaphore = DispatchSemaphore(value: 0)
        let writeError = LockedBox<Error?>(nil)

        PHAssetResourceManager.default().writeData(for: resource, toFile: outputURL, options: requestOptions) { error in
            writeError.set(error)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 60) == .timedOut {
            throw BridgeError.timeout(milliseconds: 60_000)
        }

        if let writeError = writeError.get() {
            throw BridgeError.nativeFailure("photos.export failed: \(writeError.localizedDescription)")
        }

        let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.doubleValue ?? 0
        let mimeType = mimeType(for: resource.uniformTypeIdentifier)
        let artifact = try context.artifactStore.register(url: outputURL, mimeType: mimeType)

        return .object([
            "localIdentifier": .string(localIdentifier),
            "path": .string(outputURL.path),
            "artifactID": .string(artifact.id),
            "mediaType": .string(mediaTypeString(asset.mediaType)),
            "uniformTypeIdentifier": .string(resource.uniformTypeIdentifier),
            "bytes": .number(bytes),
        ])
        #else
        _ = arguments
        _ = localIdentifier
        throw BridgeError.unsupportedPlatform("Photos export")
        #endif
    }

    private func resolvePermission(context: BridgeInvocationContext) -> PermissionStatus {
        context.resolvedPermission(for: .photoLibrary)
    }

    #if canImport(Photos)
    private func defaultOutputPath(for asset: PHAsset) -> String {
        switch asset.mediaType {
        case .image:
            return "tmp:photo-\(UUID().uuidString).jpg"
        case .video:
            return "tmp:video-\(UUID().uuidString).mov"
        default:
            return "tmp:asset-\(UUID().uuidString).bin"
        }
    }

    private func preferredResource(for asset: PHAsset) throws -> PHAssetResource {
        let resources = PHAssetResource.assetResources(for: asset)
        guard resources.isEmpty == false else {
            throw BridgeError.nativeFailure("No exportable Photos resources were found.")
        }

        if asset.mediaType == .image,
           let photo = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto })
        {
            return photo
        }

        if asset.mediaType == .video,
           let video = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo })
        {
            return video
        }

        return resources[0]
    }

    private func mediaTypeString(_ mediaType: PHAssetMediaType) -> String {
        switch mediaType {
        case .image:
            return "image"
        case .video:
            return "video"
        case .audio:
            return "audio"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }

    private func mimeType(for uniformTypeIdentifier: String) -> String? {
        #if canImport(UniformTypeIdentifiers)
        if #available(iOS 14.0, macOS 11.0, *) {
            return UTType(uniformTypeIdentifier)?.preferredMIMEType
        }
        #endif
        return nil
    }
    #endif
}
