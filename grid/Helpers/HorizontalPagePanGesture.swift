import SwiftUI
#if canImport(UIKit)
import UIKit

/// Adds left/right swipe recognizers to the enclosing grid `UIScrollView`.
/// They run at the same time as vertical scrolling, so a sideways swipe
/// on the photos changes All ↔ Favorites the same way the tab bar does.
struct GridScrollPageSwipe: UIViewRepresentable {
    var isEnabled: Bool
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeUIView(context: Context) -> InstallerView {
        PeopleTabSwipeTrace.log("uikit.makeUIView")
        let view = InstallerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        if context.coordinator.isEnabled != isEnabled {
            PeopleTabSwipeTrace.log("uikit.update enabled \(context.coordinator.isEnabled) -> \(isEnabled)")
        }
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
        let probe = UIPanGestureRecognizer()
        private var lastProbeLog = ""

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
            probe.delegate = self
            probe.cancelsTouchesInView = false
            probe.maximumNumberOfTouches = 1
            left.addTarget(self, action: #selector(handleLeft))
            right.addTarget(self, action: #selector(handleRight))
            probe.addTarget(self, action: #selector(handleProbe))
        }

        @objc func handleProbe(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            let line = "uikit.pan \(gesture.state.rawValue) dx=\(Int(translation.x)) dy=\(Int(translation.y)) vx=\(Int(velocity.x)) vy=\(Int(velocity.y))"
            if gesture.state == .began || gesture.state == .ended || gesture.state == .cancelled {
                PeopleTabSwipeTrace.log(line)
                lastProbeLog = line
            } else if abs(translation.x) > abs(translation.y), line != lastProbeLog {
                lastProbeLog = line
                PeopleTabSwipeTrace.log(line)
            }
        }

        @objc func handleLeft() {
            PeopleTabSwipeTrace.log("uikit.swipeLeft enabled=\(isEnabled)")
            guard isEnabled else { return }
            onSwipeLeft()
        }

        @objc func handleRight() {
            PeopleTabSwipeTrace.log("uikit.swipeRight enabled=\(isEnabled)")
            guard isEnabled else { return }
            onSwipeRight()
        }

        func attach(to scroll: UIScrollView) {
            let already = left.view === scroll && right.view === scroll
            if left.view !== scroll {
                left.view?.removeGestureRecognizer(left)
                scroll.addGestureRecognizer(left)
            }
            if right.view !== scroll {
                right.view?.removeGestureRecognizer(right)
                scroll.addGestureRecognizer(right)
            }
            if probe.view !== scroll {
                probe.view?.removeGestureRecognizer(probe)
                scroll.addGestureRecognizer(probe)
            }
            scroll.delaysContentTouches = false
            scroll.canCancelContentTouches = false
            if !already {
                PeopleTabSwipeTrace.log(
                    "uikit.attached scroll=\(type(of: scroll)) " +
                    "size=\(Int(scroll.bounds.width))x\(Int(scroll.bounds.height)) " +
                    "recognizers=\(scroll.gestureRecognizers?.count ?? 0)"
                )
            }
        }

        func detach() {
            PeopleTabSwipeTrace.log("uikit.detach")
            left.view?.removeGestureRecognizer(left)
            right.view?.removeGestureRecognizer(right)
            probe.view?.removeGestureRecognizer(probe)
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

        private var lastAttachLog = ""

        func attachIfNeeded() {
            if let scroll = findScrollView() {
                coordinator?.attach(to: scroll)
                return
            }
            let chain = ancestorChain()
            if chain != lastAttachLog {
                lastAttachLog = chain
                PeopleTabSwipeTrace.log("uikit.noScrollView ancestors=\(chain)")
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
                if let scroll = firstScrollView(in: child) { return scroll }
            }
            return nil
        }

        private func ancestorChain() -> String {
            var parts: [String] = [String(describing: type(of: self))]
            var current = superview
            var depth = 0
            while let view = current, depth < 12 {
                parts.append(String(describing: type(of: view)))
                current = view.superview
                depth += 1
            }
            return parts.joined(separator: " > ")
        }
    }
}
#endif
