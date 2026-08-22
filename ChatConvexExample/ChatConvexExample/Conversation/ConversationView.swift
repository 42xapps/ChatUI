//
//  ConversationView.swift
//  ChatConvexExample
//

import SwiftUI
import ExyteChat

/// A single chat thread. `ChatHomeView` hosts one of these per selected
/// conversation, inside the side-menu content area.
struct ConversationView: View {

    @StateObject var viewModel: ConversationViewModel

    /// Opens the chat-history side menu. Log out lives in the profile sheet
    /// now, not here — this toolbar button is the menu instead.
    var onOpenMenu: () -> Void = {}

    var body: some View {
        NavigationStack {
            // ChatView-specific modifiers return ChatView, so they all have to
            // come before any modifier that erases it to `some View`.
            ChatView(messages: viewModel.messages, chatType: .conversation) { draft in
                viewModel.sendMessage(draft)
            }
            .enableLoadMoreOlderMessages(
                triggerType: .pixels(0),
                hasMoreToLoad: viewModel.hasMoreOlderMessages
            ) {
                await viewModel.loadOlderMessages()
            } loadingIndicatorBuilder: {
                ProgressView()
                    .padding(.vertical, 10)
            }
            // ChatView draws its own offline banner; it's just off by default.
            .showNetworkConnectionProblem(true)
            .setAvailableInputs([.text, .audio, .media, .giphy])
            .setRecorderSettings(ChatAppearance.recorderSettings)
            .setMessageFont(ChatAppearance.messageFont)
            .setMediaPickerLiveCameraStyle(.prominant)
            .keyboardDismissMode(.interactive)
            .swipeActions(
                edge: .leading,
                performsFirstActionWithFullSwipe: true,
                items: [replyAction]
            )
            .orientationHandler { mode in
                switch mode {
                case .lock: AppDelegate.lockOrientationToPortrait()
                case .unlock: AppDelegate.unlockOrientation()
                }
            }
            .mediaPickerTheme(
                main: .init(
                    pickerText: .white,
                    pickerBackground: .examplePickerBg,
                    fullscreenPhotoBackground: .examplePickerBg
                ),
                selection: .init(
                    accent: .exampleBlue
                )
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: onOpenMenu) {
                        Image(systemName: "line.3.horizontal")
                    }
                    .font(17, .black)
                }
            }
        }
        .chatTheme(colors: ChatAppearance.colors)
        .giphyConfig(GiphyConfiguration(giphyKey: AppConfig.giphyApiKey))
        .task {
            await viewModel.start()
        }
    }

    /// Swipe a message to quote it in the composer. `defaultActions` is what
    /// wires the reply through to the input view.
    private var replyAction: SwipeAction {
        SwipeAction(
            action: { message, defaultActions in defaultActions(message, .reply) },
            activeFor: { !$0.user.isCurrentUser },
            background: .blue
        ) {
            VStack {
                Image(systemName: "arrowshape.turn.up.left")
                    .imageScale(.large)
                    .foregroundStyle(.white)
                    .frame(height: 30)
                Text("Reply")
                    .foregroundStyle(.white)
                    .font(.footnote)
            }
        }
    }
}

#Preview {
    ConversationView(viewModel: .preview)
}
