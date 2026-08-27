//
//  ChatView.swift
//  Chat
//
//  Created by Alisa Mylnikova on 20.04.2022.
//

import ExyteMediaPicker
import GiphyUISDK
import SwiftUI

public typealias MediaPickerLiveCameraStyle = LiveCameraCellStyle
public typealias MediaPickerSelectionParameters = SelectionParameters

public enum ChatType: CaseIterable, Sendable, Equatable {
    case conversation  // the latest message is at the bottom, new messages appear from the bottom
    case comments  // the latest message is at the top, new messages appear from the top
}

public enum ReplyMode: CaseIterable, Sendable, Equatable {
    case quote  // when replying to message A, new message will appear as the newest message, quoting message A in its body
    case answer  // when replying to message A, new message with appear direclty below message A as a separate cell without duplicating message A in its body
}

public struct ChatView<MessageContent: View, InputViewContent: View, MenuAction: MessageMenuAction>:
    View
{

    /// User and MessageId
    public typealias TapAvatarClosure = (User, String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.chatTheme) private var theme
    @Environment(\.giphyConfig) private var giphyConfig

    // MARK: - Parameters

    /// provide custom message view builder
    /// To customize only some messages while keeping the default style for others,
    /// use `messageBuilder` and return your custom view for the messages you want to style, and `params.defaultMessageView()` for the rest.
    /// This way you can mix your custom message view with ExyteChat's built-in styling in the same chat.
    /// ```swift
    /// ChatView(messages: viewModel.messages) { draft in
    ///     viewModel.send(draft: draft)
    /// } messageBuilder: { params in
    ///     if needsCustomUI(params.message) {
    ///         MyCustomMessageView(message: params.message)
    ///     } else {
    ///         params.defaultMessageView()
    ///     }
    /// }
    /// ```
    @ViewBuilder var messageBuilder: MessageBuilderParamsClosure

    /// provide custom input view builder
    @ViewBuilder var inputViewBuilder: InputViewBuilderParamsClosure

    /// message menu customization: create enum complying to MessageMenuAction and pass a closure processing your enum cases
    var messageMenuAction: MessageMenuActionClosure

    var messages: [Message]
    var type: ChatType
    var replyMode: ReplyMode
    var didSendMessage: (DraftMessage) -> Void
    var didUpdateAttachmentStatus: ((AttachmentUploadUpdate) -> Void)?

    // MARK: - Simple view builders

    /// a header for the whole chat, which will scroll together with all the messages and headers
    var mainHeaderBuilder: (() -> AnyView)?

    /// date section header builder
    var dateHeaderBuilder: ((Date) -> AnyView)?

    /// content to display in between the chat list view and the input view
    var betweenListAndInputViewBuilder: (() -> AnyView)?

    // MARK: - Customization

    var chatCustomizationParameters = ChatCustomizationParameters()
    var messageCustomizationParameters = MessageCustomizationParameters()
    var inputViewCustomizationParameters = InputViewCustomizationParameters()

    // MARK: - State

    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var inputViewModel = InputViewModel()
    @StateObject private var globalFocusState = GlobalFocusState()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var keyboardState = KeyboardState()
    @StateObject var messageProjection: MessageProjectionCache

    @State private var pendingScrollTo: ScrollToParams?
    @State private var isScrolledToBottom: Bool = true
    @State private var tableContentHeight: CGFloat = 0

    @State private var cellFrames = [String: CGRect]()
    /// Used to prevent the MainView from responding to keyboard changes while the Menu is active
    @State private var isShowingMenu = false

    @State private var giphyConfigured = false
    @State private var selectedGiphyMedia: GPHMedia? = nil

    public var body: some View {
        GeometryReader { proxy in
            mainView(keyboardOverlap: KeyboardLayout.overlap(
                container: proxy.frame(in: .global),
                keyboard: keyboardState.keyboardFrame
            ))
        }
            .background(chatBackground())
            // Blur parent when fullscreen media sheet is shown
            .blur(radius: viewModel.fullscreenAttachmentPresented ? 12 : 0)
            .animation(.easeInOut(duration: 0.35), value: viewModel.fullscreenAttachmentPresented)
            .environmentObject(keyboardState)
            .onChange(of: projectionInput) { _, input in
                messageProjection.update(with: input)
            }
            .onAppear {
                if isGiphyAvailable() {
                    if let giphyKey = giphyConfig.giphyKey {
                        if !giphyConfigured {
                            giphyConfigured = true
                            Giphy.configure(apiKey: giphyKey)
                        }
                    } else {
                        print(
                            "WARNING: giphy key not provided, please pass a key using giphyConfig")
                    }
                }
            }
            .onChange(of: inputViewModel.text) { _, newValue in
                inputViewCustomizationParameters.onInputTextChange?(newValue)
            }
            .onChange(of: inputViewCustomizationParameters.externalInputText) {
                DispatchQueue.main.async {
                    inputViewModel.text = inputViewCustomizationParameters.externalInputText ?? ""
                }
            }
            .onChange(of: selectedGiphyMedia) {
                if let giphyMedia = selectedGiphyMedia {
                    inputViewModel.attachments.giphyMedia = giphyMedia
                    inputViewModel.send()
                }
            }
            .onChange(of: inputViewModel.showPicker) { _, newValue in
                if newValue {
                    globalFocusState.focus = nil
                }
            }
            .onChange(of: inputViewModel.showGiphyPicker) { _, newValue in
                if newValue {
                    globalFocusState.focus = nil
                }
            }
            .onChange(of: inputViewModel.showDocumentPicker) { _, newValue in
                if newValue {
                    globalFocusState.focus = nil
                }
            }
            .onChange(of: chatCustomizationParameters.scrollToParams) { scrollToParams in
                self.pendingScrollTo = scrollToParams
            }
            .onChange(of: newestMessage) { _, _ in
                // Keeps a streaming reply (repeated in-place edits to the newest message,
                // e.g. tokens arriving from an LLM) pinned to the bottom, without fighting
                // the user if they've deliberately scrolled away to read history.
                guard isScrolledToBottom else { return }
                pendingScrollTo = ScrollToParams(.newestMessage)
            }
            .sheet(isPresented: $inputViewModel.showGiphyPicker) {
                if giphyConfig.giphyKey != nil {
                    GiphyEditorView(
                        giphyConfig: giphyConfig,
                        selectedMedia: $selectedGiphyMedia
                    )
                    .environmentObject(globalFocusState)
                } else {
                    Text("no giphy key found")
                }
            }
            .fullScreenCover(isPresented: $inputViewModel.showPicker) {
                AttachmentsEditor(
                    inputViewModel: inputViewModel,
                    mediaPickerParameters: inputViewCustomizationParameters.mediaPickerParameters,
                    localization: chatCustomizationParameters.localization
                )
                .environmentObject(globalFocusState)
                .environmentObject(keyboardState)
            }
            .sheet(isPresented: $inputViewModel.showDocumentPicker) {
                DocumentPickerView()
            }
            .sheet(isPresented: $viewModel.fullscreenAttachmentPresented) {
                let attachments = messageProjection.sections.flatMap { section in
                    section.rows.flatMap { $0.message.attachments }
                }
                let index = attachments.firstIndex {
                    $0.id == viewModel.fullscreenAttachmentItem?.id
                }

                FullscreenMediaPages(
                    viewModel: FullscreenMediaPagesViewModel(
                        attachments: attachments,
                        index: index ?? 0
                    )
                )
                // 1. Size control & selection tracking
                .presentationDetents([.fraction(0.7), .large])
                // 2. Control drag handle visibility
                .presentationDragIndicator(.visible)
                // 3. Round the top corners
                .presentationCornerRadius(30)
                .presentationBackground(Color.clear)
            }
    }

    func mainView(keyboardOverlap: CGFloat) -> some View {
        VStack(spacing: 0) {
            if chatCustomizationParameters.showNetworkConnectionProblem, !networkMonitor.isConnected
            {
                waitingForNetwork
            }

            if shouldFloatInputView {
                listWithButton
                    // The transcript can extend through the static top container area, but it
                    // must remain in the keyboard-respecting layout region. A bottom
                    // `safeAreaInset` participates in the system keyboard animation and gives
                    // the UIKit-backed list a matching safe area, so the composer and newest
                    // message stay together during focus changes and multiline expansion.
                    .ignoresSafeArea(.container, edges: .top)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        inputView
                            // The host can opt out of SwiftUI's keyboard-safe-area resizing
                            // (for example, a full-screen transformed drawer). The explicit
                            // overlap keeps the composer attached to the system keyboard in
                            // that case. This padding is part of the inset, so UIList receives
                            // the identical reservation and its newest cell cannot sit beneath
                            // the composer.
                            .padding(.bottom, keyboardOverlap)
                    }
            } else if chatCustomizationParameters.isListAboveInputView {
                listWithButton
                if let builder = betweenListAndInputViewBuilder {
                    builder()
                }
                inputView
            } else {
                inputView
                if let builder = betweenListAndInputViewBuilder {
                    builder()
                }
                listWithButton
            }
        }
        // Used to prevent ChatView movement during Emoji Keyboard invocation
        // Own floating-composer keyboard avoidance explicitly. This prevents an ancestor that
        // ignores the keyboard safe area from making the transcript and composer disagree about
        // their available height. Other ChatView configurations retain the system default.
        .ignoresSafeArea(shouldFloatInputView || isShowingMenu ? .keyboard : [])
    }

    /// The floating glass composer (see `InputView`) is designed to sit on top of the message
    /// list with content passing behind it. That only makes sense for the default conversation
    /// layout; other configurations (comments, reversed order, or a custom in-between builder)
    /// keep the original stacked layout.
    private var shouldFloatInputView: Bool {
        type == .conversation
            && chatCustomizationParameters.isListAboveInputView
            && betweenListAndInputViewBuilder == nil
    }

    /// `safeAreaInset` supplies the composer height and the current keyboard safe area to the
    /// UIKit-backed list. The inverted list needs only a small, static breathing gap of its own;
    /// calculating a keyboard-height-dependent inset here would desynchronise it from SwiftUI's
    /// interactive keyboard animation.
    private var effectiveChatParams: ChatCustomizationParameters {
        guard shouldFloatInputView else { return chatCustomizationParameters }
        var params = chatCustomizationParameters
        let floatingComposerInset = FloatingComposerLayout.messageInset(
            existingInset: params.contentInsets.top,
            gap: floatingComposerGap
        )
        // NOTE: top and bottom are vice versa here — the conversation table is upside down.
        params.contentInsets.top = floatingComposerInset
        return params
    }

    var waitingForNetwork: some View {
        VStack {
            Rectangle()
                .foregroundColor(theme.colors.mainText.opacity(0.12))
                .frame(height: 1)
            HStack {
                Spacer()
                Image("waiting", bundle: .current)
                Text(chatCustomizationParameters.localization.waitingForNetwork)
                Spacer()
            }
            .padding(.top, 6)
            Rectangle()
                .foregroundColor(theme.colors.mainText.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    var listWithButton: some View {
        switch type {
        case .conversation:
            ZStack(alignment: .bottomTrailing) {
                list

                if chatCustomizationParameters.showScrollToBottomButton, !isScrolledToBottom {
                    Button {
                        self.pendingScrollTo = ScrollToParams(.newestMessage)  // Cannot assign to property: 'self' is immutable
                    } label: {
                        theme.images.scrollToBottom
                            .frame(width: 40, height: 40)
                            .circleBackground(theme.colors.messageFriendBG)
                            .foregroundStyle(theme.colors.sendButtonBackground)
                            .shadow(color: .primary.opacity(0.1), radius: 2, y: 1)
                    }
                    .padding(.trailing, MessageView.horizontalScreenEdgePadding)
                    .padding(.bottom, 8)
                }
            }

        case .comments:
            list
        }
    }

    @ViewBuilder
    var list: some View {
        UIList(
            // MARK: - Core

            viewModel: viewModel,
            inputViewModel: inputViewModel,

            pendingScrollTo: $pendingScrollTo,
            isScrolledToBottom: $isScrolledToBottom,
            tableContentHeight: $tableContentHeight,

            // MARK: - View builders

            messageBuilder: messageBuilder,
            mainHeaderBuilder: mainHeaderBuilder,
            dateHeaderBuilder: dateHeaderBuilder,

            // MARK: - Data / type

            type: type,
            sections: messageProjection.sections,
            ids: messageProjection.ids,

            // MARK: - Customization

            chatParams: effectiveChatParams,
            messageParams: messageCustomizationParameters
        )
        .applyIf(!chatCustomizationParameters.isScrollEnabled) {
            $0.frame(height: tableContentHeight)
        }
        .onStatusBarTap {
            self.pendingScrollTo = ScrollToParams(.oldestMessage)
        }
        .transparentNonAnimatingFullScreenCover(item: $viewModel.messageMenuRow) {
            if let row = viewModel.messageMenuRow {
                messageMenu(row)
                    .onAppear(perform: showMessageMenu)
            }
        }
        .onPreferenceChange(MessageMenuPreferenceKey.self) { frames in
            DispatchQueue.main.async {
                if self.cellFrames != frames {
                    self.cellFrames = frames
                }
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                globalFocusState.focus = nil
            }
        )
        .onAppear {
            viewModel.didSendMessage = didSendMessage
            viewModel.inputViewModel = inputViewModel
            viewModel.globalFocusState = globalFocusState
            if chatCustomizationParameters.autoFocusTextInputOnChatOpen {
                viewModel.focusTheInputTextView()
            }
            if let didUpdateAttachmentStatus {
                viewModel.didUpdateAttachmentStatus = didUpdateAttachmentStatus
            }

            inputViewModel.didSendMessage = { value in
                Task { @MainActor in
                    didSendMessage(value)
                }
                if type == .conversation {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.pendingScrollTo = ScrollToParams(.newestMessage)
                    }
                }
            }
        }
    }

    var inputView: some View {
        ZStack {
            let customInputView = inputViewBuilder(
                InputViewBuilderParameters(
                    text: $inputViewModel.text,
                    attachments: inputViewModel.attachments,
                    inputViewState: inputViewModel.state,
                    inputViewStyle: .message,
                    inputViewActionClosure: inputViewModel.inputViewAction()
                ) {
                    globalFocusState.focus = nil
                }
            )

            if customInputView is DummyView {
                InputView(
                    viewModel: inputViewModel,
                    inputFieldId: viewModel.inputFieldId,
                    style: .message,
                    availableInputs: inputViewCustomizationParameters.availableInputs,
                    recorderSettings: inputViewCustomizationParameters.recorderSettings,
                    localization: chatCustomizationParameters.localization
                )
            } else {
                customInputView
                    .customFocus($globalFocusState.focus, equals: .uuid(viewModel.inputFieldId))
            }
        }
        .environmentObject(globalFocusState)
        .onAppear(perform: inputViewModel.onStart)
        .onDisappear(perform: inputViewModel.onStop)
    }

    func messageMenu(_ row: MessageRow) -> some View {
        let cellFrame = cellFrames[row.id] ?? .zero

        return MessageMenu(
            viewModel: viewModel,
            isShowingMenu: $isShowingMenu,
            message: row.message,
            cellFrame: cellFrame,
            alignment: menuAlignment(row.message, chatType: type),
            positionInUserGroup: row.positionInUserGroup,
            leadingPadding: messageCustomizationParameters.avatarSize
                + MessageView.horizontalScreenEdgePadding + MessageView.horizontalSpacing,
            trailingPadding: MessageView.statusViewWidth + MessageView.horizontalScreenEdgePadding
                + MessageView.horizontalSpacing,
            font: messageCustomizationParameters.font,
            animationDuration: chatCustomizationParameters.messageMenuAnimationDuration,
            onAction: menuActionClosure(row.message),
            reactionHandler: MessageMenu.ReactionConfig(
                delegate: chatCustomizationParameters.reactionDelegate,
                didReact: reactionClosure(row.message)
            )
        ) {
            ChatMessageView(
                viewModel: viewModel,
                messageBuilder: messageBuilder,
                row: row,
                chatType: type,
                messageParams: messageCustomizationParameters,
                isDisplayingMessageMenu: true
            )
            .onTapGesture {
                hideMessageMenu()
            }
        }
    }

    /// Determines the message menu alignment based on ChatType and message sender.
    private func menuAlignment(_ message: Message, chatType: ChatType) -> MessageMenuAlignment {
        switch chatType {
        case .conversation:
            return message.user.isCurrentUser ? .right : .left
        case .comments:
            return .left
        }
    }

    /// Our default reactionCallback flow if the user supports Reactions by implementing the didReactToMessage closure
    private func reactionClosure(_ message: Message) -> (ReactionType?) -> Void {
        { reactionType in
            Task { @MainActor in
                // Hide the menu
                hideMessageMenu()
                // Send the draft reaction
                guard let reactionDelegate = chatCustomizationParameters.reactionDelegate,
                    let reactionType
                else { return }
                reactionDelegate.didReact(
                    to: message, reaction: DraftReaction(messageID: message.id, type: reactionType))
            }
        }
    }

    func menuActionClosure(_ message: Message) -> (MenuAction) -> Void {
        { action in
            hideMessageMenu()
            messageMenuAction(action, viewModel.messageMenuAction(), message)
        }
    }

    func showMessageMenu() {
        isShowingMenu = true
    }

    func hideMessageMenu() {
        viewModel.messageMenuRow = nil
        viewModel.messageFrame = .zero
        isShowingMenu = false
    }

    private func chatBackground() -> some View {
        Group {
            if let background = theme.images.background {
                switch (isLandscape(), colorScheme) {
                case (true, .dark):
                    background.landscapeBackgroundDark
                        .resizable()
                        .ignoresSafeArea(
                            background.safeAreaRegions, edges: background.safeAreaEdges)
                case (true, .light):
                    background.landscapeBackgroundLight
                        .resizable()
                        .ignoresSafeArea(
                            background.safeAreaRegions, edges: background.safeAreaEdges)
                case (false, .dark):
                    background.portraitBackgroundDark
                        .resizable()
                        .ignoresSafeArea(
                            background.safeAreaRegions, edges: background.safeAreaEdges)
                case (false, .light):
                    background.portraitBackgroundLight
                        .resizable()
                        .ignoresSafeArea(
                            background.safeAreaRegions, edges: background.safeAreaEdges)
                default:
                    theme.colors.mainBG
                }
            } else {
                theme.colors.mainBG
            }
        }
    }

    private func isLandscape() -> Bool {
        UIDevice.current.orientation.isLandscape
    }

    private func isGiphyAvailable() -> Bool {
        inputViewCustomizationParameters.availableInputs.contains(AvailableInputType.giphy)
    }

    /// The chat's most recently created message, if any. Sections are already sorted newest-first
    /// for `.conversation`, so this is cheap. Scoped to `.conversation` to match the existing
    /// send-triggered scroll-to-bottom behavior above.
    private var newestMessage: Message? {
        guard type == .conversation else { return nil }
        return messageProjection.sections.first?.rows.first?.message
    }

    private var projectionInput: MessageProjectionInput {
        MessageProjectionInput(messages: messages, chatType: type, replyMode: replyMode)
    }

    public init(
        messages: [Message],
        chatType: ChatType = .conversation,
        replyMode: ReplyMode = .quote,
        didSendMessage: @escaping (DraftMessage) -> Void,
        @ViewBuilder messageBuilder: @escaping (_ params: MessageBuilderParameters) -> MessageContent = { _ in
            DummyView()
        },
        @ViewBuilder inputViewBuilder: @escaping (_ params: InputViewBuilderParameters) -> InputViewContent = { _ in
            DummyView()
        },
        messageMenuAction: @escaping (
            _ selectedMenuAction: MenuAction,
            _ defaultActionClosure: @escaping (Message, DefaultMessageMenuAction) -> Void,
            _ message: Message
        ) -> Void = { (selectedMenuAction: DefaultMessageMenuAction, defaultActionClosure, message) in
            defaultActionClosure(message, selectedMenuAction)
        },
        didUpdateAttachmentStatus: ((AttachmentUploadUpdate) -> Void)? = nil
    ) {
        self.messages = messages
        self.type = chatType
        self.replyMode = replyMode
        self._messageProjection = StateObject(
            wrappedValue: MessageProjectionCache(
                messages: messages,
                chatType: chatType,
                replyMode: replyMode
            )
        )
        self.didSendMessage = didSendMessage
        self.messageBuilder = messageBuilder
        self.inputViewBuilder = inputViewBuilder
        self.messageMenuAction = messageMenuAction
        self.didUpdateAttachmentStatus = didUpdateAttachmentStatus
    }
}

//#Preview {
//    let romeo = User(id: "romeo", name: "Romeo Montague", avatarURL: nil, isCurrentUser: true)
//    let juliet = User(id: "juliet", name: "Juliet Capulet", avatarURL: nil, isCurrentUser: false)
//
//    let monday = try! Date.iso8601Date.parse("2025-05-12")
//    let tuesday = try! Date.iso8601Date.parse("2025-05-13")
//
//    ChatView(messages: [
//        Message(
//            id: "26tb", user: romeo, status: .read, createdAt: monday,
//            text: "And I’ll still stay, to have thee still forget"),
//        Message(
//            id: "zee6", user: romeo, status: .read, createdAt: monday,
//            text: "Forgetting any other home but this"),
//
//        Message(
//            id: "oWUN", user: juliet, status: .read, createdAt: monday,
//            text: "’Tis almost morning. I would have thee gone"),
//        Message(
//            id: "P261", user: juliet, status: .read, createdAt: monday,
//            text: "And yet no farther than a wanton’s bird"),
//        Message(
//            id: "46hu", user: juliet, status: .read, createdAt: monday,
//            text: "That lets it hop a little from his hand"),
//        Message(
//            id: "Gjbm", user: juliet, status: .read, createdAt: monday,
//            text: "Like a poor prisoner in his twisted gyves"),
//        Message(
//            id: "IhRQ", user: juliet, status: .read, createdAt: monday,
//            text: "And with a silken thread plucks it back again"),
//        Message(
//            id: "kwWd", user: juliet, status: .read, createdAt: monday,
//            text: "So loving-jealous of his liberty"),
//
//        Message(
//            id: "9481", user: romeo, status: .read, createdAt: tuesday,
//            text: "I would I were thy bird"),
//
//        Message(
//            id: "dzmY", user: juliet, status: .sent, createdAt: tuesday, text: "Sweet, so would I"),
//        Message(
//            id: "r5HH", user: juliet, status: .sent, createdAt: tuesday,
//            text: "Yet I should kill thee with much cherishing"),
//        Message(
//            id: "quy1", user: juliet, status: .sent, createdAt: tuesday,
//            text: "Good night, good night. Parting is such sweet sorrow"),
//        Message(
//            id: "Mwh6", user: juliet, status: .sent, createdAt: tuesday,
//            text: "That I shall say 'Good night' till it be morrow"),
//    ]) { draft in }
//}

/// Breathing room between the newest message and the floating composer.
let floatingComposerGap: CGFloat = 8

/// Keeps a small gap between the inverted conversation table and its safe-area-inset composer.
/// The safe-area inset itself owns the composer's dynamic height and keyboard movement.
enum FloatingComposerLayout {
    static func messageInset(
        existingInset: CGFloat,
        gap: CGFloat = floatingComposerGap
    ) -> CGFloat {
        max(max(0, existingInset), max(0, gap))
    }
}

/// Keyboard notifications are expressed in screen coordinates while `ChatView` can be embedded
/// in a transformed container. Intersecting the two frames gives the exact bottom padding that
/// keeps the composer directly above the keyboard without relying on any ancestor's safe area.
enum KeyboardLayout {
    static func overlap(container: CGRect, keyboard: CGRect) -> CGFloat {
        guard !keyboard.isEmpty, container.intersects(keyboard) else { return 0 }
        return max(0, min(container.maxY, keyboard.maxY) - max(container.minY, keyboard.minY))
    }
}
