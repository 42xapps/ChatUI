//
//  AvatarCircle.swift
//  ChatConvexExample
//
//  Small shared avatar view: the signed-in user's photo when there is one,
//  otherwise their initials. Used by the chat-history sidebar's profile row
//  and the profile sheet.
//

import SwiftUI

struct AvatarCircle: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle()
            .fill(Color.exampleBlue.opacity(0.15))
            .overlay {
                Text(initialsText)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Color.exampleBlue)
            }
    }

    private var initialsText: String {
        let letters = name
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
