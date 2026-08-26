//
//  ChatAppearance.swift
//  ChatConvexExample
//

import SwiftUI
import ExyteChat

/// Input configuration for the chat, kept in one place so it matches
/// `ChatExample/ContentView.swift` rather than drifting from it.
///
/// Colors are deliberately absent: `ChatTheme`'s defaults come from `ChatTheme.Palette`,
/// which already carries a light and a dark value for every token.
enum ChatAppearance {

    /// Matches `ChatExampleView`: 16 kHz mono, which is what a speech pipeline
    /// wants and a fraction of the bytes of the default.
    static let recorderSettings = RecorderSettings(
        sampleRate: 16000,
        numberOfChannels: 1,
        linearPCMBitDepth: 16
    )

    static let messageFont = UIFont.systemFont(ofSize: 17, weight: .regular)
}
