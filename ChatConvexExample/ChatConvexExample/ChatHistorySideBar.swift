//
//  ChatHistorySideBar.swift
//  ChatConvexExample
//
//  The side menu's content: "New Chat", the conversation list (swipe to
//  delete), and the signed-in user's profile row pinned to the bottom-left.
//

import SwiftUI

struct ChatHistorySideBar: View {
    @ObservedObject var viewModel: ConversationsListViewModel
    @Binding var selectedConversationId: String?
    @Binding var isMenuExpanded: Bool
    let onNewChat: () -> Void
    let onShowProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            newChatButton
                .padding(.horizontal, 15)
                .padding(.top, 15)
                .padding(.bottom, 10)

            if viewModel.conversations.isEmpty {
                Spacer()
                Text("No chats yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                conversationList
            }

            Divider()
            profileRow
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var conversationList: some View {
        List {
            ForEach(viewModel.conversations) { conversation in
                Button {
                    selectedConversationId = conversation.id
                    isMenuExpanded = false
                } label: {
                    Text(conversation.title ?? "New chat")
                        .lineLimit(1)
                        .foregroundStyle(
                            conversation.id == selectedConversationId ? Color.exampleBlue : Color.primary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await delete(conversation.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var newChatButton: some View {
        Button(action: onNewChat) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .frame(width: 30)
                Text("New Chat")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            .foregroundStyle(Color.primary)
        }
    }

    private var profileRow: some View {
        Button(action: onShowProfile) {
            HStack(spacing: 10) {
                AvatarCircle(
                    url: SessionManager.currentUser?.avatarURL,
                    name: SessionManager.currentUser?.name ?? "?",
                    size: 36
                )
                Text(SessionManager.currentUser?.name ?? "Profile")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
        }
    }

    private func delete(_ conversationId: String) async {
        if conversationId == selectedConversationId {
            selectedConversationId = nil
        }
        await viewModel.delete(conversationId)
    }
}
