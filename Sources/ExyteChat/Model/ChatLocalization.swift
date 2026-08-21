//
//  ChatLocalization.swift
//  Chat
//
//  Created by Aman Kumar on 18/12/24.
//

import Foundation

public struct ChatLocalization: Hashable {
    public var inputPlaceholder: String
    public var signatureText: String
    public var cancelButtonText: String
    public var recentToggleText: String
    public var waitingForNetwork: String
    public var recordingText: String
    public var replyToText: String
    public var photoLibraryText: String
    public var cameraText: String
    public var filesText: String
    public var giphyText: String

    public init(inputPlaceholder: String, signatureText: String, cancelButtonText: String, recentToggleText: String, waitingForNetwork: String, recordingText: String, replyToText: String, photoLibraryText: String = String(localized: "Photo Library"), cameraText: String = String(localized: "Camera"), filesText: String = String(localized: "Files"), giphyText: String = String(localized: "Giphy")) {
        self.inputPlaceholder = inputPlaceholder
        self.signatureText = signatureText
        self.cancelButtonText = cancelButtonText
        self.recentToggleText = recentToggleText
        self.waitingForNetwork = waitingForNetwork
        self.recordingText = recordingText
        self.replyToText = replyToText
        self.photoLibraryText = photoLibraryText
        self.cameraText = cameraText
        self.filesText = filesText
        self.giphyText = giphyText
    }

   public static var defaultLocalization: ChatLocalization {
        ChatLocalization(
            inputPlaceholder: String(localized: "Type a message..."),
            signatureText: String(localized: "Add signature..."),
            cancelButtonText: String(localized: "Cancel"),
            recentToggleText: String(localized: "Recents"),
            waitingForNetwork: String(localized: "Waiting for network"),
            recordingText: String(localized: "Recording..."),
            replyToText: String(localized: "Reply to"),
            photoLibraryText: String(localized: "Photo Library"),
            cameraText: String(localized: "Camera"),
            filesText: String(localized: "Files"),
            giphyText: String(localized: "Giphy")
        )
    }
}
