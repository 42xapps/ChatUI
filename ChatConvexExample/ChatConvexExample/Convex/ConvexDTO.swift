//
//  ConvexDTO.swift
//  ChatConvexExample
//
//  Plain `Decodable` mirrors of the shapes the Convex functions return. Each
//  type names the validator it mirrors so the two stay in step; changing a
//  `returns` validator in `convex-backend/` means changing its twin here.
//
//  Numeric fields use `@ConvexFloat`, which accepts both a plain JSON number
//  and Convex's `{"$float": …}` encoding for NaN/±Infinity. `@ConvexInt` is
//  deliberately unused: it *requires* the `{"$integer": …}` form, which only
//  `v.int64()` fields produce, and every numeric field in the schema is
//  `v.number()` (float64).
//

import Foundation
import ConvexMobile
import ExyteChat

/// Mirrors `publicUser` in `convex/model/users.ts`.
struct ConvexUser: Decodable, Identifiable, Sendable {
    let id: String
    let clerkId: String
    let name: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case clerkId, name, avatarUrl
    }
}

/// Mirrors `resolvedAttachment` in `convex/model/messages.ts`.
struct ConvexAttachment: Decodable, Sendable {
    let type: AttachmentType
    let url: String
    let thumbUrl: String
    let r2Key: String
    let thumbR2Key: String
}

/// Mirrors `resolvedRecording` in `convex/model/messages.ts`.
struct ConvexRecording: Decodable, Sendable {
    @ConvexFloat var duration: Double
    /// Finite by construction, so no per-element `@ConvexFloat` is possible or
    /// needed — property wrappers can't apply to array elements.
    let waveformSamples: [Double]
    let url: String
}

/// Mirrors `resolvedReply` in `convex/model/messages.ts`.
struct ConvexReply: Decodable, Sendable {
    let clientId: String
    let sender: ConvexUser
    /// Convex's own commit time — see `ConvexMessage.creationTime`.
    @ConvexFloat var creationTime: Double
    let text: String
    let attachments: [ConvexAttachment]
    let recording: ConvexRecording?

    enum CodingKeys: String, CodingKey {
        case clientId, sender, text, attachments, recording
        case creationTime = "_creationTime"
    }
}

/// Mirrors `resolvedMessage` in `convex/model/messages.ts`.
///
/// `clientId` — not `_id` — is the identity used throughout the app: the sender
/// mints it before the message exists on the server, which is what lets an
/// optimistically inserted message be reconciled with its server copy.
struct ConvexMessage: Decodable, Identifiable, Sendable {
    let clientId: String
    let sender: ConvexUser
    /// Convex's own monotonic commit time — the source of truth for display
    /// and ordering. The sender's compose-time clock (`createdAt` in the
    /// schema) is intentionally not exposed here: a skewed device clock, or a
    /// message composed offline and sent after reconnecting, would otherwise
    /// misplace it relative to messages that actually arrived first.
    @ConvexFloat var creationTime: Double
    let text: String
    let attachments: [ConvexAttachment]
    let giphyMediaId: String?
    let recording: ConvexRecording?
    let replyTo: ConvexReply?

    enum CodingKeys: String, CodingKey {
        case clientId, sender, text, attachments, giphyMediaId, recording, replyTo
        case creationTime = "_creationTime"
    }

    var id: String { clientId }
}

/// Mirrors Convex's `PaginationResult`. `splitCursor` and `pageStatus` are
/// omitted: they drive reactive re-pagination on the JS clients only.
struct ConvexPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let page: [Item]
    let isDone: Bool
    let continueCursor: String
}

/// Mirrors `conversationSummary` in `convex/conversations.ts` — a row in the
/// chat-history sidebar.
struct ConvexConversationSummary: Decodable, Identifiable, Sendable {
    let id: String
    /// nil until the conversation's first message lands and derives one.
    let title: String?
    @ConvexFloat var lastMessageAt: Double

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, lastMessageAt
    }
}
