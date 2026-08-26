//
//  ContentView.swift
//  ChatConvexExample
//

import SwiftUI
import ClerkKit
import ClerkKitUI
import ConvexMobile

struct ContentView: View {

    /// How long to wait for the Convex connection to adopt a live Clerk session
    /// before assuming it never will. `ClerkConvexAuthProvider` drives that off
    /// Clerk's auth events and normally takes well under a second.
    private static let authTimeout = Duration.seconds(10)

    /// Whether Clerk and the Convex connection agree about being signed in.
    /// They lag each other by a round trip, so both are consulted.
    private enum AuthPhase: Equatable {
        case connecting
        case signedOut
        case authenticated
    }

    private enum RootState: Equatable {
        case connecting
        case signedOut
        case failed(String)
        case ready
    }

    @Environment(Clerk.self) private var clerk

    /// nil while the Convex connection is still deciding.
    @State private var convexAuthenticated: Bool?

    /// The Convex `users` row exists. Everything else requires it, so nothing
    /// renders until it does.
    @State private var userSynced = false

    @State private var failure: String?

    /// Bumped to re-run the task after a failure.
    @State private var retry = 0

    var body: some View {
        Group {
            switch rootState {
            case .connecting:
                ProgressView()
                    .controlSize(.large)
            case .signedOut:
                // Clerk's prebuilt flow. Which methods it offers — Sign in with
                // Apple, email code, password — comes from the instance
                // settings in the Clerk Dashboard, not from here.
                AuthView(isDismissible: false)
            case .failed(let message):
                failureView(message)
            case .ready:
                ChatHomeView()
            }
        }
        .onReceive(ConvexService.shared.authState) { state in
            switch state {
            case .authenticated:
                convexAuthenticated = true
            case .unauthenticated:
                convexAuthenticated = false
            case .loading:
                convexAuthenticated = nil
            }
        }
        .task(id: taskTrigger) {
            switch authPhase {
            case .authenticated:
                guard let clerkUser = clerk.user, !userSynced else { return }
                do {
                    // Has to land before ConversationView appears: every query
                    // and mutation calls `requireCurrentUser` and throws
                    // without this row.
                    try await SessionManager.shared.syncFromClerk(clerkUser)
                    failure = nil
                    userSynced = true
                } catch {
                    failure = "\(error)"
                }

            case .connecting:
                // A signed-in Clerk session the Convex connection hasn't
                // adopted. If it still hasn't after a grace period, say so —
                // this is the state a rejected token produces, and an
                // indefinite spinner hides it completely. Cancelled
                // automatically if auth resolves, because that changes the
                // task's id.
                guard clerk.isLoaded, clerk.user != nil, convexAuthenticated == false
                else { return }
                try? await Task.sleep(for: Self.authTimeout)
                guard !Task.isCancelled else { return }
                failure = """
                    The Convex deployment rejected the Clerk session token.

                    Check that the Clerk Dashboard's Convex integration is \
                    active — it adds the `aud: convex` claim that \
                    auth.config.ts matches — and that \
                    CLERK_FRONTEND_API_URL on the deployment is the full \
                    https:// issuer URL.
                    """

            case .signedOut:
                userSynced = false
                failure = nil
                SessionManager.shared.clear()
            }
        }
    }

    /// Identity for the task, so it re-runs whenever anything it branches on
    /// changes — including the inputs to the `.connecting` timeout, which
    /// `authPhase` alone would collapse.
    private struct TaskTrigger: Equatable {
        let clerkLoaded: Bool
        let hasClerkUser: Bool
        let convexAuthenticated: Bool?
        let retry: Int
    }

    private var taskTrigger: TaskTrigger {
        TaskTrigger(
            clerkLoaded: clerk.isLoaded,
            hasClerkUser: clerk.user != nil,
            convexAuthenticated: convexAuthenticated,
            retry: retry
        )
    }

    private var authPhase: AuthPhase {
        guard clerk.isLoaded else { return .connecting }

        switch convexAuthenticated {
        case .some(true):
            return .authenticated
        case .none:
            return .connecting
        case .some(false):
            // A returning user has a cached Clerk session before Convex has
            // exchanged it for a token; calling that "signed out" would flash
            // the sign-in screen on every cold launch.
            return clerk.user == nil ? .signedOut : .connecting
        }
    }

    private var rootState: RootState {
        if let failure, !userSynced { return .failed(failure) }

        switch authPhase {
        case .connecting:
            return .connecting
        case .signedOut:
            return .signedOut
        case .authenticated:
            return userSynced ? .ready : .connecting
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn't reach the chat backend")
                .font(17, .primary, .semibold)
            Text(message)
                .font(13, .gray)
                .multilineTextAlignment(.center)
            Button("Try again") {
                failure = nil
                retry += 1
            }
            .font(17, .exampleBlue, .medium)
            Button("Log out") {
                Task { try? await Clerk.shared.auth.signOut() }
            }
            .font(15, .gray)
        }
        .padding(32)
    }
}
