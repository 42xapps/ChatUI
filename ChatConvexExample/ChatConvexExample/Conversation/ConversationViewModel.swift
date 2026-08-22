//
//  ConversationViewModel.swift
//  ChatConvexExample
//

import Combine
import Foundation
import ExyteChat

@MainActor
class ConversationViewModel: ObservableObject {

    /// Initial size of the live window, and how much each older-messages load
    /// grows it by.
    ///
    /// The window only ever grows, never shrinks or pages via a separate
    /// cursor: "load older messages" means re-subscribing to
    /// `messages:listForConversation` asking for more of the conversation's
    /// newest N. That keeps a single reactive source of truth. A fixed-size
    /// window plus a separately-captured "older" cursor would go stale the
    /// moment new messages arrived and shifted what "the newest 100" means —
    /// re-subscribing with a larger N instead means every emission is always
    /// a superset of whatever was already loaded, so nothing already on
    /// screen can ever be dropped or duplicated.
    private static let pageSize = 100

    /// How many times to re-establish the message subscription after an error.
    private static let subscriptionRetries = 5

    @Published var messages: [Message] = []

    /// Which conversation this view model streams. Fixed for its lifetime —
    /// switching conversations means creating a new `ConversationViewModel`
    /// (see `ChatHomeView`, which keys one by `conversationId` via `.id(_:)`
    /// so SwiftUI recreates it instead of reusing one across conversations).
    let conversationId: String

    /// Whether the live window already reaches the start of the conversation.
    /// Read by `ConversationView` to gate `enableLoadMoreOlderMessages`.
    private(set) var hasMoreOlderMessages = true

    var lock = NSRecursiveLock()

    private var messagesCancellable: AnyCancellable?

    /// How many of the conversation's newest messages the live subscription
    /// currently asks for.
    private var windowSize = ConversationViewModel.pageSize

    /// Set by `init(conversationId:previewMessages:)` so SwiftUI previews
    /// never open a connection.
    private let isPreview: Bool

    private var hasStarted = false

    init(conversationId: String) {
        self.conversationId = conversationId
        isPreview = false
    }

    /// Preloaded, offline view model for `#Preview`.
    private init(conversationId: String, previewMessages: [Message]) {
        self.conversationId = conversationId
        isPreview = true
        messages = previewMessages
    }

    /// Starts streaming the conversation.
    ///
    /// Idempotent: called from the view's `.task`, which re-runs if the view
    /// reappears.
    func start() async {
        guard !isPreview, !hasStarted else { return }
        hasStarted = true
        await subscribeToMessages()
    }

    /// Grows the live window by one page and waits for the resulting
    /// subscription to deliver its first page, so `ChatView`'s loading
    /// indicator stays up for the duration of the fetch.
    func loadOlderMessages() async {
        guard !isPreview, hasMoreOlderMessages else { return }
        windowSize += Self.pageSize
        await subscribeToMessages()
    }

    // MARK: - get/send messages

    /// (Re)subscribes at the current `windowSize` and suspends until the
    /// first value — or a terminal failure — arrives, while leaving the
    /// subscription running afterward for ongoing reactivity. Replacing
    /// `messagesCancellable` cancels whatever subscription was running
    /// before it, so growing the window never leaves two subscriptions alive.
    private func subscribeToMessages() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            func resumeOnce() {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }

            messagesCancellable = ConvexService.shared
                .messagesPublisher(conversationId: conversationId, limit: windowSize)
                // A Combine failure completion is terminal, so without this a
                // single transient error ends the subscription for the lifetime of
                // the screen and the chat silently stops updating. That happens in
                // practice: a query can execute once before the connection's auth
                // token is attached and come back "Not signed in".
                .retry(Self.subscriptionRetries)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    if case .failure(let error) = completion {
                        print("messages:listForConversation subscription gave up: \(error)")
                        // Unknown either way, but assuming there's more is the
                        // safer failure mode: it keeps "load older" retryable
                        // instead of silently disabling it.
                        self?.hasMoreOlderMessages = true
                    }
                    resumeOnce()
                } receiveValue: { [weak self] page in
                    self?.hasMoreOlderMessages = !page.isDone
                    self?.merge(page.page)
                    resumeOnce()
                }
        }
    }

    /// Replaces the server-backed messages while preserving anything still in
    /// flight. A local message disappears from the tail the moment the server
    /// copy arrives with the same id, so it never renders twice.
    private func merge(_ convexMessages: [ConvexMessage]) {
        let messages = convexMessages.map { $0.asChatMessage() }

        lock.withLock {
            // insert messages which are still sending
            let localMessages = self.messages
                .filter { $0.status != .sent }
                .filter { localMessage in
                    messages.firstIndex { message in
                        message.id == localMessage.id
                    } == nil
                }
                .sorted { $0.createdAt < $1.createdAt }
            self.messages = messages + localMessages
        }
    }

    func sendMessage(_ draft: DraftMessage) {
        Task {
            /// precreate message with fixed id and .sending status
            guard let user = SessionManager.currentUser else { return }
            let id = UUID().uuidString
            let message = await Message.makeMessage(id: id, user: user, status: .sending, draft: draft)
            lock.withLock {
                messages.append(message)
            }

            /// upload any media and collect the resulting R2 keys
            let attachments = await uploadAttachments(draft, conversationId: conversationId)
            let recording = await uploadRecording(draft, conversationId: conversationId)

            /// send with the same id we fixed earlier, so Chat knows it's still
            /// the same message
            do {
                try await ConvexService.shared.sendMessage(
                    conversationId: conversationId,
                    clientId: id,
                    text: draft.text,
                    attachments: attachments,
                    giphyMediaId: draft.giphyMedia?.id,
                    recording: recording,
                    replyToClientId: draft.replyMessage?.id,
                    createdAt: draft.createdAt
                )
                // No need to set .sent: every message coming from Convex has
                // .sent status, so as soon as this one is committed the
                // subscription replaces the local copy.
            } catch {
                print("Error sending message: \(error)")
                lock.withLock {
                    if let index = messages.lastIndex(where: { $0.id == id }) {
                        messages[index].status = .error(draft)
                    }
                }
            }
        }
    }

    private func uploadAttachments(
        _ draft: DraftMessage,
        conversationId: String
    ) async -> [ConvexAttachmentUpload] {
        var attachments = [ConvexAttachmentUpload]()
        for media in draft.medias {
            switch media.type {
            case .image:
                if let key = await UploadingManager.uploadImageMedia(media, conversationId: conversationId) {
                    // An image is its own thumbnail.
                    attachments.append(
                        ConvexAttachmentUpload(type: .image, r2Key: key, thumbR2Key: key)
                    )
                }
            case .video:
                let (thumbKey, fullKey) = await UploadingManager.uploadVideoMedia(
                    media, conversationId: conversationId
                )
                if let thumbKey, let fullKey {
                    attachments.append(
                        ConvexAttachmentUpload(type: .video, r2Key: fullKey, thumbR2Key: thumbKey)
                    )
                }
            }
        }
        return attachments
    }

    private func uploadRecording(
        _ draft: DraftMessage,
        conversationId: String
    ) async -> ConvexRecordingUpload? {
        guard let recording = draft.recording,
              let key = await UploadingManager.uploadRecording(recording, conversationId: conversationId)
        else { return nil }

        return ConvexRecordingUpload(
            duration: recording.duration,
            waveformSamples: recording.waveformSamples.map { Double($0) },
            r2Key: key
        )
    }
}

extension ConversationViewModel {

    /// Offline view model for `#Preview`, with both sides of a conversation so
    /// the outgoing and incoming bubble styles are both visible.
    static var preview: ConversationViewModel {
        let me = User(id: "me", name: "You", avatarURL: nil, isCurrentUser: true)
        let assistant = User(id: "assistant", name: "Assistant", avatarURL: nil, isCurrentUser: false)
        let start = Date().addingTimeInterval(-600)

        return ConversationViewModel(conversationId: "preview", previewMessages: [
            Message(id: "1", user: me, status: .sent, createdAt: start,
                    text: "Hello"),
            Message(id: "2", user: assistant, status: .sent, createdAt: start.addingTimeInterval(20),
                    text: "Hi — how can I help?"),
            Message(id: "3", user: me, status: .sent, createdAt: start.addingTimeInterval(90),
                    text: "How are you doing?"),
            Message(id: "4", user: me, status: .sending, createdAt: Date(),
                    text: "Still sending…"),
        ])
    }
}
