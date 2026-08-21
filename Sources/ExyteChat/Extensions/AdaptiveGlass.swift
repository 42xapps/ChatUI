//
//  AdaptiveGlass.swift
//  Chat
//

import SwiftUI

/// Applies real Liquid Glass on iOS 26+, falling back to a Material approximation on earlier versions,
/// so call sites stay a single line regardless of deployment target.
private struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
            }
        }
    }
}

extension View {
    func adaptiveGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(AdaptiveGlassModifier(shape: shape, tint: tint))
    }
}
