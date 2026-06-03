//
//  Created by Alex.M on 22.06.2022.
//

import Foundation
import SwiftUI

struct FullscreenMediaPages: View {

    @Environment(\.chatTheme) private var theme

    @StateObject var viewModel: FullscreenMediaPagesViewModel

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $viewModel.index) {
                ForEach(viewModel.attachments.enumerated().map({ $0 }), id: \.offset) {
                    (index, attachment) in
                    AttachmentsPage(attachment: attachment)
                        .tag(index)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environmentObject(viewModel)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onTapGesture {
                withAnimation {
                    viewModel.showMinis.toggle()
                }
            }

            ScrollViewReader { proxy in
                if viewModel.showMinis {
                    ScrollView(.horizontal) {
                        HStack(spacing: 2) {
                            ForEach(
                                viewModel.attachments
                                    .filter {
                                        $0.fullUploadStatus == nil
                                            || $0.fullUploadStatus == .complete
                                    }
                                    .enumerated().map({ $0 }), id: \.offset
                            ) { (index, attachment) in
                                AttachmentCell(
                                    attachment: attachment,
                                    size: CGSize(width: 100, height: 100)
                                ) { _, _ in
                                    withAnimation {
                                        viewModel.index = index
                                    }
                                }
                                .cornerRadius(4)
                                .clipped()
                                .id(index)
                                .overlay {
                                    if viewModel.index == index {
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                theme.colors.sendButtonBackground, lineWidth: 2)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    }
                    // .padding(.top, 16)
                    .background(Color.clear)
                    .padding(.bottom, 8)
                    .onAppear {
                        proxy.scrollTo(viewModel.index)
                    }
                    .onChange(of: viewModel.index) { _, newValue in
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.showMinis, viewModel.attachments[viewModel.index].type == .video {
                HStack(spacing: 20) {
                    (viewModel.videoPlaying
                        ? theme.images.fullscreenMedia.pause : theme.images.fullscreenMedia.play)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleVideoPlaying()
                        }

                    (viewModel.videoMuted
                        ? theme.images.fullscreenMedia.unmute : theme.images.fullscreenMedia.mute)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleVideoMuted()
                        }
                }
                .foregroundColor(.white)
                .padding(.trailing, 10)

            }
        }
    }
}

