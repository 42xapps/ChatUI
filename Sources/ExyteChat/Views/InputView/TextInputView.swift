//
//  Created by Alex.M on 14.06.2022.
//

import SwiftUI
import UIKit

struct TextInputView: View {

    @Environment(\.chatTheme) private var theme

    @EnvironmentObject private var globalFocusState: GlobalFocusState

    @Binding var text: String
    var inputFieldId: UUID
    var style: InputViewStyle
    var availableInputs: [AvailableInputType]
    var localization: ChatLocalization
    /// Whether the composer is showing its expanded card, the only layout with room for more than
    /// one line.
    var isExpanded: Bool = false

    var body: some View {
        TextField(
            "", text: $text,
            prompt: Text(
                style == .message ? localization.inputPlaceholder : localization.signatureText
            )
            .foregroundColor(
                style == .message
                    ? theme.colors.inputPlaceholderText : theme.colors.inputSignaturePlaceholderText
            ), axis: .vertical
        )
        .customFocus($globalFocusState.focus, equals: .uuid(inputFieldId))
        .font(Self.font)
        .foregroundColor(
            style == .message ? theme.colors.inputText : theme.colors.inputSignatureText
        )
        .tint(style == .message ? theme.colors.inputText : theme.colors.inputSignatureText)
        .lineLimit(style == .message && !isExpanded ? 1...1 : 1...Self.maximumLines)
        .padding(.vertical, style == .message ? Self.messageVerticalPadding : 12)
        .padding(.horizontal, leadingPadding)
        .simultaneousGesture(
            TapGesture().onEnded {
                globalFocusState.focus = .uuid(inputFieldId)
            }
        )
        .accessibilityLabel(
            style == .message ? localization.inputPlaceholder : localization.signatureText
        )
        .accessibilityIdentifier(
            style == .message ? "chat-message-input" : "chat-signature-input"
        )
    }

    /// `.message` style's horizontal position is otherwise owned by `ComposerLayout` in
    /// `InputView`, but `TextField` renders its text flush against its own bounds while
    /// `attachButton`'s icon sits inset by 4pt within its button frame — this small nudge keeps
    /// the typed text's left edge aligned with the `+` button below it in the expanded layout.
    private var leadingPadding: CGFloat {
        guard style != .message else { return Self.messageHorizontalPadding }
        return isMediaGiphyAvailable() ? 0 : 8
    }

    private func isMediaGiphyAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.media)
            || availableInputs.contains(AvailableInputType.giphy)
    }
}

/// The `.message` field's metrics, kept next to the measurements the composer sizes itself from —
/// those are only right for as long as they mirror what `body` applies to the field. All widths
/// here are row widths, i.e. what `ComposerLayout` hands this view, padding included.
extension TextInputView {

    private static let fontSize: CGFloat = 19
    private static let messageVerticalPadding: CGFloat = 6
    private static let messageHorizontalPadding: CGFloat = 6

    static let maximumLines = 5

    static let font: Font = .system(size: fontSize)

    /// The `UIFont` twin of `font`, so measurements wrap the way the field renders.
    private static var measuringFont: UIFont { .systemFont(ofSize: fontSize) }

    /// Height a `.message` field needs in a row `rowWidth` points wide.
    static func messageRowHeight(for text: String, rowWidth: CGFloat) -> CGFloat {
        CGFloat(lineCount(of: text, rowWidth: rowWidth)) * measuringFont.lineHeight
            + messageVerticalPadding * 2
    }

    /// Whether `text` outgrows a single line in a row `rowWidth` points wide.
    static func wrapsToMultipleLines(_ text: String, rowWidth: CGFloat) -> Bool {
        lineCount(of: text, rowWidth: rowWidth) > 1
    }

    private static func lineCount(of text: String, rowWidth: CGFloat) -> Int {
        let textWidth = rowWidth - messageHorizontalPadding * 2
        guard textWidth > 0, !text.isEmpty else { return 1 }

        let font = measuringFont
        let height = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            .height
        // Rounded, not ceiled: a whole number of lines measures a fraction of a point over.
        return min(max(1, Int((height / font.lineHeight).rounded())), maximumLines)
    }
}
