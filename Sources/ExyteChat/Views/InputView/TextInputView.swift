//
//  Created by Alex.M on 14.06.2022.
//

import SwiftUI

struct TextInputView: View {

    @Environment(\.chatTheme) private var theme

    @EnvironmentObject private var globalFocusState: GlobalFocusState

    @Binding var text: String
    var inputFieldId: UUID
    var style: InputViewStyle
    var availableInputs: [AvailableInputType]
    var localization: ChatLocalization

    private var isFocused: Bool {
        globalFocusState.focus == .uuid(inputFieldId)
    }

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
        .font(.system(size: 19))
        .foregroundColor(
            style == .message ? theme.colors.inputText : theme.colors.inputSignatureText
        )
        .lineLimit(style == .message && !isFocused ? 1...1 : 1...5)
        .padding(.vertical, style == .message && isFocused ? 2 : 12)
        .padding(.horizontal, leadingPadding)
        .simultaneousGesture(
            TapGesture().onEnded {
                globalFocusState.focus = .uuid(inputFieldId)
            }
        )
    }

    /// `.message` style's horizontal position is otherwise owned by `ComposerLayout` in
    /// `InputView`, but `TextField` renders its text flush against its own bounds while
    /// `attachButton`'s icon sits inset by 4pt within its button frame — this small nudge keeps
    /// the typed text's left edge aligned with the `+` button below it in the expanded layout.
    private var leadingPadding: CGFloat {
        guard style != .message else { return 6 }
        return isMediaGiphyAvailable() ? 0 : 8
    }

    private func isMediaGiphyAvailable() -> Bool {
        return availableInputs.contains(AvailableInputType.media)
            || availableInputs.contains(AvailableInputType.giphy)
    }
}
