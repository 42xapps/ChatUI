import SwiftUI
import Testing

@testable import ExyteChat

struct ChatStabilityTests {
    private let sender = User(id: "sender", name: "Sender", avatarURL: nil, isCurrentUser: true)

    @Test("Floating composer inset leaves keyboard ownership to the safe area")
    func floatingComposerInsetUsesOnlyStaticBreathingRoom() {
        #expect(
            FloatingComposerLayout.messageInset(
                existingInset: 0,
                gap: 8
            ) == 8
        )
        #expect(
            FloatingComposerLayout.messageInset(
                existingInset: 24,
                gap: 8
            ) == 24
        )
    }

    @Test("Keyboard overlap is scoped to the embedded chat container")
    func keyboardOverlapUsesOnlyIntersectingHeight() {
        #expect(
            KeyboardLayout.overlap(
                container: CGRect(x: 0, y: 44, width: 390, height: 800),
                keyboard: CGRect(x: 0, y: 600, width: 390, height: 300)
            ) == 244
        )
        #expect(
            KeyboardLayout.overlap(
                container: CGRect(x: 0, y: 44, width: 390, height: 500),
                keyboard: CGRect(x: 0, y: 600, width: 390, height: 300)
            ) == 0
        )
    }

    @Test("Message projection is rebuilt only when its input changes")
    @MainActor
    func messageProjectionCachesUnchangedInput() {
        let message = Message(id: "one", user: sender, text: "Hello")
        let cache = MessageProjectionCache(
            messages: [message],
            chatType: .conversation,
            replyMode: .quote
        )

        cache.update(
            with: MessageProjectionInput(
                messages: [message],
                chatType: .conversation,
                replyMode: .quote
            )
        )
        #expect(cache.rebuildCount == 1)

        cache.update(
            with: MessageProjectionInput(
                messages: [message, Message(id: "two", user: sender, text: "Again")],
                chatType: .conversation,
                replyMode: .quote
            )
        )
        #expect(cache.rebuildCount == 2)
        #expect(cache.ids == ["one", "two"])
    }

    @Test("Thumbnail requests downsample and use size-specific cache keys")
    func thumbnailConfigurationDoesNotCacheOriginalImage() throws {
        let configuration = CachedImageLoadConfiguration(
            url: try #require(URL(string: "https://example.com/image.jpg")),
            providedCacheKey: "message-image",
            targetSize: CGSize(width: 120, height: 180),
            scale: 3
        )

        #expect(configuration.isThumbnail)
        #expect(configuration.cacheKey == "message-image#thumbnail-360x540")
        #expect(!configuration.options.contains { option in
            if case .cacheOriginalImage = option { return true }
            return false
        })
        #expect(configuration.options.contains { option in
            if case .processor = option { return true }
            return false
        })
    }
}
