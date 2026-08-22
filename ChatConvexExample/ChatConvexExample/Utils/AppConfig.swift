//
//  AppConfig.swift
//  ChatConvexExample
//

import Foundation

/// Client configuration, read from `Info.plist` keys that `Config.xcconfig`
/// populates at build time.
///
/// Both values are public by design — the Clerk publishable key is meant for
/// clients, and the Convex deployment URL is a public endpoint. Authorization
/// happens on the server against the Clerk session token, so neither grants
/// access on its own. R2 credentials live only in the Convex deployment's
/// environment and never reach the app.
enum AppConfig {

    /// Full `https://` URL of the Convex deployment.
    static let convexDeploymentURL = "https://" + required("ConvexDeploymentURL")

    static let clerkPublishableKey = required("ClerkPublishableKey")

    /// GIF sending is a non-essential feature, unlike auth/backend connectivity,
    /// so a missing key degrades to "no GIFs" (ExyteChat's own picker already
    /// handles a nil key gracefully) rather than crashing the whole app.
    static let giphyApiKey = optional("GiphyApiKey")

    /// Traps rather than silently connecting nowhere: a blank value here means
    /// `Config.xcconfig` was never filled in, and every request would fail with
    /// a confusing network error instead.
    private static func required(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            fatalError("""
                Missing '\(key)' in Info.plist. \
                Fill in ChatConvexExample/Config.xcconfig and rebuild.
                """)
        }
        return value
    }

    private static func optional(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
