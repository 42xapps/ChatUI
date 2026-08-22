//
//  SessionManager.swift
//  ChatConvexExample
//

import Foundation
import ClerkKit
import ExyteChat

let currentUserKey = "currentUser"

/// Holds the signed-in user's identity, cached locally so callers that need it
/// synchronously (conversation titles, "is this my message") don't have to wait
/// on a round trip.
///
/// Identity comes from Clerk's session, projected into the Convex `users` row
/// that `syncFromClerk` creates. The cached copy is only a read-through cache —
/// Clerk's session is the source of truth for *whether* anyone is signed in.
@MainActor
final class SessionManager: ObservableObject {

    static let shared = SessionManager()

    static var currentUserId: String {
        shared.currentUser?.id ?? ""
    }

    static var currentUser: User? {
        shared.currentUser
    }

    @Published private(set) var currentUser: User?

    private init() {
        loadCachedUser()
    }

    /// Pushes the Clerk identity into Convex and adopts the resulting row.
    ///
    /// Clerk's default session token carries no name or avatar claim, so those
    /// are passed explicitly from the Clerk `User` the SDK already has locally;
    /// the backend prefers signed claims when they are present.
    /// Throws rather than swallowing: a failure here means every subsequent
    /// query would throw "Not signed in", so the caller needs to show it rather
    /// than leave the user on a spinner.
    func syncFromClerk(_ clerkUser: ClerkKit.User) async throws {
        let synced = try await ConvexService.shared.syncCurrentUser(
            name: Self.displayName(for: clerkUser),
            avatarUrl: clerkUser.hasImage ? clerkUser.imageUrl : nil
        )
        store(synced.asChatUser(isCurrentUser: true))
    }

    func clear() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: currentUserKey)
    }

    // MARK: - Local cache

    private func store(_ user: User) {
        currentUser = user
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: currentUserKey)
        }
    }

    private func loadCachedUser() {
        guard let data = UserDefaults.standard.data(forKey: currentUserKey) else { return }
        currentUser = try? JSONDecoder().decode(User.self, from: data)
    }

    /// Best available human-readable name: Clerk's profile name, then username,
    /// then the email local part.
    private static func displayName(for clerkUser: ClerkKit.User) -> String? {
        let nameParts = [clerkUser.firstName, clerkUser.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        if !nameParts.isEmpty {
            return nameParts.joined(separator: " ")
        }
        if let username = clerkUser.username, !username.isEmpty {
            return username
        }
        return clerkUser.primaryEmailAddress?.emailAddress
            .split(separator: "@")
            .first
            .map(String.init)
    }
}

extension ConvexUser {
    /// Projects a Convex `users` row onto the model `ExyteChat` renders with.
    func asChatUser(isCurrentUser: Bool) -> User {
        User(
            id: id,
            name: name,
            avatarURL: avatarUrl?.toURL(),
            isCurrentUser: isCurrentUser
        )
    }
}
