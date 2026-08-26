//
//  Utils.swift
//  ChatConvexExample
//

import SwiftUI

extension View {
    /// Defaults to `.primary` rather than `.black` so app chrome follows the system
    /// appearance, the same way the chat's own `ChatTheme.Palette` does.
    func font(_ size: CGFloat, _ color: Color = .primary, _ weight: Font.Weight = .regular) -> some View {
        self
            .fontWeight(weight)
            .font(.system(size: size))
            .foregroundColor(color)
    }
}

extension String {
    func toURL() -> URL? {
        URL(string: self)
    }
}
