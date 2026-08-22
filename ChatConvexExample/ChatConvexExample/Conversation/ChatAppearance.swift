//
//  ChatAppearance.swift
//  ChatConvexExample
//

import SwiftUI
import ExyteChat

/// Visual and input configuration for the chat, kept in one place so it matches
/// `ChatExample/ContentView.swift` rather than drifting from it.
enum ChatAppearance {

    /// Mirrors the palette in `ChatExample/ContentView.swift`.
    static var colors: ChatTheme.Colors {
        var colors = ChatTheme.Colors()

        // --- General Colors ---
        colors.mainBG = Color.white
        colors.mainTint = Color(hex: "#1E1E1E")
        colors.mainText = Color.white
        colors.mainCaptionText = Color.gray

        // --- Outgoing Messages (My) ---
        colors.messageMyBG = Color(hex: "#027DFC")
        colors.messageMyText = Color.white
        colors.messageMyTimeText = Color.white.opacity(0.65)
        colors.messageReadStatus = Color.green

        // --- Incoming Messages (Friend) ---
        colors.messageFriendBG = Color(hex: "#EAEAEA")
        colors.messageFriendText = Color.black
        colors.messageFriendTimeText = Color.gray

        // --- System Messages ---
        colors.messageSystemBG = Color.gray.opacity(0.1)
        colors.messageSystemText = Color.gray
        colors.messageSystemTimeText = Color.gray

        // --- Chat Input ---
        colors.inputBG = Color(hex: "#F5F5F5")
        colors.inputText = Color(hex: "#1E1E1E")
        colors.inputPlaceholderText = Color.gray
        colors.inputIcon = Color(hex: "#1E1E1E")

        // --- Signature Fields (Comments Mode) ---
        colors.inputSignatureBG = Color.white.opacity(0.5)
        colors.inputSignatureText = Color.black
        colors.inputSignaturePlaceholderText = Color.black.opacity(0.7)

        // --- Context Menu ---
        colors.menuBG = Color.black.opacity(0.8)
        colors.menuText = Color.white
        colors.menuTextDelete = Color.red

        // --- Status Indicators & Misc ---
        colors.statusError = Color.red
        colors.statusGray = Color.gray
        colors.sendButtonBackground = Color(hex: "#1E1E1E")
        colors.recordDot = Color.red

        return colors
    }

    /// Matches `ChatExampleView`: 16 kHz mono, which is what a speech pipeline
    /// wants and a fraction of the bytes of the default.
    static let recorderSettings = RecorderSettings(
        sampleRate: 16000,
        numberOfChannels: 1,
        linearPCMBitDepth: 16
    )

    static let messageFont = UIFont.systemFont(ofSize: 17, weight: .regular)
}
