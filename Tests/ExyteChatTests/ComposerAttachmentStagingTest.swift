import ExyteMediaPicker
import Foundation
import Testing

@testable import ExyteChat

/// Covers how the composer stages media coming out of the full screen picker. The sequences here
/// mirror what `AttachmentsEditor` actually does: it stages on every selection change, and the
/// picker's dismissal is what ends a session — including the dismissal a send causes.
@MainActor
struct ComposerAttachmentStagingTest {

    @Test("Sending clears the composer even though the picker's dismissal replays its selection")
    func sendDoesNotRestageSentMedia() async {
        let viewModel = InputViewModel()
        viewModel.onStart()

        var sent: [DraftMessage] = []
        viewModel.didSendMessage = { sent.append($0) }

        let photo = Media.stub()
        viewModel.showPicker = true
        viewModel.stagePickerSelection([photo], from: .library)
        #expect(viewModel.attachments.medias == [photo])

        viewModel.send()
        await viewModel.settle()

        #expect(sent.count == 1)
        #expect(sent.first?.medias == [photo])

        // The editor still holds the finished session's selection and replays it as the picker goes
        // away. That replay must not put the sent photo back into the composer.
        viewModel.stagePickerSelection([photo], from: .library)
        #expect(viewModel.attachments.medias.isEmpty)
        #expect(viewModel.state == .empty)
    }

    @Test("A second picker session sends only its own selection")
    func consecutiveSessionsDoNotAccumulate() async {
        let viewModel = InputViewModel()
        viewModel.onStart()

        var sent: [DraftMessage] = []
        viewModel.didSendMessage = { sent.append($0) }

        let first = Media.stub()
        viewModel.showPicker = true
        viewModel.stagePickerSelection([first], from: .library)
        viewModel.send()
        await viewModel.settle()
        viewModel.stagePickerSelection([first], from: .library)

        let second = Media.stub()
        viewModel.showPicker = true
        viewModel.stagePickerSelection([second], from: .library)
        viewModel.send()
        await viewModel.settle()

        #expect(sent.count == 2)
        #expect(sent.first?.medias == [first])
        #expect(sent.last?.medias == [second])
    }

    @Test("Closing the picker without sending leaves its selection staged to write a message around")
    func dismissingPickerKeepsStagedMedia() async {
        let viewModel = InputViewModel()
        viewModel.onStart()

        let picked = Media.stub()
        viewModel.showPicker = true
        viewModel.stagePickerSelection([picked], from: .library)

        viewModel.showPicker = false
        // The editor replays its last selection as the picker goes away; that must neither drop the
        // staging nor duplicate it.
        viewModel.stagePickerSelection([picked], from: .library)

        #expect(viewModel.attachments.medias == [picked])

        viewModel.text = "what is in this photo?"
        var sent: [DraftMessage] = []
        viewModel.didSendMessage = { sent.append($0) }
        viewModel.send()
        await viewModel.settle()

        #expect(sent.first?.medias == [picked])
        #expect(sent.first?.text == "what is in this photo?")
    }

    @Test("A camera capture is staged alongside library picks instead of replacing them")
    func cameraAndLibraryPicksAreStagedTogether() async {
        let viewModel = InputViewModel()
        viewModel.onStart()

        let firstLibrary = Media.stub()
        let secondLibrary = Media.stub()
        let capture = Media.stub()

        viewModel.showPicker = true
        // Each half of the picker reports only its own selection through the shared callback.
        viewModel.stagePickerSelection([firstLibrary, secondLibrary], from: .library)
        viewModel.stagePickerSelection([capture], from: .camera)

        #expect(viewModel.attachments.medias == [firstLibrary, secondLibrary, capture])

        // Unchecking a library photo must leave the capture staged.
        viewModel.stagePickerSelection([firstLibrary], from: .library)
        #expect(viewModel.attachments.medias == [firstLibrary, capture])

        var sent: [DraftMessage] = []
        viewModel.didSendMessage = { sent.append($0) }
        viewModel.send()
        await viewModel.settle()

        #expect(sent.first?.medias == [firstLibrary, capture])
    }

    @Test("A previewed photo counts as the selection only while nothing is checked")
    func previewedMediaYieldsToCheckedSelection() async {
        let viewModel = InputViewModel()
        viewModel.onStart()

        let previewed = Media.stub()
        let checked = Media.stub()

        viewModel.showPicker = true
        viewModel.stagePreviewedMedia(previewed)
        #expect(viewModel.attachments.medias == [previewed])

        viewModel.stagePickerSelection([checked], from: .library)
        #expect(viewModel.attachments.medias == [checked])
    }

    @Test("The picker stages on top of a quick-attached photo, and cancelling keeps it")
    func cancellingPickerKeepsQuickAttachedMedia() async {
        let viewModel = InputViewModel()
        viewModel.onStart()

        let quickAttached = Media.stub()
        viewModel.attachments.medias = [quickAttached]

        let picked = Media.stub()
        viewModel.showPicker = true
        viewModel.stagePickerSelection([picked], from: .library)
        #expect(viewModel.attachments.medias == [quickAttached, picked])

        viewModel.cancelPicker()
        #expect(viewModel.attachments.medias == [quickAttached])
    }
}

private extension InputViewModel {

    /// `send` stops the recorder and `reset` hops through the main queue twice, so waiting for the
    /// composer to empty is what tells us the send has fully landed.
    func settle() async {
        for _ in 0..<100 {
            if attachments.medias.isEmpty { return }
            await Task.yield()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}

private extension Media {

    static func stub() -> Media {
        Media(source: StubMediaModel())
    }
}

private struct StubMediaModel: MediaModelProtocol {

    var mediaType: MediaType? { .image }

    var duration: CGFloat? {
        get async { nil }
    }

    func getURL() async -> URL? { nil }
    func getThumbnailURL() async -> URL? { nil }
    func getData() async throws -> Data? { nil }
    func getThumbnailData() async -> Data? { nil }
}
