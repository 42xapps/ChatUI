//
//  Utils.swift
//  ChatConvexExample
//

import SwiftUI

extension View {
    func font(_ size: CGFloat, _ color: Color = .black, _ weight: Font.Weight = .regular) -> some View {
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
