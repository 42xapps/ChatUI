//
//  Created by Alex.M on 23.06.2022.
//

import ExyteChat
import ExyteMediaPicker
import SwiftUI

struct ContentView: View {

    @State private var theme: ExampleThemeState = .accent
    @State private var color = Color(.exampleBlue)

    var body: some View {
        // `ChatTheme.Colors()` is already built from `ChatTheme.Palette`, whose tokens carry
        // both a light and a dark value, so the chat follows the system appearance without
        // this app configuring anything.
        ChatExampleView()
            .ignoresSafeArea(edges: .top)
    }
}

/// An enum that lets us iterate through the different ChatTheme styles
enum ExampleThemeState: String {
    case accent
    case image

    @available(iOS 18, *)
    case themed

    var title: String {
        self.rawValue.capitalized
    }

    func next() -> ExampleThemeState {
        switch self {
        case .accent:
            if #available(iOS 18.0, *) {
                return .themed
            } else {
                return .image
            }
        case .themed:
            return .image
        case .image:
            return .accent
        }
    }

    var images: ChatTheme.Images {
        switch self {
        case .accent, .themed: return .init()
        case .image:
            return .init(
                background: ChatTheme.Images.Background(
                    portraitBackgroundLight: Image("chatBackgroundLight"),
                    portraitBackgroundDark: Image("chatBackgroundDark"),
                    landscapeBackgroundLight: Image("chatBackgroundLandscapeLight"),
                    landscapeBackgroundDark: Image("chatBackgroundLandscapeDark")
                )
            )
        }
    }

    var isAccent: Bool {
        if #available(iOS 18.0, *) {
            return self != .themed
        }
        return true
    }
}

#Preview {
    ContentView()
}
