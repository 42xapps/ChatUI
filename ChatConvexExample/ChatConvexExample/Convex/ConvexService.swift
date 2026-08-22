//
//  ConvexService.swift
//  ChatConvexExample
//

import Combine
import Foundation
import ClerkConvex
import ConvexMobile
import ExyteChat

/// What to upload, which decides the object key's extension server-side.
enum ConvexUploadKind: String {
    case image
    case video
    case videoThumbnail
    case recording
}

/// A presigned PUT destination returned by `attachments:requestUploadUrl`.
struct ConvexUploadTarget: Decodable, Sendable {
    let key: String
    let url: String
}

/// An attachment to persist on a message, described by the R2 keys the bytes
/// were uploaded to. `thumbR2Key` equals `r2Key` for images.
struct ConvexAttachmentUpload: Sendable {
    let type: AttachmentType
    let r2Key: String
    let thumbR2Key: String
}

/// A voice note to persist on a message.
struct ConvexRecordingUpload: Sendable {
    let duration: Double
    let waveformSamples: [Double]
    let r2Key: String
}

/// The app's single Convex connection, plus a typed wrapper per backend
/// function so function names and argument shapes live in one place.
///
/// `Clerk.configure(...)` must run before this is first touched:
/// `ClerkConvexAuthProvider` reads `Clerk.shared` as soon as it is bound to the
/// client. `ChatConvexExampleApp.init()` enforces the order.
@MainActor
final class ConvexService {

    static let shared = ConvexService()

    let client: ConvexClientWithAuth<String>

    /// Emits whenever the Convex connection's authentication changes. The Clerk
    /// provider drives this off the Clerk session — nothing calls `login()`.
    var authState: AnyPublisher<AuthState<String>, Never> { client.authState }

    private init() {
        client = ConvexClientWithAuth(
            deploymentUrl: AppConfig.convexDeploymentURL,
            authProvider: ClerkConvexAuthProvider()
        )
    }

    // MARK: - Subscriptions

    /// Live window over a conversation's most recent `limit` messages, ordered
    /// oldest to newest.
    func messagesPublisher(
        conversationId: String,
        limit: Int
    ) -> AnyPublisher<ConvexPage<ConvexMessage>, ClientError> {
        client.subscribe(
            to: "messages:listForConversation",
            with: [
                "conversationId": conversationId,
                // `cursor` is `v.union(v.string(), v.null())`, so an explicit
                // null is correct here — unlike the optional args below.
                "paginationOpts": [
                    "numItems": Double(limit),
                    "cursor": nil,
                ] as [String: ConvexEncodable?],
            ],
            yielding: ConvexPage<ConvexMessage>.self
        )
    }

    // MARK: - Users

    /// Creates or refreshes the caller's Convex `users` row. Call once per
    /// sign-in, before subscribing to anything that needs it.
    func syncCurrentUser(name: String?, avatarUrl: String?) async throws -> ConvexUser {
        try await client.mutation(
            "users:syncCurrentUser",
            with: omittingNils(["name": name, "avatarUrl": avatarUrl])
        )
    }

    // MARK: - Conversations

    /// Live list of the signed-in user's conversations, most recently active
    /// first — the chat-history sidebar's data source.
    var conversationsPublisher: AnyPublisher<[ConvexConversationSummary], ClientError> {
        client.subscribe(to: "conversations:listMine", yielding: [ConvexConversationSummary].self)
    }

    /// Starts a new, empty conversation. Returns its id.
    func createConversation() async throws -> String {
        try await client.mutation("conversations:create")
    }

    /// Deletes a conversation and everything in it.
    func deleteConversation(conversationId: String) async throws {
        try await client.mutation(
            "conversations:remove",
            with: ["conversationId": conversationId]
        )
    }

    // MARK: - Messages

    /// Appends a message. Re-sending the same `clientId` is a no-op server-side,
    /// so a retry after a dropped connection can't duplicate the message.
    func sendMessage(
        conversationId: String,
        clientId: String,
        text: String,
        attachments: [ConvexAttachmentUpload],
        giphyMediaId: String?,
        recording: ConvexRecordingUpload?,
        replyToClientId: String?,
        createdAt: Date
    ) async throws {
        let encodedAttachments: [ConvexEncodable?] = attachments.map { attachment in
            [
                "type": attachment.type.rawValue,
                "r2Key": attachment.r2Key,
                "thumbR2Key": attachment.thumbR2Key,
            ] as [String: ConvexEncodable?]
        }

        var encodedRecording: ConvexEncodable?
        if let recording {
            encodedRecording = [
                "duration": recording.duration,
                "waveformSamples": recording.waveformSamples.map { $0 as ConvexEncodable? }
                    as [ConvexEncodable?],
                "r2Key": recording.r2Key,
            ] as [String: ConvexEncodable?]
        }

        try await client.mutation(
            "messages:send",
            with: omittingNils([
                "conversationId": conversationId,
                "clientId": clientId,
                "text": text,
                "attachments": encodedAttachments as [ConvexEncodable?],
                "giphyMediaId": giphyMediaId,
                "recording": encodedRecording,
                "replyToClientId": replyToClientId,
                "createdAt": createdAt.convexTimestamp,
            ])
        )
    }

    // MARK: - Attachments

    /// Asks the backend for a presigned PUT URL scoped to `conversationId`.
    func requestUploadTarget(
        conversationId: String,
        kind: ConvexUploadKind
    ) async throws -> ConvexUploadTarget {
        try await client.mutation(
            "attachments:requestUploadUrl",
            with: ["conversationId": conversationId, "kind": kind.rawValue]
        )
    }

    // MARK: - Argument encoding

    /// Drops nil-valued arguments.
    ///
    /// Convex's `v.optional(T)` accepts an *absent* field, not an explicit
    /// `null` — and the Swift client encodes a present-but-nil value as JSON
    /// `null`, which would fail argument validation. So optional arguments have
    /// to be removed from the dictionary rather than passed through as nil.
    private func omittingNils(
        _ args: [String: ConvexEncodable?]
    ) -> [String: ConvexEncodable?] {
        args.filter { $0.value != nil }
    }
}

extension Date {
    /// Convex stores timestamps the way JavaScript's `Date.now()` produces
    /// them: milliseconds since the Unix epoch, as a float64.
    var convexTimestamp: Double { timeIntervalSince1970 * 1000 }

    init(convexTimestamp: Double) {
        self.init(timeIntervalSince1970: convexTimestamp / 1000)
    }
}
