//
//  AttachmentsEditor.swift
//  Chat
//
//  Created by Alex.M on 22.06.2022.
//

import SwiftUI
import ExyteMediaPicker
import ActivityIndicatorView

struct AttachmentsEditor: View {

    @Environment(\.chatTheme) var theme
    @Environment(\.mediaPickerTheme) var mediaPickerTheme
    @Environment(\.mediaPickerThemeIsOverridden) var mediaPickerThemeIsOverridden

    @ObservedObject var inputViewModel: InputViewModel

    var mediaPickerParameters: MediaPickerParameters
    var localization: ChatLocalization

    @State private var currentFullscreenMedia: Media?

    var showingAlbums: Bool {
        inputViewModel.mediaPickerMode == .albums
    }

    var body: some View {
        ZStack {
            mediaPicker

            if inputViewModel.showActivityIndicator {
                ActivityIndicator()
            }
        }
    }

    var mediaPicker: some View {
        GeometryReader { g in
            MediaPicker(isPresented: $inputViewModel.showPicker) { picked in
                inputViewModel.stagePickerSelection(
                    picked,
                    from: inputViewModel.mediaPickerMode.pickerSource
                )
            } albumSelectionBuilder: { _, albumSelectionView, _ in
                VStack {
                    albumSelectionHeaderView
                        .padding(.top, g.safeAreaInsets.top)
                    albumSelectionView
                    Spacer()
                }
                .background(mediaPickerTheme.main.pickerBackground.ignoresSafeArea())
            } cameraSelectionBuilder: { _, cancelClosure, cameraSelectionView in
                VStack {
                    cameraSelectionView
                        .overlay(alignment: .top) {
                            cameraSelectionHeaderView(cancelClosure: cancelClosure)
                                .padding(.top, 12)
                        }
                        .padding(.top, g.safeAreaInsets.top)
                    Spacer()
                }
                .background(mediaPickerTheme.main.pickerBackground.ignoresSafeArea())
            }
            .didPressCancelCamera {
                currentFullscreenMedia = nil
                inputViewModel.cancelPicker()
            }
            .fullscreenMedia($currentFullscreenMedia)
            .pickerMode($inputViewModel.mediaPickerMode)
            .setMediaPickerParameters(mediaPickerParameters)
            .padding(.top)
            .background(theme.colors.mainBG)
            .ignoresSafeArea(.all)
            .onChange(of: currentFullscreenMedia) {
                inputViewModel.stagePreviewedMedia(currentFullscreenMedia)
            }
            .onChange(of: inputViewModel.showPicker) { _, isPresented in
                // Once the picker is gone this is only a stale mirror of a finished session, and
                // leaving it behind would let the next session reopen with it.
                guard !isPresented else { return }
                currentFullscreenMedia = nil
            }
            .applyIf(!mediaPickerThemeIsOverridden) {
                $0.mediaPickerTheme(
                    main: .init(
                        pickerText: theme.colors.mainText,
                        pickerBackground: theme.colors.mainBG,
                        fullscreenPhotoBackground: theme.colors.mainBG
                    ),
                    selection: .init(
                        accent: theme.colors.sendButtonBackground
                    )
                )
            }
        }
    }

    /// Confirms the picker without sending, leaving the selection staged in the chat's composer.
    /// Only offered once something is staged, since otherwise it would just duplicate Cancel.
    @ViewBuilder
    var confirmButton: some View {
        if !inputViewModel.attachments.medias.isEmpty {
            Button {
                inputViewModel.showPicker = false
            } label: {
                Text(localization.addAttachmentsText)
                    .fontWeight(.semibold)
            }
        }
    }

    var albumSelectionHeaderView: some View {
        ZStack {
            HStack {
                Button {
                    currentFullscreenMedia = nil
                    inputViewModel.cancelPicker()
                } label: {
                    Text(localization.cancelButtonText)
                }

                Spacer()

                confirmButton
            }

            HStack {
                Text(localization.recentToggleText)
                Image(systemName: "chevron.down")
                    .rotationEffect(Angle(radians: showingAlbums ? .pi : 0))
            }
            .onTapGesture {
                withAnimation {
                    inputViewModel.mediaPickerMode = showingAlbums ? .photos : .albums
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundColor(mediaPickerTheme.main.pickerText)
        .padding(.horizontal)
        .padding(.bottom, 5)
    }

    private func cameraSelectionHeaderView(cancelClosure: @escaping ()->()) -> some View {
        HStack {
            Button(action: cancelClosure) {
                theme.images.mediaPicker.cross
                    .imageScale(.large)
            }
            .tint(mediaPickerTheme.main.pickerText)
            .padding(.trailing, 30)

            Spacer()

            // The camera used to rely on the removed input row to get out with its captures.
            confirmButton
                .foregroundColor(mediaPickerTheme.main.pickerText)
        }
        .padding(.horizontal)
    }
}

private extension MediaPickerMode {

    /// The picker switches into a camera mode before it reports a capture, so the mode is what
    /// attributes an incoming selection to the camera rather than the library. Deliberately
    /// exhaustive: a new mode upstream should fail to build rather than be filed as a library pick.
    var pickerSource: InputViewModel.PickerSource {
        switch self {
        case .camera, .cameraSelection:
            .camera
        case .photos, .albums, .album:
            .library
        }
    }
}
