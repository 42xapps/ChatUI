import SwiftUI
import Testing

@testable import ExyteChat

struct StreamingOperationsTest {
    typealias ConcreteChatView = ChatView<EmptyView, EmptyView, DefaultMessageMenuAction>
    typealias ConcreteList = UIList<EmptyView>

    let assistant = User(
        id: "assistant",
        name: "Embie",
        avatarURL: nil,
        isCurrentUser: false
    )

    @Test("Growing streamed text uses the self-sizing streaming edit")
    func growingTextUsesStreamingEdit() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let oldMessage = Message(
            id: "assistant-message",
            user: assistant,
            createdAt: createdAt,
            text: "Hello",
            responseStatus: .generating
        )
        let newMessage = Message(
            id: oldMessage.id,
            user: assistant,
            createdAt: createdAt,
            text: "Hello, this reply is growing across several lines.",
            responseStatus: .generating
        )

        let split = ConcreteList.SplitInfo.operationsSplit(
            oldSections: ConcreteChatView.mapMessages(
                [oldMessage], chatType: .conversation, replyMode: .quote
            ),
            newSections: ConcreteChatView.mapMessages(
                [newMessage], chatType: .conversation, replyMode: .quote
            )
        )

        #expect(split.editOperations.map(\.description) == [
            "editStreaming section 0 row 0"
        ])
    }

    @Test("Response lifecycle changes use the same self-sizing streaming edit")
    func responseStateUsesStreamingEdit() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let oldMessage = Message(
            id: "assistant-message",
            user: assistant,
            createdAt: createdAt,
            responseStatus: .queued(until: nil)
        )
        let newMessage = Message(
            id: oldMessage.id,
            user: assistant,
            createdAt: createdAt,
            responseStatus: .generating
        )

        let split = ConcreteList.SplitInfo.operationsSplit(
            oldSections: ConcreteChatView.mapMessages(
                [oldMessage], chatType: .conversation, replyMode: .quote
            ),
            newSections: ConcreteChatView.mapMessages(
                [newMessage], chatType: .conversation, replyMode: .quote
            )
        )

        #expect(split.editOperations.map(\.description) == [
            "editStreaming section 0 row 0"
        ])
    }
}
