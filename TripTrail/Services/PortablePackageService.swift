import Foundation

enum PortablePackageKind: String, Codable, Equatable {
    case backup
    case sharedJourney
}

struct PortablePackageExportResult {
    let url: URL
    let mediaCount: Int
    let mediaBytes: Int64
    var skippedMedia: [String] = []
}

struct PortablePackageMediaEntry: Codable, Equatable {
    let referenceID: UUID
    let kindRaw: String
    let originalFilename: String
    let uniformTypeIdentifier: String
    let byteCount: Int64
}

struct OpenedPortablePackage {
    let url: URL
    let kind: PortablePackageKind
    let contentData: Data
    let media: [PortablePackageMediaEntry]
    let payloadOffset: UInt64
}

enum PortablePackageError: LocalizedError {
    case oversizedContent
    case invalidPackage
    case unsupportedVersion(Int)
    case wrongPackageKind
    case missingMedia(String)
    case truncatedMedia(String)

    var errorDescription: String? {
        switch self {
        case .oversizedContent:
            "备份内容超过 64 MB，请减少凭证文件大小后再导出。"
        case .invalidPackage:
            "这不是有效的旅迹文件。"
        case .unsupportedVersion(let version):
            "该媒体包版本为 \(version)，当前 App 暂不支持。"
        case .wrongPackageKind:
            "文件内容类型与当前操作不匹配。"
        case .missingMedia(let name):
            "无法读取媒体“\(name)”，请确认原素材仍在相簿中并已从 iCloud 下载。"
        case .truncatedMedia(let name):
            "媒体“\(name)”数据不完整，文件可能已损坏。"
        }
    }
}

@MainActor
enum PortablePackageService {
    private static let magic = Data("TRIPTRAILPKG1\n".utf8)
    private static let formatName = "triptrail.portable-package"
    private static let formatVersion = 1
    private static let chunkSize = 1_048_576
    private static let maximumManifestSize = 64 * 1_048_576

    private struct Manifest: Codable {
        let format: String
        let formatVersion: Int
        let kind: PortablePackageKind
        let contentData: Data
        let media: [PortablePackageMediaEntry]
    }

    private struct ExportedPayload {
        let entry: PortablePackageMediaEntry
        let fileURL: URL
    }

    static func makePackage(
        kind: PortablePackageKind,
        contentData: Data,
        mediaReferences: [MediaReference],
        fileExtension: String,
        skipUnavailableMedia: Bool = false
    ) async throws -> PortablePackageExportResult {
        let uniqueReferences = unique(mediaReferences)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripTrailPackage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        var payloads: [ExportedPayload] = []
        var skippedIDs = Set<String>()
        var skippedNames: [String] = []
        for reference in uniqueReferences {
            do {
                let exported = try await PhotoLibraryService.exportOriginal(
                    identifier: reference.localIdentifier,
                    kind: reference.kind,
                    referenceID: reference.id,
                    to: workDirectory
                )
                let values = try exported.fileURL.resourceValues(forKeys: [.fileSizeKey])
                let byteCount = Int64(values.fileSize ?? 0)
                guard byteCount > 0 else {
                    throw PortablePackageError.missingMedia(exported.originalFilename)
                }
                payloads.append(
                    ExportedPayload(
                        entry: PortablePackageMediaEntry(
                            referenceID: reference.id,
                            kindRaw: reference.kindRaw,
                            originalFilename: exported.originalFilename,
                            uniformTypeIdentifier: exported.uniformTypeIdentifier,
                            byteCount: byteCount
                        ),
                        fileURL: exported.fileURL
                    )
                )
            } catch {
                if error is CancellationError { throw error }
                guard skipUnavailableMedia else {
                    throw PortablePackageError.missingMedia(reference.caption.isEmpty ? reference.kind.rawValue : reference.caption)
                }
                skippedIDs.insert(reference.id.uuidString.lowercased())
                skippedNames.append(reference.caption.isEmpty ? reference.kind.rawValue : reference.caption)
            }
        }
        let exportedContent = try removingUnavailableMedia(from: contentData, identifiers: skippedIDs)

        let manifest = Manifest(
            format: formatName,
            formatVersion: formatVersion,
            kind: kind,
            contentData: exportedContent,
            media: payloads.map(\.entry)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        guard manifestData.count <= maximumManifestSize else { throw PortablePackageError.oversizedContent }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripTrail-\(UUID().uuidString).\(fileExtension)")
        try await write(manifestData: manifestData, payloads: payloads, to: outputURL)
        return PortablePackageExportResult(
            url: outputURL,
            mediaCount: payloads.count,
            mediaBytes: payloads.reduce(0) { $0 + $1.entry.byteCount },
            skippedMedia: skippedNames
        )
    }

    static func removingUnavailableMedia(from contentData: Data, identifiers skippedIDs: Set<String>) throws -> Data {
        guard !skippedIDs.isEmpty else { return contentData }
        func filtered(_ value: Any) -> Any {
            if let array = value as? [Any] { return array.map(filtered) }
            guard var object = value as? [String: Any] else { return value }
            if let media = object["media"] as? [[String: Any]] {
                object["media"] = media.filter { !skippedIDs.contains(($0["id"] as? String ?? "").lowercased()) }
            }
            if let cover = object["coverMedia"] as? [String: Any], skippedIDs.contains((cover["id"] as? String ?? "").lowercased()) {
                object.removeValue(forKey: "coverMedia")
            }
            return object.mapValues(filtered)
        }
        return try JSONSerialization.data(withJSONObject: filtered(JSONSerialization.jsonObject(with: contentData)))
    }

    static func open(_ url: URL) throws -> OpenedPortablePackage? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let prefix = try handle.read(upToCount: magic.count), prefix == magic else { return nil }
        guard let lengthData = try handle.read(upToCount: 8), lengthData.count == 8 else {
            throw PortablePackageError.invalidPackage
        }
        let manifestLength = decodeUInt64(lengthData)
        guard manifestLength <= UInt64(maximumManifestSize),
              let manifestData = try handle.read(upToCount: Int(manifestLength)),
              manifestData.count == Int(manifestLength)
        else {
            throw PortablePackageError.invalidPackage
        }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        } catch {
            throw PortablePackageError.invalidPackage
        }
        guard manifest.format == formatName else { throw PortablePackageError.invalidPackage }
        guard manifest.formatVersion == formatVersion else {
            throw PortablePackageError.unsupportedVersion(manifest.formatVersion)
        }
        guard manifest.media.allSatisfy({ $0.byteCount > 0 }) else {
            throw PortablePackageError.invalidPackage
        }
        return OpenedPortablePackage(
            url: url,
            kind: manifest.kind,
            contentData: manifest.contentData,
            media: manifest.media,
            payloadOffset: UInt64(magic.count + 8) + manifestLength
        )
    }

    static func restoreMedia(from package: OpenedPortablePackage) async throws -> [UUID: String] {
        guard !package.media.isEmpty else { return [:] }
        let authorization = await PhotoLibraryService.requestReadWriteAccess()
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibraryError.permissionDenied
        }

        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripTrailImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionDirectory) }

        let handle = try FileHandle(forReadingFrom: package.url)
        defer { try? handle.close() }
        try handle.seek(toOffset: package.payloadOffset)
        var identifiers: [UUID: String] = [:]
        for entry in package.media {
            let safeExtension = URL(fileURLWithPath: entry.originalFilename).pathExtension
            let targetURL = extractionDirectory
                .appendingPathComponent(entry.referenceID.uuidString)
                .appendingPathExtension(safeExtension.isEmpty ? "bin" : safeExtension)
            FileManager.default.createFile(atPath: targetURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: targetURL)
            do {
                var remaining = entry.byteCount
                while remaining > 0 {
                    let requested = Int(min(Int64(chunkSize), remaining))
                    guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else {
                        throw PortablePackageError.truncatedMedia(entry.originalFilename)
                    }
                    try output.write(contentsOf: chunk)
                    remaining -= Int64(chunk.count)
                    await Task.yield()
                }
                try output.close()
            } catch {
                try? output.close()
                throw error
            }
            let kind = MediaKind(rawValue: entry.kindRaw) ?? .image
            identifiers[entry.referenceID] = try await PhotoLibraryService.importAssetFile(at: targetURL, kind: kind)
        }
        return identifiers
    }

    static func temporaryCopy(of sourceURL: URL, extension preferredExtension: String? = nil) throws -> URL {
        let fileExtension = preferredExtension ?? sourceURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripTrailIncoming-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func unique(_ references: [MediaReference]) -> [MediaReference] {
        var seen: Set<UUID> = []
        return references.filter { seen.insert($0.id).inserted }
    }

    private static func write(manifestData: Data, payloads: [ExportedPayload], to url: URL) async throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        do {
            try output.write(contentsOf: magic)
            try output.write(contentsOf: encodeUInt64(UInt64(manifestData.count)))
            try output.write(contentsOf: manifestData)
            for payload in payloads {
                let input = try FileHandle(forReadingFrom: payload.fileURL)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                    try output.write(contentsOf: chunk)
                    await Task.yield()
                }
            }
            try output.close()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func encodeUInt64(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    private static func decodeUInt64(_ data: Data) -> UInt64 {
        data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}


/// Owns only app-generated temporary files, never user documents or Photos assets.
final class TemporaryFileOwner {
    private var urls: Set<URL> = []
    func keep(_ url: URL) { urls.insert(url) }
    // Once handed to another app, its read lifetime is independent of our preview.
    func handOff(_ url: URL) {
        guard urls.remove(url) != nil else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3 * 60 * 60) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    static func shareURL(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TripTrailShared", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(filename)
    }
    func remove(_ url: URL?) {
        guard let url, urls.remove(url) != nil else { return }
        try? FileManager.default.removeItem(at: url)
    }
    func clear() {
        for url in urls { try? FileManager.default.removeItem(at: url) }
        urls.removeAll()
    }
    deinit { clear() }

    // Run once before any new import/export starts. Only known legacy temp names qualify.
    static func cleanPreviousSession(in root: URL = FileManager.default.temporaryDirectory) {
        let manager = FileManager.default
        for url in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.lastPathComponent
            let isWork = ["TripTrailPackage-", "TripTrailImport-", "TripTrailIncoming-"].contains { name.hasPrefix($0) }
            let isPackage = ["triptrail", "triptrailbackup"].contains(url.pathExtension.lowercased())
                && (name.hasPrefix("TripTrail-") || name.hasPrefix("旅迹"))
            if name == "TripTrailShared" || isPackage {
                // Preserve recent files even across a process restart while WeChat reads.
                let files = name == "TripTrailShared"
                    ? ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                    : [url]
                for file in files {
                    if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       modified < Date().addingTimeInterval(-3 * 60 * 60) {
                        try? manager.removeItem(at: file)
                    }
                }
            } else if isWork { try? manager.removeItem(at: url) }
        }
    }
}
