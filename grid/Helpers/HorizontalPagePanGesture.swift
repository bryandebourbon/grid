import SwiftUI
#if canImport(UIKit)
import UIKit
import MapKit

/// Adds left/right swipe recognizers to the enclosing grid `UIScrollView`.
/// They run at the same time as vertical scrolling, so a sideways swipe
/// changes people tabs the same way the tab bar does.
struct GridScrollPageSwipe: UIViewRepresentable {
    var isEnabled: Bool
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.left.isEnabled = isEnabled
        context.coordinator.right.isEnabled = isEnabled
        uiView.coordinator = context.coordinator
        uiView.attachIfNeeded()
    }

    static func dismantleUIView(_ uiView: InstallerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: Bool
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        let left = UISwipeGestureRecognizer()
        let right = UISwipeGestureRecognizer()

        init(isEnabled: Bool, onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            super.init()
            left.direction = .left
            right.direction = .right
            for swipe in [left, right] {
                swipe.delegate = self
                swipe.cancelsTouchesInView = false
            }
            left.addTarget(self, action: #selector(handleLeft))
            right.addTarget(self, action: #selector(handleRight))
        }

        @objc func handleLeft() {
            guard isEnabled else { return }
            onSwipeLeft()
        }

        @objc func handleRight() {
            guard isEnabled else { return }
            onSwipeRight()
        }

        func attach(to scroll: UIScrollView) {
            if left.view !== scroll {
                left.view?.removeGestureRecognizer(left)
                scroll.addGestureRecognizer(left)
            }
            if right.view !== scroll {
                right.view?.removeGestureRecognizer(right)
                scroll.addGestureRecognizer(right)
            }
            scroll.delaysContentTouches = false
            scroll.canCancelContentTouches = false
        }

        func detach() {
            left.view?.removeGestureRecognizer(left)
            right.view?.removeGestureRecognizer(right)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    final class InstallerView: UIView {
        var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            if let scroll = findScrollView() {
                coordinator?.attach(to: scroll)
            }
        }

        private func findScrollView() -> UIScrollView? {
            var current = superview
            while let view = current {
                if let scroll = view as? UIScrollView {
                    return scroll
                }
                if let scroll = firstScrollView(in: view) {
                    return scroll
                }
                current = view.superview
            }
            return nil
        }

        private func firstScrollView(in root: UIView) -> UIScrollView? {
            if let scroll = root as? UIScrollView { return scroll }
            for child in root.subviews {
                if let scroll = firstScrollView(in: child) {
                    return scroll
                }
            }
            return nil
        }
    }
}

/// Drags the main page left to reveal search, and right to return.
struct GridSearchPager: UIViewRepresentable {
    var enabled: Bool
    var searchOpen: Bool
    var onHold: () -> Void
    var onMove: (CGFloat) -> Void
    var onEnd: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> GridSearchPagerView {
        let view = GridSearchPagerView()
        view.onHold = onHold
        view.onMove = onMove
        view.onEnd = onEnd
        view.isEnabled = enabled
        view.searchOpen = searchOpen
        return view
    }

    func updateUIView(_ view: GridSearchPagerView, context: Context) {
        view.onHold = onHold
        view.onMove = onMove
        view.onEnd = onEnd
        view.isEnabled = enabled
        view.searchOpen = searchOpen
    }

    static func dismantleUIView(_ view: GridSearchPagerView, coordinator: ()) {
        view.removePan()
    }
}

final class GridSearchPagerView: UIView, UIGestureRecognizerDelegate {
    var onHold: (() -> Void)?
    var onMove: ((CGFloat) -> Void)?
    var onEnd: ((CGFloat, CGFloat) -> Void)?
    var isEnabled = true
    var searchOpen = false
    private var pan: UIPanGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window else {
            removePan()
            return
        }
        if pan == nil {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.cancelsTouchesInView = false
            pan.delegate = self
            self.pan = pan
            window.addGestureRecognizer(pan)
        }
    }

    func removePan() {
        if let pan {
            pan.view?.removeGestureRecognizer(pan)
        }
        pan = nil
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: window)
        guard abs(velocity.x) > abs(velocity.y) else { return false }
        return searchOpen ? velocity.x > 0 : velocity.x < 0
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard isEnabled else { return false }
        if touch.location(in: window).y < 8 { return false }
        var view = touch.view
        while let current = view {
            if current is MKMapView || current is UITextField || current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: window).x
        switch pan.state {
        case .changed:
            onMove?(translation)
        case .ended:
            onEnd?(translation, pan.velocity(in: window).x)
        case .cancelled, .failed:
            onHold?()
        default:
            break
        }
    }
}
#endif
