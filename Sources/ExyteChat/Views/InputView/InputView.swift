//
//  InputView.swift
//  Chat
//
//  Created by Alex.M on 25.05.2022.
//

import ExyteMediaPicker
import GiphyUISDK
import SwiftUI

public enum InputViewStyle: Sendable {
    case message
    case signature
}

public enum InputViewAction: Sendable {
    case giphy
    case photo
    case add
    case camera
    case send

    case recordAudioHold
    case recordAudioTap
    case recordAudioLock
    case stopRecordAudio
    case deleteRecord
    case playRecord
    case pauseRecord
    case document
    //    case location

    case saveEdit
    case cancelEdit
}

public enum InputViewState: Sendable {
    case empty
    case hasTextOrMedia

    case waitingForRecordingPermission
    case isRecordingHold
    case isRecordingTap
    case hasRecording
    case playingRecording
    case pausedRecording

    case editing

    var canSend: Bool {
        switch self {
        case .hasTextOrMedia, .hasRecording, .isRecordingTap, .playingRecording, .pausedRecording:
            return true
        default: return false
        }
    }
}

public enum AvailableInputType: Sendable {
    case text
    case media
    case audio
    case giphy
}

public struct InputViewAttachments {
    var medias: [Media] = []
    var recording: Recording?
    var giphyMedia: GPHMedia?
    var replyMessage: ReplyMessage?
}

struct InputView: View {

    @Environment(\.chatTheme) private var theme
    @Environment(\.mediaPickerTheme) private var pickerTheme

    @EnvironmentObject private var keyboardState: KeyboardState
    @EnvironmentObject private var globalFocusState: GlobalFocusState

    @ObservedObject var viewModel: InputViewModel
    var inputFieldId: UUID
    var style: InputViewStyle
    var availableInputs: [AvailableInputType]
    var recorderSettings: RecorderSettings = RecorderSettings()
    var localization: ChatLocalization

    @StateObject var recordingPlayer = RecordingPlayer()

    private var onAction: (InputViewAction) -> Void {
        viewModel.inputViewAction()
    }

    private var state: InputViewState {
        viewModel.state
    }

    private var isFocused: Bool {
        globalFocusState.focus == .uuid(inputFieldId)
    }

    private var isRecordingState: Bool {
        [.isRecordingHold, .isRecordingTap, .hasRecording, .playingRecording, .pausedRecording]
            .contains(state)
    }

    /// Drives the compact (pill, inline controls) ↔ expanded (card, controls below text) morph.
    /// Recording has its own dedicated layout and never expands this way.
    private var isExpanded: Bool {
        style == .message && !isRecordingState && isFocused
    }

    private var composerCornerRadius: CGFloat { 26 }

    @State private var showAttachMenu = false

    @State private var overlaySize: CGSize = .zero

    @State private var recordButtonFrame: CGRect = .zero
    @State private var lockRecordFrame: CGRect = .zero
    @State private var deleteRecordFrame: CGRect = .zero

    @State private var dragStart: Date?
    @State private var tapDelayTimer: Timer?
    @State private var cancelGesture = false
    private let tapDelay = 0.2

    var body: some View {
        VStack(spacing: 8) {
            viewOnTop
                .padding(.top, 6)
                .transition(.move(edge: .bottom))

            HStack(alignment: .bottom, spacing: 10) {
                composerCard

                if state == .editing {
                    editingButtons
                        .frame(height: 48)
                }
            }
            .padding(
                .horizontal,
                isExpanded
                    ? MessageView.horizontalScreenEdgePadding
                    : MessageView.horizontalScreenEdgePadding + 14
            )
            .padding(.vertical, 8)
            .animation(.smooth(duration: 0.3), value: isExpanded)
        }
        .background(Color.clear)
        .onAppear {
            viewModel.recordingPlayer = recordingPlayer
            viewModel.setRecorderSettings(recorderSettings: recorderSettings)
        }
        .onDrag(towards: .bottom, ofAmount: 100...) {
            keyboardState.resignFirstResponder()
        }
    }

    /// `.signature` style and recording keep the original single-row layout (re-skinned with
    /// the new glass background); the normal `.message` compose flow morphs between compact
    /// and expanded via `ComposerLayout`, driven purely by focus.
    @ViewBuilder
    private var composerCard: some View {
        Group {
            if style == .signature || isRecordingState {
                legacyComposerRow
            } else {
                ComposerLayout(isExpanded: isExpanded, spacing: 4) {
                    attachSlot
                    TextInputView(
                        text: $viewModel.text,
                        inputFieldId: inputFieldId,
                        style: style,
                        availableInputs: availableInputs,
                        localization: localization
                    )
                    trailingSlot
                }
                .padding(.horizontal, 4)
                .padding(.vertical, isExpanded ? 8 : 4)
            }
        }
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous))
        .animation(.smooth(duration: 0.3), value: isExpanded)
    }

    private var legacyComposerRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            leftView
            middleView
            rightView
        }
    }

    @ViewBuilder
    private var attachSlot: some View {
        if isMediaAvailable() || isGiphyAvailable() {
            attachButton
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    @ViewBuilder
    private var trailingSlot: some View {
        if state == .editing {
            Color.clear.frame(width: 1, height: 1)
        } else {
            sendRecordButton
        }
    }

    @ViewBuilder
    var leftView: some View {
        if isRecordingState {
            deleteRecordButton
        } else {
            // Only reached for `.signature` style now — `.message` outside recording uses
            // `ComposerLayout`/`attachSlot` instead.
            if viewModel.mediaPickerMode == .cameraSelection {
                addButton
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
        }
    }

    @ViewBuilder
    var middleView: some View {
        Group {
            switch state {
            case .hasRecording, .playingRecording, .pausedRecording:
                recordWaveform
            case .isRecordingHold:
                swipeToCancel
            case .isRecordingTap:
                recordingInProgress
            default:
                TextInputView(
                    text: $viewModel.text,
                    inputFieldId: inputFieldId,
                    style: style,
                    availableInputs: availableInputs,
                    localization: localization
                )
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    var rightView: some View {
        HStack(spacing: 4) {
            switch state {
            case .isRecordingHold, .isRecordingTap:
                recordDurationInProcess
            case .hasRecording:
                recordDuration
            case .playingRecording, .pausedRecording:
                recordDurationLeft
            default:
                EmptyView()
            }

            if state != .editing {
                sendRecordButton
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    var editingButtons: some View {
        HStack {
            Button {
                onAction(.cancelEdit)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
                    .padding(5)
                    .background(Circle().foregroundStyle(.red))
            }

            Button {
                onAction(.saveEdit)
            } label: {
                Image(systemName: "checkmark")
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
                    .padding(5)
                    .background(Circle().foregroundStyle(.green))
            }
        }
    }

    @ViewBuilder
    var sendRecordButton: some View {
        Group {
            if state.canSend || !isAudioAvailable() {
                sendButton
                    .disabled(!state.canSend)
            } else {
                recordButton
                    .highPriorityGesture(dragGesture())
            }
        }
        .background {
            if [.isRecordingTap, .isRecordingHold].contains(state) {
                RecordIndicator()
                    .viewSize(60)
                    .foregroundColor(theme.colors.sendButtonBackground)
            }
        }
        .compositingGroup()
        .overlay(alignment: .top) {
            Group {
                if state == .isRecordingTap {
                    stopRecordButton
                } else if state == .isRecordingHold {
                    lockRecordButton
                }
            }
            .sizeGetter($overlaySize)
            // hardcode 28 for now because sizeGetter returns 0 somehow
            .offset(y: (state == .isRecordingTap ? -28 : -overlaySize.height) - 24)
        }
    }

    @ViewBuilder
    var viewOnTop: some View {
        if let message = viewModel.attachments.replyMessage {
            VStack(spacing: 8) {
                Rectangle()
                    .foregroundColor(theme.colors.messageFriendBG)
                    .frame(height: 2)

                HStack {
                    theme.images.reply.replyToMessage
                    Capsule()
                        .foregroundColor(theme.colors.messageMyBG)
                        .frame(width: 2)
                    VStack(alignment: .leading) {
                        Text(localization.replyToText + " " + message.user.name)
                            .font(.caption2)
                            .foregroundColor(theme.colors.mainCaptionText)
                        if !message.attributedText.characters.isEmpty {
                            Text(message.attributedText)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundColor(theme.colors.mainText)
                        }
                    }
                    .padding(.vertical, 2)

                    Spacer()

                    if let first = message.attachments.first {
                        AsyncImageView(attachment: first, size: CGSize(width: 30, height: 30))
                            .viewSize(30)
                            .cornerRadius(4)
                            .padding(.trailing, 16)
                    }

                    if message.recording != nil {
                        theme.images.inputView.microphone
                            .renderingMode(.template)
                            .foregroundColor(theme.colors.mainTint)
                    }

                    theme.images.reply.cancelReply
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.attachments.replyMessage = nil
                            }
                        }
                }
                .padding(.horizontal, 26)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    var attachButton: some View {
        Button {
            showAttachMenu = true
        } label: {
            theme.images.inputView.add
                .renderingMode(.template)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(theme.colors.inputIcon)
                .viewSize(24)
                .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
        .popover(isPresented: $showAttachMenu) {
            attachMenuContent
        }
    }

    var attachMenuContent: some View {
        VStack(spacing: 0) {
            if isMediaAvailable() {
                attachMenuRow(icon: theme.images.attachMenu.photo, title: localization.photoLibraryText) {
                    onAction(.photo)
                }
                Divider()
                attachMenuRow(icon: theme.images.attachMenu.camera, title: localization.cameraText) {
                    onAction(.camera)
                }
                Divider()
                attachMenuRow(icon: theme.images.attachMenu.document, title: localization.filesText) {
                    onAction(.document)
                }
            }
            if isMediaAvailable(), isGiphyAvailable() {
                Divider()
            }
            if isGiphyAvailable() {
                attachMenuRow(icon: theme.images.inputView.sticker, title: localization.giphyText) {
                    onAction(.giphy)
                }
            }
        }
        .frame(width: 220)
        .presentationCompactAdaptation(.popover)
    }

    func attachMenuRow(icon: Image, title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showAttachMenu = false
        } label: {
            HStack(spacing: 12) {
                icon
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(theme.colors.inputIcon)
                    .aspectRatio(contentMode: .fit)
                    .viewSize(22)
                Text(title)
                    .foregroundColor(theme.colors.mainText)
                Spacer()
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        }
        .buttonStyle(.plain)
    }

    var addButton: some View {
        Button {
            onAction(.add)
        } label: {
            theme.images.inputView.add
                .renderingMode(.template)
                .foregroundColor(theme.colors.inputIcon)
                .viewSize(22)
                .circleBackground(theme.colors.sendButtonBackground)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 8))
        }
    }

    var sendButton: some View {
        Button {
            onAction(.send)
        } label: {
            theme.images.inputView.arrowSend
                .renderingMode(.template)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.colors.recordButtonBackground))
                .padding(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
        }
    }

    var recordButton: some View {
        theme.images.inputView.microphone
            .renderingMode(.template)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(theme.colors.recordButtonBackground))
            .padding(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
            .frameGetter($recordButtonFrame)
    }

    var deleteRecordButton: some View {
        Button {
            onAction(.deleteRecord)
        } label: {
            theme.images.recordAudio.deleteRecord
                .viewSize(22)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 8))
        }
        .frameGetter($deleteRecordFrame)
    }

    var stopRecordButton: some View {
        Button {
            onAction(.stopRecordAudio)
        } label: {
            theme.images.recordAudio.stopRecord
                .viewSize(28)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                )
        }
    }

    var lockRecordButton: some View {
        Button {
            onAction(.recordAudioLock)
        } label: {
            VStack(spacing: 20) {
                theme.images.recordAudio.lockRecord
                theme.images.recordAudio.sendRecord
            }
            .frame(width: 28)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            )
        }
        .frameGetter($lockRecordFrame)
    }

    var swipeToCancel: some View {
        HStack {
            Spacer()
            Button {
                onAction(.deleteRecord)
            } label: {
                HStack {
                    theme.images.recordAudio.cancelRecord
                        .renderingMode(.template)
                        .foregroundStyle(theme.colors.mainText)
                    Text(localization.cancelButtonText)
                        .font(.footnote)
                        .foregroundColor(theme.colors.mainText)
                }
            }
            Spacer()
        }
    }

    var recordingInProgress: some View {
        HStack {
            Spacer()
            Text(localization.recordingText)
                .font(.footnote)
                .foregroundColor(theme.colors.mainText)
            Spacer()
        }
    }

    var recordDurationInProcess: some View {
        HStack {
            Circle()
                .foregroundColor(theme.colors.recordDot)
                .viewSize(6)
            recordDuration
        }
    }

    var recordDuration: some View {
        Text(DateFormatter.timeString(Int(viewModel.attachments.recording?.duration ?? 0)))
            .foregroundColor(theme.colors.mainText)
            .opacity(0.6)
            .font(.caption2)
            .monospacedDigit()
            .padding(.trailing, 12)
    }

    var recordDurationLeft: some View {
        Text(DateFormatter.timeString(Int(recordingPlayer.secondsLeft)))
            .foregroundColor(theme.colors.mainText)
            .opacity(0.6)
            .font(.caption2)
            .monospacedDigit()
            .padding(.trailing, 12)
    }

    var playRecordButton: some View {
        Button {
            onAction(.playRecord)
        } label: {
            theme.images.recordAudio.playRecord
        }
    }

    var pauseRecordButton: some View {
        Button {
            onAction(.pauseRecord)
        } label: {
            theme.images.recordAudio.pauseRecord
        }
    }

    @ViewBuilder
    var recordWaveform: some View {
        if let recording = viewModel.attachments.recording {
            HStack(spacing: 8) {
                Group {
                    if state == .hasRecording || state == .pausedRecording {
                        playRecordButton
                    } else if state == .playingRecording {
                        pauseRecordButton
                    }
                }
                .frame(width: 20)

                RecordWaveformPlaying(
                    samples: recording.waveformSamples, progress: recordingPlayer.progress,
                    color: theme.colors.mainText, addExtraDots: true
                ) { progress in
                    Task {
                        await recordingPlayer.seek(with: recording, to: progress)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    var backgroundColor: Color {
        switch style {
        case .message:
            return theme.contentBG
        case .signature:
            return pickerTheme.main.pickerBackground
        }
    }

    func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0.0, coordinateSpace: .global)
            .onChanged { [state] value in
                if dragStart == nil {
                    dragStart = Date()
                    cancelGesture = false
                    tapDelayTimer = Timer.scheduledTimer(withTimeInterval: tapDelay, repeats: false)
                    { _ in
                        if state != .isRecordingTap, state != .waitingForRecordingPermission {
                            DispatchQueue.main.async {
                                self.onAction(.recordAudioHold)
                            }
                        }
                    }
                }

                if value.location.y < lockRecordFrame.minY,
                    value.location.x > recordButtonFrame.minX
                {
                    cancelGesture = true
                    onAction(.recordAudioLock)
                }

                if value.location.x < UIScreen.main.bounds.width / 2,
                    value.location.y > recordButtonFrame.minY
                {
                    cancelGesture = true
                    onAction(.deleteRecord)
                }
            }
            .onEnded { value in
                if !cancelGesture {
                    tapDelayTimer = nil
                    if recordButtonFrame.contains(value.location) {
                        if let dragStart = dragStart, Date().timeIntervalSince(dragStart) < tapDelay
                        {
                            onAction(.recordAudioTap)
                        } else if state != .waitingForRecordingPermission {
                            onAction(.send)
                        }
                    } else if lockRecordFrame.contains(value.location) {
                        onAction(.recordAudioLock)
                    } else if deleteRecordFrame.contains(value.location) {
                        onAction(.deleteRecord)
                    } else {
                        onAction(.send)
                    }
                }
                dragStart = nil
            }
    }

    private func isAudioAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.audio)
    }

    private func isGiphyAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.giphy)
    }

    private func isMediaAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.media)
    }
}

@MainActor
func performBatchTableUpdates(_ tableView: UITableView, closure: () -> Void) async {
    await withCheckedContinuation { continuation in
        tableView.performBatchUpdates {
            closure()
        } completion: { _ in
            continuation.resume()
        }
    }
}
