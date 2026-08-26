//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Combine
import ExyteMediaPicker
import FanPicker
import SwiftUI

@MainActor
final class InputViewModel: ObservableObject {

    /// Which half of the full screen picker a selection came from. They are reported through a
    /// single callback and only the picker's mode tells them apart.
    enum PickerSource {
        case library
        case camera
    }

    @Published var text = ""
    @Published var attachments = InputViewAttachments()
    @Published var state: InputViewState = .empty

    @Published var showGiphyPicker = false
    @Published var showPicker = false
    @Published var showDocumentPicker = false
  
    @Published var mediaPickerMode = MediaPickerMode.photos

    @Published var showActivityIndicator = false

    /// Set while the quick-attach fan is being held open, so the message list stops scrolling out
    /// from under the gesture.
    @Published var isScrollLocked = false
    @Published var photoAccessDenied = false

    var recordingPlayer: RecordingPlayer?
    var didSendMessage: ((DraftMessage) -> Void)?

    /// What the composer had staged before the full screen picker opened, so cancelling that
    /// picker only discards its own session and leaves quick-attached photos alone.
    ///
    /// Non-nil only while that picker is on screen. Sending closes the picker, and the dismissal
    /// makes the editor replay its last selection — without this window that replay would land the
    /// just-sent photos back in the composer.
    private var mediasBeforePicker: [Media]?

    /// The live picker session, kept per source. The picker reports library picks and camera
    /// captures through one callback, each carrying only its own selection, so tracking them apart
    /// is what stops a capture from wiping everything picked from the library.
    private var libraryPicks: [Media] = []
    private var cameraPicks: [Media] = []
    private var previewedPick: Media?

    private var recorder = Recorder()

    private var saveEditingClosure: ((String) -> Void)?

    private var recordPlayerSubscription: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()
    
    func setRecorderSettings(recorderSettings: RecorderSettings = RecorderSettings()) {
        Task {
            await self.recorder.setRecorderSettings(recorderSettings)
        }
    }

    func onStart() {
        RecentPhotoMediaModel.cleanTempDirectory()
        subscribeValidation()
        subscribePicker()
        subscribeGiphyPicker()
    }

    func onStop() {
        subscriptions.removeAll()
    }

    func reset() {
        DispatchQueue.main.async { [weak self] in
            self?.showPicker = false
            self?.showGiphyPicker = false
            self?.showDocumentPicker = false
            self?.text = ""
            self?.saveEditingClosure = nil
            self?.attachments = InputViewAttachments()
            self?.mediasBeforePicker = nil
            self?.clearPickerSession()
            self?.subscribeValidation()
            self?.state = .empty
        }
    }

    func send() {
        Task {
            await recorder.stopRecording()
            await recordingPlayer?.reset()
            sendMessage()
        }
    }

    func edit(_ closure: @escaping (String) -> Void) {
        saveEditingClosure = closure
        state = .editing
    }

    func appendRecentPhoto(_ selection: RecentPhotoSelection) {
        attachments.medias.append(Media(recentPhoto: selection))
        attachments.mediaPreviews[selection.id] = selection.asset.image
    }

    func removeAttachment(id: UUID) {
        attachments.medias.removeAll { $0.id == id }
        attachments.mediaPreviews[id] = nil
        RecentPhotoMediaModel.cleanup(id: id)
    }

    /// Replaces what `source` currently contributes to the picker session and restages the whole
    /// session on top of what the composer already held.
    func stagePickerSelection(_ picked: [Media], from source: PickerSource) {
        switch source {
        case .library:
            libraryPicks = picked
        case .camera:
            cameraPicks = picked
        }
        restagePickerSession()
    }

    /// Photos opened full screen in the picker count as the selection when nothing is checked.
    func stagePreviewedMedia(_ media: Media?) {
        previewedPick = media
        restagePickerSession()
    }

    func cancelPicker() {
        if let mediasBeforePicker {
            attachments.medias = mediasBeforePicker
        }
        showPicker = false
    }

    /// Does nothing once the picker has closed, since by then its selection has either been staged
    /// already or deliberately discarded. Without that window, the replay the editor performs as
    /// the picker goes away would land a just-sent photo back in the composer.
    private func restagePickerSession() {
        guard let mediasBeforePicker else { return }
        let checked = libraryPicks + cameraPicks
        let session = checked.isEmpty ? [previewedPick].compactMap { $0 } : checked
        attachments.medias = mediasBeforePicker + session
    }

    private func clearPickerSession() {
        libraryPicks = []
        cameraPicks = []
        previewedPick = nil
    }

    func inputViewAction() -> (InputViewAction) -> Void {
        { [weak self] in
            self?.inputViewActionInternal($0)
        }
    }

    private func inputViewActionInternal(_ action: InputViewAction) {
        switch action {
        case .giphy:
            showGiphyPicker = true
        case .photo:
            mediaPickerMode = .photos
            showPicker = true
        case .add:
            mediaPickerMode = .camera
        case .camera:
            mediaPickerMode = .camera
            showPicker = true
        case .document:
            showDocumentPicker = true
        case .send:
            send()
        case .recordAudioTap:
            Task {
                state = await recorder.isAllowedToRecordAudio ? .isRecordingTap : .waitingForRecordingPermission
                await recordAudio()
            }
        case .recordAudioHold:
            Task {
                state = await recorder.isAllowedToRecordAudio ? .isRecordingHold : .waitingForRecordingPermission
                await recordAudio()
            }
        case .recordAudioLock:
            state = .isRecordingTap
        case .stopRecordAudio:
            Task {
                await recorder.stopRecording()
                if let _ = attachments.recording {
                    state = .hasRecording
                }
                await recordingPlayer?.reset()
            }
        case .deleteRecord:
            Task {
                unsubscribeRecordPlayer()
                await recorder.stopRecording()
                attachments.recording = nil
            }
        case .playRecord:
            state = .playingRecording
            if let recording = attachments.recording {
                Task {
                    subscribeRecordPlayer()
                    await recordingPlayer?.play(recording)
                }
            }
        case .pauseRecord:
            state = .pausedRecording
            Task {
                await recordingPlayer?.pause()
            }
        case .saveEdit:
            saveEditingClosure?(text)
            reset()
        case .cancelEdit:
            reset()
        }
    }

    private func recordAudio() async {
        guard !(await recorder.isRecording) else { return }

        attachments.recording = Recording()
        let url = await recorder.startRecording { [weak self] duration, samples in
            Task { @MainActor [weak self] in
                self?.attachments.recording?.duration = duration
                self?.attachments.recording?.waveformSamples = samples
            }
        }

        guard let url else {
            attachments.recording = nil
            state = .empty
            return
        }

        attachments.recording?.url = url
        if state == .waitingForRecordingPermission {
            state = .isRecordingTap
        }
    }
}

private extension InputViewModel {

    public func validateDraft() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard state != .editing else { return } // special case
            if !self.text.isEmpty || !self.attachments.medias.isEmpty {
                self.state = .hasTextOrMedia
            } else if self.text.isEmpty,
                      self.attachments.medias.isEmpty,
                      self.attachments.recording == nil {
                self.state = .empty
            }
        }
    }

    func subscribeValidation() {
        $attachments.sink { [weak self] _ in
            self?.validateDraft()
        }
        .store(in: &subscriptions)

        $text.sink { [weak self] _ in
            self?.validateDraft()
        }
        .store(in: &subscriptions)
    }

    func subscribeGiphyPicker() {
        $showGiphyPicker
            .sink { [weak self] value in
                if !value {
                  self?.attachments.giphyMedia = nil
                }
            }
            .store(in: &subscriptions)
    }
  
    func subscribePicker() {
        $showPicker
            .sink { [weak self] isPresented in
                guard let self else { return }
                mediasBeforePicker = isPresented ? attachments.medias : nil
                clearPickerSession()
            }
            .store(in: &subscriptions)
    }

    func subscribeRecordPlayer() {
        Task { @MainActor in
            if let recordingPlayer {
                recordPlayerSubscription = recordingPlayer.didPlayTillEnd
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] in
                        self?.state = .hasRecording
                    }
            }
        }
    }

    func unsubscribeRecordPlayer() {
        recordPlayerSubscription = nil
    }
}

private extension InputViewModel {

    func sendMessage() {
        showActivityIndicator = true
        let draft = DraftMessage(
            text: text,
            medias: attachments.medias,
            giphyMedia: attachments.giphyMedia,
            recording: attachments.recording,
            replyMessage: attachments.replyMessage,
            createdAt: Date()
        )
        didSendMessage?(draft)
        DispatchQueue.main.async { [weak self] in
            self?.showActivityIndicator = false
            self?.reset()
        }
    }
}
