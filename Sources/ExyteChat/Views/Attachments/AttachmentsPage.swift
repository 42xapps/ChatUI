//
//  Created by Alex.M on 20.06.2022.
//

import SwiftUI

struct AttachmentsPage: View {

    @EnvironmentObject var mediaPagesViewModel: FullscreenMediaPagesViewModel
    @Environment(\.chatTheme) private var theme

    let attachment: Attachment

    var body: some View {
        if attachment.type == .image {
            // ZoomableContainer {
            CachedAsyncImage(
                url: attachment.full,
                cacheKey: attachment.fullCacheKey
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                default:
                    ActivityIndicator()
                }
            }
            .background(Color.clear)
            // }
        } else if attachment.type == .video {
            VideoView(viewModel: VideoViewModel(attachment: attachment))
        } else {
            Rectangle()
                .foregroundColor(Color.gray)
                .frame(minWidth: 100, minHeight: 100)
                .frame(maxHeight: 200)
                .overlay {
                    Text("Unknown", bundle: .module)
                }
        }
    }
}
