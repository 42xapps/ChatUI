//
//  ChatTheme+Palette.swift
//  Chat
//

import SwiftUI

extension ChatTheme {

    /// The tokens every default ``ChatTheme/Colors`` is built from.
    ///
    /// Each token carries both appearances, so a chat that does not customise its theme
    /// follows the system between light and dark without the host app doing anything. Tokens
    /// are shared between the theme properties that are meant to stay visually locked
    /// together — `mainTint`, `inputIcon` and `sendButtonBackground` all resolve to ``ink``,
    /// for instance — so restyling stays a one-line change.
    public enum Palette {

        // MARK: Neutrals

        /// Behind the message list and the composer.
        public static let background = Color(lightHex: "#FFFFFF", darkHex: "#151515")

        /// Primary text, and the tint the composer's hairline border and chips are derived from.
        public static let label = Color(lightHex: "#000000", darkHex: "#FFFFFF")

        /// Timestamps, captions and other de-emphasised text.
        public static let secondaryLabel = Color(lightHex: "#8E8E93", darkHex: "#98989F")

        /// Text the user has not typed yet.
        public static let placeholderLabel = Color(lightHex: "#8E8E93", darkHex: "#8A8A8E")

        /// High-contrast chrome: the accent tint, composer icons and the add-attachment button.
        /// Near-black on light, near-white on dark, so it always reads against ``background``.
        public static let ink = Color(lightHex: "#1E1E1E", darkHex: "#F5F5F5")

        /// Fill of text fields and media placeholders.
        public static let field = Color(lightHex: "#F5F5F5", darkHex: "#1F1F1F")

        // MARK: Bubbles

        /// The outgoing bubble keeps its blue in both appearances, which is why its text and
        /// timestamp are white in both.
        public static let outgoingBubble = Color(hex: "#027DFC")

        /// Light grey on light, dark grey on dark, so ``label`` stays legible on top of it.
        public static let incomingBubble = Color(lightHex: "#EAEAEA", darkHex: "#262626")

        /// Barely-there fill for system messages, tinted by whatever is behind it.
        public static let systemBubble = Color(
            light: Color(hex: "#8E8E93").opacity(0.1),
            dark: Color.white.opacity(0.1)
        )

        // MARK: Overlays

        /// The message menu dims whatever is behind it, so it stays dark in both appearances.
        public static let menuBackground = Color.black.opacity(0.8)

        /// Signature fields sit on top of picked media rather than on ``background``.
        public static let signatureField = Color(
            light: Color.white.opacity(0.5),
            dark: Color.black.opacity(0.5)
        )

        // MARK: Status

        public static let error = Color(lightHex: "#FF3B30", darkHex: "#FF453A")

        public static let success = Color(lightHex: "#34C759", darkHex: "#30D158")
    }
}
