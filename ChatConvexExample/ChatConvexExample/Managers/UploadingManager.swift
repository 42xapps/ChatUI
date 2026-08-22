//
//  UploadingManager.swift
//  ChatConvexExample
//

import Foundation
import ExyteChat

/// Uploads attachment bytes straight to Cloudflare R2.
///
/// Same three jobs as the Firebase Storage version, but the mechanism is: ask
/// the backend for a presigned PUT URL (which is where authorization and key
/// naming happen), then `URLSession.upload` the bytes to R2 directly, so they
/// never pass through Convex.
///
/// Returns R2 *object keys*, not URLs. Keys are what messages persist; the
/// backend derives URLs on read, which keeps them stable and lets the URL
/// scheme change without a data migration.
///
/// Giphy GIFs never come through here — they stay on Giphy's CDN and travel as
/// a media id.
enum UploadingManager {

    /// Uploads a picked image. Returns its R2 object key.
    static func uploadImageMedia(_ media: Media?, conversationId: String) async -> String? {
        guard let data = await media?.getData() else { return nil }
        return await upload(data, conversationId: conversationId, kind: .image, contentType: "image/jpeg")
    }

    /// Uploads a picked video and its poster frame. Returns (thumbnail, full).
    static func uploadVideoMedia(_ media: Media?, conversationId: String) async -> (String?, String?) {
        guard let thumbData = await media?.getThumbnailData(),
              let data = await media?.getData() else { return (nil, nil) }

        let thumbKey = await upload(
            thumbData, conversationId: conversationId, kind: .videoThumbnail, contentType: "image/jpeg"
        )
        let fullKey = await upload(
            data, conversationId: conversationId, kind: .video, contentType: "video/quicktime"
        )
        return (thumbKey, fullKey)
    }

    /// Uploads a recorded voice note. Returns its R2 object key.
    static func uploadRecording(_ recording: Recording?, conversationId: String) async -> String? {
        guard let url = recording?.url, let data = try? Data(contentsOf: url) else { return nil }
        return await upload(data, conversationId: conversationId, kind: .recording, contentType: "audio/aac")
    }

    /// Mints a presigned URL, PUTs the bytes, and returns the key on success.
    ///
    /// `Content-Type` is sent even though it isn't part of the signature: R2
    /// stores it on the object, which is what makes the file serve correctly
    /// later. Presigned S3 URLs only enforce the headers they signed, so an
    /// extra one is accepted.
    private static func upload(
        _ data: Data,
        conversationId: String,
        kind: ConvexUploadKind,
        contentType: String
    ) async -> String? {
        do {
            let target = try await ConvexService.shared.requestUploadTarget(
                conversationId: conversationId,
                kind: kind
            )
            guard let url = URL(string: target.url) else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")

            let (_, response) = try await URLSession.shared.upload(for: request, from: data)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                print("R2 upload rejected: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            return target.key
        } catch {
            print("R2 upload failed: \(error)")
            return nil
        }
    }
}
