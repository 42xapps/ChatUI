//
//  ChatConvexExampleApp.swift
//  ChatConvexExample
//

import SwiftUI
import ClerkKit

/// Exists so the media picker and camera can pin the interface to portrait while
/// they're presented, then restore whatever the device was doing.
class AppDelegate: NSObject, UIApplicationDelegate {

    static var orientationLock = UIInterfaceOrientationMask.all

    static func lockOrientationToPortrait() {
        AppDelegate.orientationLock = .portrait
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
    }

    static func unlockOrientation() {
        AppDelegate.orientationLock = .all
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let currentOrientation = UIDevice.current.orientation
            let newOrientation: UIInterfaceOrientationMask

            switch currentOrientation {
            case .portrait: newOrientation = .portrait
            case .portraitUpsideDown: newOrientation = .portraitUpsideDown
            case .landscapeLeft: newOrientation = .landscapeLeft
            case .landscapeRight: newOrientation = .landscapeRight
            default: newOrientation = .all
            }

            scene.requestGeometryUpdate(.iOS(interfaceOrientations: newOrientation))
        }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

@main
struct ChatConvexExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
        // Order matters: `ClerkConvexAuthProvider` reads `Clerk.shared` the
        // moment it's bound to the client, so the Convex connection is opened
        // here rather than lazily from a view body.
        _ = ConvexService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(Clerk.shared)
        }
    }
}
