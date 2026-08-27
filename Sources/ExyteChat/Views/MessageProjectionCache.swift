//
//  MessageProjectionCache.swift
//  Chat
//

import Combine
import SwiftUI

/// The list projection is structural data. Keeping it in state prevents typing in the composer
/// from repeatedly regrouping every message while preserving the public `ChatView` API.
@MainActor
final class MessageProjectionCache: ObservableObject {

    @Published private(set) var sections: [MessagesSection]
    @Published private(set) var ids: [String]

    private var input: MessageProjectionInput
    private(set) var rebuildCount = 1

    init(messages: [Message], chatType: ChatType, replyMode: ReplyMode) {
        let input = MessageProjectionInput(
            messages: messages,
            chatType: chatType,
            replyMode: replyMode
        )
        self.input = input
        self.sections = ProjectionChatView.mapMessages(
            messages,
            chatType: chatType,
            replyMode: replyMode
        )
        self.ids = messages.map(\.id)
    }

    func update(with input: MessageProjectionInput) {
        guard self.input != input else { return }

        self.input = input
        sections = ProjectionChatView.mapMessages(
            input.messages,
            chatType: input.chatType,
            replyMode: input.replyMode
        )
        ids = input.messages.map(\.id)
        rebuildCount += 1
    }
}

struct MessageProjectionInput: Equatable {
    let messages: [Message]
    let chatType: ChatType
    let replyMode: ReplyMode
}

private typealias ProjectionChatView = ChatView<EmptyView, EmptyView, DefaultMessageMenuAction>
