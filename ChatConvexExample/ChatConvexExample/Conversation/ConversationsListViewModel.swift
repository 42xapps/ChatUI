//
//  ConversationsListViewModel.swift
//  ChatConvexExample
//
//  Backs the chat-history sidebar: the signed-in user's conversations, most
//  recently active first.
//

import Combine
import Foundation

@MainActor
final class ConversationsListViewModel: ObservableObject {

    private static let subscriptionRetries = 5

    @Published private(set) var conversations: [ConvexConversationSummary] = []

    private var cancellable: AnyCancellable?

    /// Subscribes once; the reactive query keeps `conversations` in sync with
    /// every create/delete/title/lastMessageAt change from here on, so
    /// callers don't need to re-fetch after `createConversation`/`delete`.
    func start() {
        guard cancellable == nil else { return }
        cancellable = ConvexService.shared.conversationsPublisher
            .retry(Self.subscriptionRetries)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    print("conversations:listMine subscription gave up: \(error)")
                }
            } receiveValue: { [weak self] conversations in
                self?.conversations = conversations
            }
    }

    /// Starts a new, empty conversation and returns its id.
    func createConversation() async -> String? {
        do {
            return try await ConvexService.shared.createConversation()
        } catch {
            print("Failed to create conversation: \(error)")
            return nil
        }
    }

    func delete(_ conversationId: String) async {
        do {
            try await ConvexService.shared.deleteConversation(conversationId: conversationId)
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }
}
