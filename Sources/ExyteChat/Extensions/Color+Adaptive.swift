//
//  Color+Adaptive.swift
//  Chat
//

import SwiftUI
import UIKit

extension Color {

    /// A color that resolves to `light` or `dark` according to the appearance it is drawn in.
    ///
    /// Backed by a dynamic `UIColor` rather than by reading `\.colorScheme`, so it keeps
    /// adapting after the `Color` → `UIColor` round trip that `UIList` needs in order to tint
    /// the table view, its cells and its section headers.
    public init(light: Color, dark: Color) {
        self.init(
            uiColor: UIColor { traits in
                UIColor(traits.userInterfaceStyle == .dark ? dark : light)
            })
    }

    /// Hex convenience for ``init(light:dark:)``. Accepts the same `RGB` / `RRGGBB` /
    /// `AARRGGBB` forms as ``init(hex:)``.
    public init(lightHex: String, darkHex: String) {
        self.init(light: Color(hex: lightHex), dark: Color(hex: darkHex))
    }
}
