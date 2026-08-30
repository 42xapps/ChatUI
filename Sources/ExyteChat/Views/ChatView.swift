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

public enum ChatType: CaseIterable, Sendable {
    case conversation  // the latest message is at the bottom, new messages appear from the bottom
    case comments  // the latest message is at the top, new messages appear from the top
}

public enum ReplyMode: CaseIterable, Sendable {
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

    var type: ChatType
    var sections: [MessagesSection]
    var ids: [String]
    var didSendMessage: (DraftMessage) -> DraftSubmissionDisposition
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

    @State private var pendingScrollTo: ScrollToParams?
    @State private var isScrolledToBottom: Bool = true
    @State private var tableContentHeight: CGFloat = 0

    @State private var cellFrames = [String: CGRect]()
    /// Used to prevent the MainView from responding to keyboard changes while the Menu is active
    @State private var isShowingMenu = false

    /// Measured height of the floating composer itself. The table's adjusted inset handles system
    /// safe areas separately, so including them here would double-count the keyboard.
    @State private var floatingComposerHeight: CGFloat = 0

    @State private var giphyConfigured = false
    @State private var selectedGiphyMedia: GPHMedia? = nil

    public var body: some View {
        mainView
            .background(chatBackground())
            // Blur parent when fullscreen media sheet is shown
            .blur(radius: viewModel.fullscreenAttachmentPresented ? 12 : 0)
            .animation(.easeInOut(duration: 0.35), value: viewModel.fullscreenAttachmentPresented)
            .environmentObject(keyboardState)
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
                    guard inputViewCustomizationParameters.areActionsEnabled else {
                        selectedGiphyMedia = nil
                        return
                    }
                    // Consume the bridge binding immediately so selecting the same GIF later still
                    // publishes a change. InputViewModel owns compatibility and submission guards.
                    selectedGiphyMedia = nil
                    inputViewModel.submitGiphy(giphyMedia)
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
                let attachments = sections.flatMap { section in
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

    var mainView: some View {
        VStack(spacing: 0) {
            if chatCustomizationParameters.showNetworkConnectionProblem, !networkMonitor.isConnected
            {
                waitingForNetwork
            }

            if shouldFloatInputView {
                ZStack(alignment: .bottom) {
                    listWithButton
                    inputView
                        .padding(.bottom, floatingComposerBottomPadding)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: FloatingComposerHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        )
                }
                .onPreferenceChange(FloatingComposerHeightKey.self) { height in
                    floatingComposerHeight = height
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
        .ignoresSafeArea(isShowingMenu ? .keyboard : [])
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

    private var scrollToBottomButtonBottomPadding: CGFloat {
        shouldFloatInputView
            ? effectiveFloatingComposerHeight + floatingComposerGap
            : 8
    }

    private var effectiveFloatingComposerHeight: CGFloat {
        max(floatingComposerHeight, minimumCompactComposerHeight)
    }

    /// A true `ZStack` overlay (not `safeAreaInset`/`safeAreaBar`) lets the message list's own
    /// content extend behind the floating composer, which is what makes its glass background
    /// actually show blurred content through it instead of just looking like a solid fill.
    /// `safeAreaBar`'s automatic scroll-edge effect doesn't reach into `UIList`'s
    /// `UIViewRepresentable`-wrapped table view, so it isn't relied on here — instead the table
    /// gets a modest content inset (sized for the compact composer) so the newest message still
    /// clears it at rest, while remaining free to scroll behind it.
    private var effectiveChatParams: ChatCustomizationParameters {
        guard shouldFloatInputView else { return chatCustomizationParameters }
        var params = chatCustomizationParameters
        // Measured, not fixed. The composer switches to a taller two-row layout once the draft
        // wraps (see `ComposerLayout`) and keeps growing with it, so a constant sized for the
        // compact state leaves the newest messages sitting behind it.
        let floatingComposerInset = effectiveFloatingComposerHeight + floatingComposerGap
        // NOTE: top and bottom are vice versa here — the conversation table is upside down.
        params.contentInsets.top = max(params.contentInsets.top, floatingComposerInset)
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
            ZStack(alignment: .bottom) {
                list
                    .applyIf(shouldFloatInputView) {
                        $0.ignoresSafeArea(.container, edges: [.top, .bottom])
                    }

                if chatCustomizationParameters.showScrollToBottomButton, !isScrolledToBottom {
                    Button {
                        pendingScrollTo = ScrollToParams(.newestMessage)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(
                                width: InputView.controlChipSize,
                                height: InputView.controlChipSize
                            )
                            .background(
                                Circle().fill(theme.colors.recordButtonBackground)
                            )
                            .shadow(color: .primary.opacity(0.1), radius: 2, y: 1)
                            .frame(width: 44, height: 44)
                    }
                    .padding(.bottom, scrollToBottomButtonBottomPadding)
                    .accessibilityLabel("Scroll to latest messages")
                    .accessibilityIdentifier("chat-scroll-to-latest")
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
            sections: sections,
            ids: ids,

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
            viewModel.didSendMessage = { draft in
                _ = didSendMessage(draft)
            }
            viewModel.inputViewModel = inputViewModel
            viewModel.globalFocusState = globalFocusState
            if chatCustomizationParameters.autoFocusTextInputOnChatOpen {
                viewModel.focusTheInputTextView()
            }
            if let didUpdateAttachmentStatus {
                viewModel.didUpdateAttachmentStatus = didUpdateAttachmentStatus
            }

            inputViewModel.didSendMessage = { value in
                let disposition = didSendMessage(value)
                if disposition == .accepted, type == .conversation {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.pendingScrollTo = ScrollToParams(.newestMessage)
                    }
                }
                return disposition
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
                    availableAttachmentInputs: inputViewCustomizationParameters.availableAttachmentInputs,
                    areActionsEnabled: inputViewCustomizationParameters.areActionsEnabled,
                    recorderSettings: inputViewCustomizationParameters.recorderSettings,
                    localization: chatCustomizationParameters.localization
                )
            } else {
                customInputView
                    .customFocus($globalFocusState.focus, equals: .uuid(viewModel.inputFieldId))
            }
        }
        .environmentObject(globalFocusState)
        .onAppear {
            configureInputViewModel()
            inputViewModel.onStart()
        }
        .onChange(of: inputViewCustomizationParameters.areActionsEnabled) {
            configureInputViewModel()
        }
        .onChange(
            of: inputViewCustomizationParameters.mediaPickerParameters.selectionParameters
                .selectionLimit
        ) {
            configureInputViewModel()
        }
        .onChange(of: inputViewCustomizationParameters.allowsMixedMediaAndGiphy) {
            configureInputViewModel()
        }
        .onDisappear(perform: inputViewModel.onStop)
    }

    private func configureInputViewModel() {
        inputViewModel.configureInputActions(
            enabled: inputViewCustomizationParameters.areActionsEnabled,
            maximumMediaCount: inputViewCustomizationParameters.mediaPickerParameters
                .selectionParameters.selectionLimit,
            allowsMixedMediaAndGiphy: inputViewCustomizationParameters.allowsMixedMediaAndGiphy
        )
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

    /// The chat's most recently created message, if any. `sections`/`ids` are already sorted
    /// newest-first for `.conversation`, so this is cheap and doesn't require holding onto the
    /// raw `messages` array. Scoped to `.conversation` to match the existing send-triggered
    /// scroll-to-bottom behavior above.
    private var newestMessage: Message? {
        guard type == .conversation else { return nil }
        return sections.first?.rows.first?.message
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
private let floatingComposerGap: CGFloat = 8

/// Space between the composer and the bottom edge of the chat. Kept small so the input sits
/// low on screen while still clearing the home indicator on most devices.
private let floatingComposerBottomPadding: CGFloat = 4

/// Fallback until the composer's preference reports a real height. Sized for the compact
/// `.message` composer: reply strip padding, row insets, card padding, and the 48pt input row.
private let minimumCompactComposerHeight: CGFloat = 82

/// Reports the floating composer's rendered height up to `ChatView`, so the message list can
/// inset by however tall it currently is rather than a constant.
private struct FloatingComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
