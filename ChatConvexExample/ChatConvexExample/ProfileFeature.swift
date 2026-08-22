//
//  ProfileFeature.swift
//  ChatConvexExample
//
//  Presented from the chat-history sidebar's profile row.
//
//  This is Clerk's own prebuilt `UserProfileView` (ClerkKitUI), not a
//  hand-built screen: avatar with real editing, connected accounts (this is
//  where "Signed in via Apple" actually shows up — under Manage Account, not
//  a label this app fabricates), security, and sign out, all wired to live
//  Clerk data already. Hand-rolling a profile screen would mean reimplementing
//  something the SDK ships and maintains, with none of its editing flows.
//

import SwiftUI
import ClerkKitUI

struct ProfileSheet: View {
    var body: some View {
        UserProfileView()
    }
}
