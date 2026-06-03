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
        let themeColors: ChatTheme.Colors = {
            var colors = ChatTheme.Colors()
            // --- General Colors ---
            colors.mainBG = Color.white
            colors.mainTint = Color(hex: "#1E1E1E")
            colors.mainText = Color.white
            colors.mainCaptionText = Color.gray

            // --- Outgoing Messages (My) ---
            colors.messageMyBG = Color(hex: "#F5F5F5")
            colors.messageMyText = Color.black
            colors.messageMyTimeText = Color.black.opacity(0.65)
            colors.messageReadStatus = Color.green

            // --- Incoming Messages (Friend) ---
            colors.messageFriendBG = Color.clear
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
        }()

        ChatExampleView()
            .chatTheme(colors: themeColors)
            .ignoresSafeArea(edges: .top)
        //        NavigationView {
        //            List {
        //                Section {
        //                    NavigationLink("Active chat example") {
        ////                        if !theme.isAccent, #available(iOS 18.0, *) {
        //                            ActiveChatExampleView()
        //                                .chatTheme(themeColor: color)
        ////                        } else {
        ////                            ActiveChatExampleView()
        ////                                .chatTheme(
        ////                                    accentColor: color,
        ////                                    images: theme.images
        ////                                )
        ////                        }
        //                    }
        //
        //                    NavigationLink("Simple chat example") {
        //                        if !theme.isAccent, #available(iOS 18.0, *) {
        //                            ChatExampleView()
        //                                .chatTheme(themeColor: color)
        //                        } else {
        //                            ChatExampleView()
        //                                .chatTheme(
        //                                    accentColor: color,
        //                                    images: theme.images
        //                                )
        //                        }
        //                    }
        //
        //                    NavigationLink("Simple comments example") {
        //                        CommentsExampleView()
        //                            .chatTheme(.init(colors: .init(
        //                                inputSignatureBG: .white.opacity(0.5),
        //                                inputSignatureText: .black,
        //                                inputSignaturePlaceholderText: .black.opacity(0.7)
        //                            )))
        //                            .mediaPickerTheme(
        //                                main: .init(
        //                                    pickerText: .white,
        //                                    pickerBackground: Color(.examplePickerBg),
        //                                    fullscreenPhotoBackground: Color(.examplePickerBg)
        //                                ),
        //                                selection: .init(
        //                                    accent: Color(.exampleBlue)
        //                                )
        //                            )
        //                    }
        //                } header: {
        //                    Text("Basic examples")
        //                }
        //            }
        //            .navigationTitle("Chat examples")
        //            .navigationBarTitleDisplayMode(.inline)
        //            .toolbar {
        //                ToolbarItem(placement: .navigationBarTrailing) {
        //                    HStack {
        //                        Button(theme.title) {
        //                            theme = theme.next()
        //                        }
        //                        ColorPicker("", selection: $color)
        //                    }
        //                }
        //            }
        //        }
        //        .navigationViewStyle(.stack)
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
