//
//  Created by Aman Kumar on 26/08/25.
//

import SwiftUI
import Kingfisher

/// A view that asynchronously loads and displays an image using Kingfisher.
///
///     CachedAsyncImage(url: URL(string: "https://example.com/icon.png"))
///         .frame(width: 200, height: 200)
///
/// You can specify a custom cache key:
///
///     CachedAsyncImage(url: URL(string: "https://example.com/icon.png"), cacheKey: "custom-key")
///
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct CachedAsyncImage<Content>: View where Content: View {

    @State private var phase: AsyncImagePhase

    private let url: URL?
    private let cacheKey: String?
    private let targetSize: CGSize?
    private let scale: CGFloat
    private let transaction: Transaction
    private let content: (AsyncImagePhase) -> Content

    public var body: some View {
        content(phase)
            .task(id: loadConfiguration.taskIdentifier, load)
    }

    /// Loads and displays an image from the specified URL.
    public init(
        url: URL?,
        cacheKey: String? = nil,
        scale: CGFloat = 1,
        targetSize: CGSize? = nil
    ) where Content == Image {
        self.init(url: url, cacheKey: cacheKey, scale: scale, targetSize: targetSize) { phase in
    #if os(macOS)
            phase.image ?? Image(nsImage: .init())
    #else
            phase.image ?? Image(uiImage: .init())
    #endif
        }
    }


    /// Loads and displays a modifiable image with placeholder.
    public init<I, P>(
        url: URL?,
        cacheKey: String? = nil,
        scale: CGFloat = 1,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P>, I: View, P: View {
        self.init(url: url, cacheKey: cacheKey, scale: scale, targetSize: targetSize) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }


    /// Loads and displays a modifiable image in phases.
    public init(
        url: URL?,
        cacheKey: String? = nil,
        scale: CGFloat = 1,
        targetSize: CGSize? = nil,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.cacheKey = cacheKey
        self.targetSize = targetSize
        self.scale = scale
        self.transaction = transaction
        self.content = content
        self._phase = State(wrappedValue: .empty)
    }

    @Sendable
    private func load() async {
        guard let url = url else {
            withAnimation(transaction.animation) { phase = .empty }
            return
        }

        let configuration = loadConfiguration
        let resource = KF.ImageResource(downloadURL: url, cacheKey: configuration.cacheKey)

        do {
            let image = try await withCheckedThrowingContinuation { continuation in
                KingfisherManager.shared.retrieveImage(
                    with: resource,
                    options: configuration.options
                ) { result in
                    switch result {
                    case .success(let value):
                        //print("[CachedAsyncImage] Loaded image from: \(value.cacheType)")
                        continuation.resume(returning: value.image)
                    case .failure(let error):
                        print("[CachedAsyncImage] Failed to load image: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }

            withAnimation(transaction.animation) {
                #if canImport(UIKit)
                phase = .success(Image(uiImage: image))
                #elseif canImport(AppKit)
                phase = .success(Image(nsImage: image))
                #else
                phase = .success(Image(uiImage: image)) // fallback for iOS-only targets
                #endif
            }
        } catch {
            withAnimation(transaction.animation) {
                phase = .failure(error)
            }
        }
    }
}

/// Image-loading details which can be tested independently of the SwiftUI view. Thumbnail
/// requests use a processed, size-specific cache entry and deliberately omit
/// `cacheOriginalImage`, preventing a feed of large images from retaining full-size originals.
struct CachedImageLoadConfiguration {
    let url: URL?
    let providedCacheKey: String?
    let targetSize: CGSize?
    let scale: CGFloat

    var isThumbnail: Bool {
        guard let targetSize else { return false }
        return targetSize.width > 0 && targetSize.height > 0
    }

    var cacheKey: String? {
        guard let baseKey = providedCacheKey ?? url?.absoluteString else { return nil }
        guard isThumbnail, let targetSize else { return baseKey }

        let width = Int((targetSize.width * scale).rounded(.up))
        let height = Int((targetSize.height * scale).rounded(.up))
        return "\(baseKey)#thumbnail-\(width)x\(height)"
    }

    var taskIdentifier: String {
        "\(url?.absoluteString ?? "nil")|\(cacheKey ?? "nil")|\(scale)"
    }

    var options: KingfisherOptionsInfo {
        var options: KingfisherOptionsInfo = [.scaleFactor(scale)]
        if isThumbnail, let targetSize {
            options.append(.processor(DownsamplingImageProcessor(size: targetSize)))
        } else {
            options.append(.cacheOriginalImage)
        }
        return options
    }
}

private extension CachedAsyncImage {
    var loadConfiguration: CachedImageLoadConfiguration {
        CachedImageLoadConfiguration(
            url: url,
            providedCacheKey: cacheKey,
            targetSize: targetSize,
            scale: scale
        )
    }
}
