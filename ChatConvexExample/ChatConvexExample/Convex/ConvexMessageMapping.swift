//
//  ConvexMessageMapping.swift
//  ChatConvexExample
//
//  Projects the Convex message DTOs onto the models `ExyteChat` renders.
//

import Foundation
import ExyteChat

extension ConvexAttachment {
    /// Returns nil for an attachment whose URLs don't parse, so a malformed row
    /// drops out instead of breaking the whole message.
    func asChatAttachment() -> Attachment? {
        guard let full = url.toURL(), let thumbnail = thumbUrl.toURL() else { return nil }
        return Attachment(
            // The R2 key, not a fresh UUID: this identity has to be stable
            // across subscription updates or SwiftUI re-creates the view and
            // the image cache misses on every message the conversation
            // receives. The cache keys do the same job for the image loader.
            id: r2Key,
            thumbnail: thumbnail,
            full: full,
            type: type,
            thumbnailCacheKey: thumbR2Key,
            fullCacheKey: r2Key
        )
    }
}

extension ConvexRecording {
    func asChatRecording() -> Recording {
        Recording(
            duration: duration,
            waveformSamples: waveformSamples.map { CGFloat($0) },
            url: url.toURL()
        )
    }
}

extension ConvexReply {
    @MainActor
    func asReplyMessage() -> ReplyMessage {
        ReplyMessage(
            id: clientId,
            user: sender.asChatUser(isCurrentUser: sender.id == SessionManager.currentUserId),
            createdAt: Date(convexTimestamp: creationTime),
            text: text,
            attachments: attachments.compactMap { $0.asChatAttachment() },
            recording: recording?.asChatRecording()
        )
    }
}

extension ConvexMessage {
    /// Anything that reaches the client from Convex has been committed, so it
    /// is always `.sent` — which is what lets an optimistic local copy be
    /// replaced by matching on `clientId`.
    @MainActor
    func asChatMessage() -> Message {
        Message(
            id: clientId,
            user: sender.asChatUser(isCurrentUser: sender.id == SessionManager.currentUserId),
            status: .sent,
            createdAt: Date(convexTimestamp: creationTime),
            text: text,
            attachments: attachments.compactMap { $0.asChatAttachment() },
            giphyMediaId: giphyMediaId,
            recording: recording?.asChatRecording(),
            replyMessage: replyTo?.asReplyMessage()
        )
    }
}
