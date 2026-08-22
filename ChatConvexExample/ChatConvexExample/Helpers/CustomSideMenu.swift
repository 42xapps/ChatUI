//
//  CustomSideMenu.swift
//  XStyleSideBar
//
//  Created by Balaji Venkatesh on 08/05/26.
//

import SwiftUI

struct CustomSideMenu<MenuContent: View, Content: View>: View {
    var isEnabled: Bool = true
    var sideBarWidth: CGFloat = 280
    @Binding var isExpanded: Bool
    @ViewBuilder var menuContent: (_ progress: CGFloat) -> MenuContent
    @ViewBuilder var content: (_ progress: CGFloat) -> Content
    /// View Properties
    @State private var progress: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var haptics: Bool = false
    var body: some View {
        ZStack(alignment: .leading) {
            menuContent(progress)
                .frame(width: sideBarWidth)
                .frame(maxHeight: .infinity)
                .opacity(progress)
                .scaleEffect(0.95 + (0.05 * progress))
            
            content(progress)
                .containerRelativeFrame(.horizontal)
                .frame(maxHeight: .infinity)
                .background {
                    backgroundShape
                        .fill(.background)
                        .ignoresSafeArea()
                }
                .overlay {
                    backgroundShape
                        .fill(.fill.tertiary)
                        .stroke(.fill.secondary, lineWidth: 1)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(animation) {
                                dismissMenu()
                            }
                        }
                        .opacity(progress)
                }
                .mask {
                    backgroundShape
                        .ignoresSafeArea()
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.06 * progress), radius: 5, x: -10, y: 0)
                .offset(x: xOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .gesture(
            CustomSideMenuGesture(isEnabled: isEnabled, isExpanded: $isExpanded) { gesture in
                let state = gesture.state
                let translation = gesture.translation(in: gesture.view).x + (isExpanded ? sideBarWidth : 0)
                let velocity = gesture.velocity(in: gesture.view).x / 5
                
                if state == .began || state == .changed {
                    xOffset = min(max(translation, 0), sideBarWidth)
                    progress = xOffset / sideBarWidth
                } else {
                    withAnimation(animation) {
                        if (xOffset + velocity) > (sideBarWidth / 2) {
                            expandMenu()
                        } else {
                            dismissMenu()
                        }
                    }
                }
            }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: haptics)
        .onChange(of: isExpanded) { oldValue, newValue in
            withAnimation(animation) {
                if newValue && progress != 1 {
                    expandMenu()
                }
                
                if !newValue && progress != 0 {
                    dismissMenu()
                }
            }
        }
    }
    
    func expandMenu() {
        if !isExpanded { haptics.toggle() }
        
        /// Expanded
        xOffset = sideBarWidth
        progress = 1
        isExpanded = true
    }
    
    func dismissMenu() {
        if isExpanded { haptics.toggle() }
        
        /// Reset
        xOffset = 0
        progress = 0
        isExpanded = false
    }
    
    var backgroundShape: some Shape {
        if #available(iOS 26, *) {
            return ConcentricRectangle(corners: .concentric, isUniform: true)
        } else {
            /// USE EXTRACTED DEVICE CORNER RADIUS VALUE HERE
            return RoundedRectangle(cornerRadius: 45)
        }
    }
    
    var animation: Animation {
        .interactiveSpring(duration: 0.2, extraBounce: 0.02)
    }
}

/// Custom Gesture For Side Menu Which Respects If there any horizontal scroll interactions!
fileprivate struct CustomSideMenuGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    @Binding var isExpanded: Bool
    var handle: (UIPanGestureRecognizer) -> ()
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.delegate = context.coordinator
        gesture.maximumNumberOfTouches = 1
        return gesture
    }
    
    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }
    
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        handle(recognizer)
    }
    
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CustomSideMenuGesture
        init(parent: CustomSideMenuGesture) {
            self.parent = parent
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
                let velocity = panGesture.velocity(in: panGesture.view)
                let isHorizontalSwipe = abs(velocity.x) > abs(velocity.y)
                /// ADD MORE CONDITIONS ACCORDING TO YOUR WISH
                
                return (isHorizontalSwipe && velocity.x > 0) || (isHorizontalSwipe && velocity.x < 0 && parent.isExpanded)
            }
            
            return false
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if let scrollview = otherGestureRecognizer.view as? UIScrollView {
                let offset = scrollview.contentOffset.x
                return offset <= 0
            }
            
            return false
        }
    }
}
