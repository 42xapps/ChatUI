//
//  Created by Alex.M on 02.10.2023.
//

import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
public final class KeyboardState: ObservableObject {
    @Published private(set) public var isShown: Bool = false
    @Published private(set) public var keyboardFrame: CGRect = .zero
    
    private var subscriptions = Set<AnyCancellable>()

    init() {
        subscribeKeyboardNotifications()
    }

    /// Requests the dismissal of the current / active keyboard
    public func resignFirstResponder() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension KeyboardState {
    struct Transition {
        let frame: CGRect
        let animation: Animation
    }

    func subscribeKeyboardNotifications() {
        let frameChanges = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .compactMap(Transition.init(notification:))

        let hides = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in
                Transition(frame: .zero, animation: .keyboardDefault)
            }

        Publishers.Merge(frameChanges, hides)
            .receive(on: RunLoop.main)
            .sink { [weak self] transition in
                guard let self else { return }
                withAnimation(transition.animation) {
                    self.keyboardFrame = transition.frame
                    self.isShown = transition.frame != .zero
                }
            }
            .store(in: &subscriptions)
    }
}

private extension KeyboardState.Transition {
    init?(notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else { return nil }

        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? TimeInterval ?? 0.25
        let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey]
            as? Int ?? UIView.AnimationCurve.easeInOut.rawValue
        let curve = UIView.AnimationCurve(rawValue: curveValue) ?? .easeInOut

        self.init(frame: frame.cgRectValue, animation: .keyboard(duration: duration, curve: curve))
    }
}

private extension Animation {
    static let keyboardDefault = Animation.easeInOut(duration: 0.25)

    static func keyboard(duration: TimeInterval, curve: UIView.AnimationCurve) -> Animation {
        switch curve {
        case .easeIn:
            .easeIn(duration: duration)
        case .easeOut:
            .easeOut(duration: duration)
        case .linear:
            .linear(duration: duration)
        case .easeInOut:
            .easeInOut(duration: duration)
        @unknown default:
            .easeInOut(duration: duration)
        }
    }
}
