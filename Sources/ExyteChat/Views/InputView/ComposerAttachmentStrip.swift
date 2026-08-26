//
//  ComposerAttachmentStrip.swift
//  Chat
//

import ExyteMediaPicker
import FanPicker
import SwiftUI

/// Horizontal preview of everything staged in the composer, whatever it was picked with. Photos
/// quick-attached from the fan are also the destination FanPicker's hero animation flies into.
struct ComposerAttachmentStrip: View {

    let medias: [Media]
    let previews: [UUID: UIImage]
    let configuration: FanPickerConfiguration
    let picker: RecentPhotoPickerContext?
    let onRemove: (UUID) -> Void
    let removeLabel: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: configuration.attachmentSpacing) {
                ForEach(medias) { media in
                    thumbnail(for: media)
                        .attachmentTransition(
                            id: media.id,
                            picker: picker,
                            configuration: configuration
                        )
                        .overlay(alignment: .topTrailing) {
                            if picker?.isTransitioningAttachment(id: media.id) != true {
                                removeButton(for: media.id)
                            }
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
        // The hero flight overshoots the strip's bounds on its way in.
        .scrollClipDisabled(true)
        .frame(height: configuration.attachmentSize)
    }

    @ViewBuilder
    private func thumbnail(for media: Media) -> some View {
        if let preview = previews[media.id] {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
        } else {
            MediaThumbnail(media: media)
        }
    }

    private func removeButton(for id: UUID) -> some View {
        Button {
            onRemove(id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(
                    width: configuration.closeBadgeSize,
                    height: configuration.closeBadgeSize
                )
                .background(.black.opacity(0.75), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel(removeLabel)
    }
}

/// Loads a thumbnail for media that arrived without one, i.e. anything picked through the full
/// screen picker rather than the fan.
private struct MediaThumbnail: View {

    @Environment(\.chatTheme) private var theme

    let media: Media

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                theme.colors.mainText.opacity(0.06)
            }
        }
        .task(id: media.id) {
            guard let data = await media.getThumbnailData() else { return }
            image = UIImage(data: data)
        }
    }
}

private extension View {

    /// FanPicker owns the destination's size, corner radius and matched geometry while a picker
    /// context exists; without one the strip has to size itself the same way.
    @ViewBuilder
    func attachmentTransition(
        id: UUID,
        picker: RecentPhotoPickerContext?,
        configuration: FanPickerConfiguration
    ) -> some View {
        if let picker {
            fanPickerAttachmentTransition(id: id, context: picker)
        } else {
            frame(
                width: configuration.attachmentSize,
                height: configuration.attachmentSize
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: configuration.attachmentCornerRadius,
                    style: .continuous
                )
            )
        }
    }
}
