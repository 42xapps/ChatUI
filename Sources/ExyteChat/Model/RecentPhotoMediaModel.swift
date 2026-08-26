//
//  RecentPhotoMediaModel.swift
//  Chat
//

import ExyteMediaPicker
import FanPicker
import Foundation
import UniformTypeIdentifiers
import UIKit

/// Bridges a photo quick-attached from the composer's fan into `Media`, so it travels the same
/// path as anything picked through the full screen media picker.
struct RecentPhotoMediaModel: MediaModelProtocol {

    let id: UUID
    let asset: RecentPhotoAsset

    private let files = RecentPhotoFileCache()

    var mediaType: MediaType? { .image }

    var duration: CGFloat? {
        get async { nil }
    }

    /// Writes the full resolution photo to a temporary file on first use. Picking stays instant —
    /// and the hero animation stays smooth — because nothing touches the resource until something
    /// actually asks for it, which in practice is the send.
    ///
    /// Note this deliberately goes through `loadImageData()` rather than FanPicker's
    /// `exportResource(to:)`. As of 0.2.0 the latter hands main-actor-isolated closures to
    /// `PHAssetResourceManager`, which calls them on its own file IO queue, and Swift's isolation
    /// check traps the process.
    func getURL() async -> URL? {
        await files.url(.full) {
            try? await writeFullImage()
        }
    }

    func getThumbnailURL() async -> URL? {
        await files.url(.thumbnail) {
            guard let data = await getThumbnailData() else { return nil }
            return try? write(data, named: "thumbnail.jpg")
        }
    }

    /// Reads back the file written by ``getURL()`` so a photo is only ever fetched out of Photos
    /// once, however many times the composer and the host app ask for it.
    func getData() async throws -> Data? {
        guard let url = await getURL() else {
            throw RecentPhotoResourceError.unavailable
        }
        return try Data(contentsOf: url)
    }

    func getThumbnailData() async -> Data? {
        await MainActor.run {
            asset.image.jpegData(compressionQuality: 0.9)
        }
    }

    private func writeFullImage() async throws -> URL {
        let image = try await asset.loadImageData()
        return try write(image.data, named: "photo.\(image.fileExtension)")
    }

    private func write(_ data: Data, named name: String) throws -> URL {
        let url = try directoryURL().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func directoryURL() throws -> URL {
        let directory = Self.directory(for: id)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func directory(for id: UUID) -> URL {
        baseTempDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static var baseTempDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ExyteChatQuickAttach", isDirectory: true)
    }

    static func cleanup(id: UUID) {
        let dir = directory(for: id)
        try? FileManager.default.removeItem(at: dir)
    }

    static func cleanTempDirectory() {
        try? FileManager.default.removeItem(at: baseTempDirectory)
    }
}

extension Media {

    /// Wraps a quick-attach selection, reusing the selection's id so FanPicker can match the fan
    /// thumbnail to the composer attachment it flies into.
    init(recentPhoto selection: RecentPhotoSelection) {
        self.init(source: RecentPhotoMediaModel(id: selection.id, asset: selection.asset))
        id = selection.id
    }
}

private extension RecentPhotoImageData {

    /// Uploaders downstream tend to rely on a meaningful extension.
    var fileExtension: String {
        typeIdentifier
            .flatMap(UTType.init(_:))?
            .preferredFilenameExtension ?? "jpg"
    }
}

/// Keeps each written file around for the lifetime of the selection and collapses concurrent
/// requests for the same file into a single fetch.
private actor RecentPhotoFileCache {

    enum Kind: Hashable {
        case full
        case thumbnail
    }

    private var tasks: [Kind: Task<URL?, Never>] = [:]

    func url(_ kind: Kind, make: @Sendable @escaping () async -> URL?) async -> URL? {
        if let existing = tasks[kind] {
            return await existing.value
        }
        let task = Task(operation: make)
        tasks[kind] = task
        return await task.value
    }
}
