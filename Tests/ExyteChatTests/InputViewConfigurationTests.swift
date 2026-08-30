import XCTest
@preconcurrency import ExyteMediaPicker
@preconcurrency import GiphyUISDK
@testable import ExyteChat

@MainActor
final class InputViewConfigurationTests: XCTestCase {
    func testBuiltInComposerDefaultsKeepAllExistingAttachmentSourcesEnabled() {
        let parameters = InputViewCustomizationParameters()

        XCTAssertEqual(
            parameters.availableAttachmentInputs,
            AvailableAttachmentType.allCases
        )
        XCTAssertTrue(parameters.areActionsEnabled)
        XCTAssertTrue(parameters.allowsMixedMediaAndGiphy)
    }

    func testDisabledComposerActionsCannotOpenAttachmentPickers() {
        let viewModel = InputViewModel()
        var didSubmit = false
        viewModel.didSendMessage = { _ in
            didSubmit = true
            return .accepted
        }
        viewModel.showPicker = true
        viewModel.showDocumentPicker = true
        viewModel.showGiphyPicker = true
        viewModel.configureInputActions(
            enabled: false,
            maximumMediaCount: nil,
            allowsMixedMediaAndGiphy: true
        )

        viewModel.inputViewAction()(.photo)
        viewModel.inputViewAction()(.camera)
        viewModel.inputViewAction()(.document)
        viewModel.inputViewAction()(.giphy)
        viewModel.inputViewAction()(.send)
        viewModel.text = "Drafts stay editable"

        XCTAssertFalse(viewModel.showPicker)
        XCTAssertFalse(viewModel.showDocumentPicker)
        XCTAssertFalse(viewModel.showGiphyPicker)
        XCTAssertFalse(didSubmit)
        XCTAssertEqual(viewModel.text, "Drafts stay editable")
    }

    func testAttachmentLimitBoundsEverySelectionPathAgainstExistingMedia() {
        let limit = AttachmentSelectionLimit(maximumCount: 4)

        XCTAssertEqual(limit.remainingCount(after: 0), 4)
        XCTAssertEqual(limit.remainingCount(after: 3), 1)
        XCTAssertEqual(limit.remainingCount(after: 8), 0)
        XCTAssertEqual(limit.acceptedPrefix(from: [1, 2, 3], existingCount: 2), [1, 2])
        XCTAssertFalse(limit.canAppend(after: 4))
    }

    func testNilAttachmentLimitRemainsUnlimited() {
        let limit = AttachmentSelectionLimit(maximumCount: nil)

        XCTAssertNil(limit.remainingCount(after: 50))
        XCTAssertEqual(limit.acceptedPrefix(from: [1, 2, 3], existingCount: 50), [1, 2, 3])
        XCTAssertTrue(limit.canAppend(after: 50))
    }

    func testPickerSessionUsesRemainingCapacityWithoutMutatingHostParameters() {
        let viewModel = InputViewModel()
        viewModel.configureInputActions(
            enabled: true,
            maximumMediaCount: 4,
            allowsMixedMediaAndGiphy: false
        )
        viewModel.attachments.medias = makeImageMedia(count: 3)
        let host = SelectionParameters(
            mediaType: .photo,
            selectionStyle: .count,
            selectionLimit: 4,
            showFullscreenPreview: false
        )

        let session = AttachmentsEditor.makeSessionSelectionParameters(
            from: host,
            remainingLimit: viewModel.remainingMediaSelectionLimit
        )

        XCTAssertFalse(host === session)
        XCTAssertEqual(host.selectionLimit, 4)
        XCTAssertEqual(session.selectionLimit, 1)
        XCTAssertFalse(session.showFullscreenPreview)
        if case .photo = session.mediaType {} else {
            XCTFail("Expected photo-only session")
        }
        if case .count = session.selectionStyle {} else {
            XCTFail("Expected count selection style")
        }
    }

    func testPickerDoesNotOpenWhenComposerHasNoRemainingMediaCapacity() {
        let viewModel = InputViewModel()
        viewModel.configureInputActions(
            enabled: true,
            maximumMediaCount: 1,
            allowsMixedMediaAndGiphy: true
        )
        viewModel.attachments.medias = makeImageMedia(count: 1)

        viewModel.inputViewAction()(.photo)
        XCTAssertFalse(viewModel.showPicker)

        viewModel.inputViewAction()(.camera)
        XCTAssertFalse(viewModel.showPicker)
    }

    func testExclusiveMediaPolicyBlocksImageAndGiphyCombinations() {
        let viewModel = InputViewModel()
        viewModel.configureInputActions(
            enabled: true,
            maximumMediaCount: 4,
            allowsMixedMediaAndGiphy: false
        )
        viewModel.attachments.medias = makeImageMedia(count: 1)

        viewModel.inputViewAction()(.giphy)
        XCTAssertFalse(viewModel.showGiphyPicker)
        XCTAssertFalse(viewModel.canSelectGiphy)

        viewModel.attachments.medias = []
        viewModel.attachments.giphyMedia = makeGiphyMedia()
        viewModel.inputViewAction()(.photo)
        viewModel.inputViewAction()(.camera)
        XCTAssertFalse(viewModel.showPicker)
        XCTAssertFalse(viewModel.canSelectMedia)
    }

    func testSendRechecksActionLockBeforeSubmission() async {
        let viewModel = InputViewModel()
        var submissionCount = 0
        viewModel.text = "Do not send after locking"
        viewModel.didSendMessage = { _ in
            submissionCount += 1
            return .accepted
        }

        viewModel.send()
        viewModel.configureInputActions(
            enabled: false,
            maximumMediaCount: nil,
            allowsMixedMediaAndGiphy: true
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(submissionCount, 0)
        XCTAssertEqual(viewModel.text, "Do not send after locking")
    }

    func testConcurrentSendTapsSubmitOnlyOnce() async {
        let viewModel = InputViewModel()
        let submitted = expectation(description: "Draft submitted")
        var submissionCount = 0
        viewModel.text = "One message"
        viewModel.didSendMessage = { _ in
            submissionCount += 1
            submitted.fulfill()
            return .accepted
        }

        viewModel.send()
        viewModel.send()
        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(submissionCount, 1)
    }

    func testKeepDraftDispositionPreservesTextAndMedia() async {
        let viewModel = InputViewModel()
        let submitted = expectation(description: "Draft submitted")
        viewModel.text = "What is in this photo?"
        viewModel.attachments.medias = [Media(source: StubImageMediaSource())]
        viewModel.didSendMessage = { _ in
            submitted.fulfill()
            return .keepDraft
        }

        viewModel.send()
        await fulfillment(of: [submitted], timeout: 1)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.text, "What is in this photo?")
        XCTAssertEqual(viewModel.attachments.medias.count, 1)
    }

    func testAcceptedDispositionClearsDraftExactlyOnce() async {
        let viewModel = InputViewModel()
        let submitted = expectation(description: "Draft submitted")
        viewModel.text = "Hello"
        viewModel.didSendMessage = { _ in
            submitted.fulfill()
            return .accepted
        }

        viewModel.send()
        await fulfillment(of: [submitted], timeout: 1)
        await waitUntil { viewModel.text.isEmpty }

        XCTAssertEqual(viewModel.text, "")
        XCTAssertTrue(viewModel.attachments.medias.isEmpty)
    }

    func testAcceptedPromptAndGiphySubmitsTogetherAndClearsComposer() async {
        let viewModel = InputViewModel()
        let submitted = expectation(description: "GIPHY draft submitted")
        var submittedDraft: DraftMessage?
        viewModel.text = "This is exactly my mood"
        viewModel.didSendMessage = { draft in
            submittedDraft = draft
            submitted.fulfill()
            return .accepted
        }

        viewModel.submitGiphy(makeGiphyMedia())
        await fulfillment(of: [submitted], timeout: 1)
        await waitUntil { viewModel.text.isEmpty }

        XCTAssertEqual(submittedDraft?.text, "This is exactly my mood")
        XCTAssertEqual(submittedDraft?.giphyMedia?.id, "test-giphy-id")
        XCTAssertEqual(viewModel.text, "")
        XCTAssertNil(viewModel.attachments.giphyMedia)
    }

    func testRejectedPromptAndGiphyKeepsTextWithoutHiddenGiphyAttachment() async {
        let viewModel = InputViewModel()
        let submitted = expectation(description: "GIPHY draft rejected")
        var submittedDraft: DraftMessage?
        viewModel.text = "Keep this prompt"
        viewModel.didSendMessage = { draft in
            submittedDraft = draft
            submitted.fulfill()
            return .keepDraft
        }

        viewModel.submitGiphy(makeGiphyMedia())
        await fulfillment(of: [submitted], timeout: 1)
        await waitUntil { viewModel.attachments.giphyMedia == nil }

        XCTAssertEqual(submittedDraft?.giphyMedia?.id, "test-giphy-id")
        XCTAssertEqual(viewModel.text, "Keep this prompt")
        XCTAssertNil(viewModel.attachments.giphyMedia)
    }

    private func makeImageMedia(count: Int) -> [Media] {
        (0..<count).map { _ in Media(source: StubImageMediaSource()) }
    }

    private func makeGiphyMedia() -> GPHMedia {
        GPHMedia("test-giphy-id", type: .gif, url: "https://giphy.com/gifs/test-giphy-id")
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Condition was not satisfied before timeout", file: file, line: line)
    }
}

private struct StubImageMediaSource: MediaModelProtocol {
    let mediaType: MediaType? = .image
    var duration: CGFloat? { get async { nil } }

    func getURL() async -> URL? { nil }
    func getThumbnailURL() async -> URL? { nil }
    func getData() async throws -> Data? { nil }
    func getThumbnailData() async -> Data? { nil }
}
