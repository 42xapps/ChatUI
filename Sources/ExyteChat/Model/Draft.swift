//
//  Created by Alex.M on 17.06.2022.
//

import Foundation
import GiphyUISDK
import ExyteMediaPicker

/// Tells the built-in composer whether it may clear editable text and staged local media after a
/// submission attempt. GIPHY selections are immediate-send actions and never remain hidden in a
/// rejected draft.
public enum DraftSubmissionDisposition: Equatable, Sendable {
    case accepted
    case keepDraft
}

public struct DraftMessage: Sendable {
    public var id: String?
    public let text: String
    public let medias: [Media]
    public let giphyMedia: GPHMedia?
    public let recording: Recording?
    public let replyMessage: ReplyMessage?
    public let createdAt: Date
    
    public init(id: String? = nil,
                text: String,
                medias: [Media],
                giphyMedia: GPHMedia?,
                recording: Recording?,
                replyMessage: ReplyMessage?,
                createdAt: Date) {
        self.id = id
        self.text = text
        self.medias = medias
        self.giphyMedia = giphyMedia
        self.recording = recording
        self.replyMessage = replyMessage
        self.createdAt = createdAt
    }
}
