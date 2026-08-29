import Combine
import SwiftUI
import Testing
import UIKit

@testable import ExyteChat

@Suite("Table update transactions")
@MainActor
struct TableUpdateTransactionTests {
    @Test("A transaction returns only after its table update finishes")
    func waitsForTableUpdateCompletion() async throws {
        let model = TransactionHarness()
        let host = UIHostingController(rootView: TransactionHarnessView(model: model))
        let windowScene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitUntil {
            model.transaction != nil
                && host.view.firstSubview(of: UITableView.self)?.numberOfRows(inSection: 0) == 1
        }

        let transaction = try #require(model.transaction)
        let tableView = try #require(host.view.firstSubview(of: UITableView.self))
        await transaction(animationMode: .natural) {
            model.messages = TransactionHarness.messages(count: 2)
        }

        #expect(tableView.numberOfRows(inSection: 0) == 2)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw TransactionTestTimeout()
    }
}

@MainActor
private final class TransactionHarness: ObservableObject {
    @Published var messages = TransactionHarness.messages(count: 1)
    var transaction: TableUpdateTransaction?

    static func messages(count: Int) -> [Message] {
        let user = User(
            id: "user",
            name: "User",
            avatarURL: nil,
            isCurrentUser: true
        )
        return (0..<count).map { index in
            Message(
                id: "message-\(index)",
                user: user,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                text: "Message \(index)"
            )
        }
    }
}

private struct TransactionHarnessView: View {
    @ObservedObject var model: TransactionHarness

    var body: some View {
        ChatView(messages: model.messages) { _ in }
            .updateTransaction($model.transaction)
    }
}

private extension UIView {
    func firstSubview<ViewType: UIView>(of type: ViewType.Type) -> ViewType? {
        if let match = self as? ViewType { return match }
        for subview in subviews {
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }
}

private struct TransactionTestTimeout: Error {}
