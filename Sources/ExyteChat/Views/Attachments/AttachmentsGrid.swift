//
//  Created by Alex.M on 16.06.2022.
//

import SwiftUI

struct AttachmentsGrid: View {
    let onTap: (_ attachment: Attachment, _ isCancel: Bool) -> Void
    let isCurrentUser: Bool
    let maxImages: Int = 4 // TODO: Make injectable

    private let attachmentsToShow: [Attachment]
    private let onlyOne: Bool

    private let hidden: String?
    private let showMoreAttachmentId: String?

    init(attachments: [Attachment], isCurrentUser: Bool,
         onTap: @escaping (_ attachment: Attachment, _ isCancel: Bool) -> Void) {
        var toShow = attachments

        if toShow.count > maxImages {
            toShow = Array(attachments.prefix(maxImages))
            hidden = "+\(attachments.count - (maxImages - 1))"
            showMoreAttachmentId = toShow.last?.id
        } else {
            hidden = nil
            showMoreAttachmentId = nil
        }

        self.attachmentsToShow = toShow
        self.onlyOne = attachments.count == 1
        self.onTap = onTap
        self.isCurrentUser = isCurrentUser
    }

    var body: some View {
        if onlyOne, let attachment = attachmentsToShow.first {
            AttachmentCell(
                attachment: attachment,
                size: CGSize(width: 204, height: 200),
                showCancel: isCurrentUser,
                onTap: onTap
            )
            .clipped()
            .cornerRadius(0)
        } else if !attachmentsToShow.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachmentsToShow) { attachment in
                        AttachmentCell(
                            attachment: attachment,
                            size: CGSize(width: 120, height: 180),
                            showCancel: isCurrentUser,
                            onTap: onTap
                        )
                        .clipped()
                        .overlay {
                            if attachment.id == showMoreAttachmentId, let hidden = hidden {
                                ZStack {
                                    RadialGradient(
                                        colors: [
                                            .black.opacity(0.8),
                                            .black.opacity(0.6),
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 90
                                    )
                                    Text(hidden)
                                        .font(.body)
                                        .bold()
                                        .foregroundColor(.white)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .cornerRadius(12)
                    }
                }
            }
            .environment(\.layoutDirection, isCurrentUser ? .rightToLeft : .leftToRight)
        }
    }
}

#if DEBUG
struct AttachmentsGrid_Preview: PreviewProvider {
    private static let examples = [1, 2, 3, 4, 5, 10]

    static var previews: some View {
        Group {
            ForEach(examples, id: \.self) { count in
                ScrollView {
                    AttachmentsGrid(attachments: .random(count: count), isCurrentUser: true, onTap: { _,_ in } )
                        .padding()
                        .background(Color.white)
                }
            }
            .padding()
            .background(Color.secondary)
        }
    }
}

extension Array where Element == Attachment {
    static func random(count: Int) -> [Attachment] {
        return Swift.Array(repeating: 0, count: count)
            .map { _ in randomAttachment() }
    }

    private static func randomAttachment() -> Attachment {
        if Int.random(in: 0...3) == 0 {
            return Attachment.randomVideo()
        } else {
            return Attachment.randomImage()
        }
    }
}

extension Attachment {
    static func randomImage() -> Attachment {
        Attachment(id: UUID().uuidString, url: URL(string: "https://placeimg.com/640/480/sepia")!, type: .image)
    }
    // TODO get video, not image
    static func randomVideo() -> Attachment {
        Attachment(id: UUID().uuidString, url: URL(string: "https://placeimg.com/640/480/sepia")!, type: .video)
    }
}
#endif
