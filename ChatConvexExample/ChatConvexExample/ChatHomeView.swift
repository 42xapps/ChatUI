//
//  ChatHomeView.swift
//  ChatConvexExample
//
//  Root content shown once the user is signed in: a swipeable chat-history
//  side menu (via `CustomSideMenu`) wrapping the currently selected
//  conversation. Replaces the old single-thread `ConversationView` root —
//  there's no tab bar anywhere in this app.
//

import SwiftUI

struct ChatHomeView: View {

    @StateObject private var conversationsViewModel = ConversationsListViewModel()

    @State private var isMenuExpanded = false
    @State private var selectedConversationId: String?
    @State private var showProfile = false
    /// Guards the one-time "open whatever's most recent" pick on first load,
    /// so it doesn't fight the user's own subsequent selections.
    @State private var hasMadeInitialSelection = false

    var body: some View {
        CustomSideMenu(isExpanded: $isMenuExpanded) { _ in
            ChatHistorySideBar(
                viewModel: conversationsViewModel,
                selectedConversationId: $selectedConversationId,
                isMenuExpanded: $isMenuExpanded,
                onNewChat: startNewChat,
                onShowProfile: { showProfile = true }
            )
        } content: { _ in
            if let selectedConversationId {
                ConversationView(
                    viewModel: ConversationViewModel(conversationId: selectedConversationId),
                    onOpenMenu: { isMenuExpanded = true }
                )
                .id(selectedConversationId)
            } else {
                EmptyChatView(onNewChat: startNewChat, onOpenMenu: { isMenuExpanded = true })
            }
        }
        .task {
            conversationsViewModel.start()
        }
        .onChange(of: conversationsViewModel.conversations.count) { _, _ in
            guard !hasMadeInitialSelection else { return }
            hasMadeInitialSelection = true
            selectedConversationId = conversationsViewModel.conversations.first?.id
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
        }
    }

    private func startNewChat() {
        Task {
            guard let id = await conversationsViewModel.createConversation() else { return }
            selectedConversationId = id
            isMenuExpanded = false
        }
    }
}

/// Shown when the user has no conversations yet (or just deleted the one they
/// were in) — an inviting call to action rather than a blank chat screen.
private struct EmptyChatView: View {
    let onNewChat: () -> Void
    let onOpenMenu: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No chats yet")
                    .font(20, .black, .semibold)
                Button("Start a new chat", action: onNewChat)
                    .font(17, .white, .medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.exampleBlue, in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: onOpenMenu) {
                        Image(systemName: "line.3.horizontal")
                    }
                    .font(17, .black)
                }
            }
        }
    }
}
