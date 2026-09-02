import SwiftUI
import UIKit
import ObjectiveC

extension Color {
    static let tripInk = Color(red: 0.10, green: 0.23, blue: 0.21)
    static let tripLake = Color(red: 0.30, green: 0.58, blue: 0.59)
    static let tripLakeText = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.56, green: 0.79, blue: 0.80, alpha: 1)
                : UIColor(red: 0.16, green: 0.43, blue: 0.44, alpha: 1)
        }
    )
    static let tripSage = Color(red: 0.43, green: 0.61, blue: 0.49)
    static let tripMist = Color(red: 0.74, green: 0.84, blue: 0.84)
    static let tripSand = Color(red: 0.82, green: 0.72, blue: 0.56)
    static let tripCanvas = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
        }
    )
    static let tripSurface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.tertiarySystemGroupedBackground
                : UIColor(red: 0.995, green: 0.99, blue: 0.975, alpha: 1)
        }
    )
    static let tripItemSurface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor(red: 0.965, green: 0.955, blue: 0.925, alpha: 1)
        }
    )
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.tripSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.tripMist.opacity(0.32), lineWidth: 0.8)
            }
            .shadow(color: Color.tripInk.opacity(0.055), radius: 14, y: 6)
    }
}

struct TripNavigationStack<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .background(NavigationPopEdgeGuardInstaller())
        }
    }
}

private struct NavigationPopEdgeGuardInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TrackingView {
        TrackingView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {
        context.coordinator.install(from: uiView)
    }

    static func dismantleUIView(_ uiView: TrackingView, coordinator: Coordinator) {
        // The delegate proxy is retained by the system pop recognizer so the
        // edge-only rule survives SwiftUI rebuilding or removing this view.
    }

    final class TrackingView: UIView {
        weak var coordinator: Coordinator?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.install(from: self)
        }
    }

    final class Coordinator: NSObject {
        private let edgeActivationWidth: CGFloat = 24
        private var retryScheduled = false

        func install(from hostView: UIView) {
            guard let navigationController = navigationController(from: hostView) else {
                guard !retryScheduled, hostView.window != nil else { return }
                retryScheduled = true
                DispatchQueue.main.async { [weak self, weak hostView] in
                    guard let self else { return }
                    self.retryScheduled = false
                    guard let hostView, hostView.window != nil else { return }
                    self.install(from: hostView)
                }
                return
            }
            let controllers = navigationControllers(in: hostView.window?.rootViewController)
            let targets = controllers.contains(where: { $0 === navigationController })
                ? controllers
                : controllers + [navigationController]
            for controller in targets {
                EdgeOnlyNavigationPopController.install(
                    on: controller,
                    edgeActivationWidth: edgeActivationWidth
                )
            }
        }

        private func navigationController(from view: UIView) -> UINavigationController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let navigationController = current as? UINavigationController {
                    return navigationController
                }
                if let viewController = current as? UIViewController,
                   let navigationController = viewController.navigationController {
                    return navigationController
                }
                responder = current.next
            }
            return nil
        }

        private func navigationControllers(in root: UIViewController?) -> [UINavigationController] {
            var result: [UINavigationController] = []
            var visited: Set<ObjectIdentifier> = []

            func visit(_ controller: UIViewController?) {
                guard let controller else { return }
                let identifier = ObjectIdentifier(controller)
                guard visited.insert(identifier).inserted else { return }

                if let navigationController = controller as? UINavigationController {
                    result.append(navigationController)
                }
                for child in controller.children {
                    visit(child)
                }
                visit(controller.presentedViewController)
            }

            visit(root)
            return result
        }
    }
}

private final class EdgeOnlyNavigationPopController: NSObject, UIGestureRecognizerDelegate {
    private static var associationKey: UInt8 = 0

    private weak var navigationController: UINavigationController?
    private weak var popRecognizer: UIGestureRecognizer?
    private weak var originalDelegate: UIGestureRecognizerDelegate?
    private let edgeActivationWidth: CGFloat

    private init(
        navigationController: UINavigationController,
        popRecognizer: UIGestureRecognizer,
        edgeActivationWidth: CGFloat
    ) {
        self.navigationController = navigationController
        self.popRecognizer = popRecognizer
        self.originalDelegate = popRecognizer.delegate
        self.edgeActivationWidth = edgeActivationWidth
        super.init()
    }

    static func install(
        on navigationController: UINavigationController,
        edgeActivationWidth: CGFloat
    ) {
        guard let popRecognizer = navigationController.interactivePopGestureRecognizer else { return }

        if let existing = objc_getAssociatedObject(
            navigationController,
            &associationKey
        ) as? EdgeOnlyNavigationPopController {
            if popRecognizer.delegate !== existing {
                existing.originalDelegate = popRecognizer.delegate
                popRecognizer.delegate = existing
            }
            return
        }

        let controller = EdgeOnlyNavigationPopController(
            navigationController: navigationController,
            popRecognizer: popRecognizer,
            edgeActivationWidth: edgeActivationWidth
        )
        objc_setAssociatedObject(
            navigationController,
            &associationKey,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        popRecognizer.delegate = controller
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        guard navigationController.viewControllers.count > 1 else { return false }
        guard navigationController.transitionCoordinator == nil else { return false }
        return originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let view = gestureRecognizer.view else { return false }
        guard touch.location(in: view).x <= edgeActivationWidth else { return false }
        return originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
    }

}

struct CardSwipeActionContainer<Content: View>: View {
    private let actionWidth: CGFloat = 74
    private let cornerRadius: CGFloat
    private let editTitle: String
    private let deleteTitle: String
    private let onEdit: () -> Void
    private let onDelete: () -> Void
    private let content: Content
    @State private var isOpen = false

    init(
        cornerRadius: CGFloat,
        editTitle: String,
        deleteTitle: String,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.editTitle = editTitle
        self.deleteTitle = deleteTitle
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.content = content()
    }

    private var actionPanelWidth: CGFloat { actionWidth * 2 }

    private var visibleOffset: CGFloat {
        isOpen ? -actionPanelWidth : 0
    }

    var body: some View {
        content
            .offset(x: visibleOffset)
            .contentShape(Rectangle())
            .background {
                HorizontalCardSwipeInstaller(
                    isOpen: isOpen,
                    onSwipeLeft: openActions,
                    onSwipeRight: closeActions
                )
            }
            .overlay {
                GeometryReader { geometry in
                    actionPanel
                        .frame(width: actionPanelWidth, height: geometry.size.height)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .opacity(isOpen ? 1 : 0)
                        .allowsHitTesting(isOpen)
                        .accessibilityHidden(!isOpen)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityAction(named: editTitle, onEdit)
            .accessibilityAction(named: deleteTitle, onDelete)
    }

    private var actionPanel: some View {
        HStack(spacing: 0) {
            actionButton("编辑", systemImage: "pencil", color: .tripLake) {
                closeActions()
                onEdit()
            }
            actionButton("删除", systemImage: "trash", color: .red) {
                closeActions()
                onDelete()
            }
        }
        .frame(width: actionPanelWidth)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
        .frame(width: actionWidth)
    }

    private func openActions() {
        withAnimation(.snappy(duration: 0.22)) {
            isOpen = true
        }
    }

    private func closeActions() {
        withAnimation(.snappy(duration: 0.18)) {
            isOpen = false
        }
    }
}

private struct HorizontalCardSwipeInstaller: UIViewRepresentable {
    let isOpen: Bool
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isOpen: isOpen, onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeUIView(context: Context) -> TrackingView {
        TrackingView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {
        context.coordinator.isOpen = isOpen
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.install(from: uiView)
    }

    static func dismantleUIView(_ uiView: TrackingView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class TrackingView: UIView {
        weak var coordinator: Coordinator?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.install(from: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isOpen: Bool
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        private weak var hostView: UIView?
        private weak var installedWindow: UIWindow?
        private weak var navigationPopRecognizer: UIGestureRecognizer?

        private lazy var horizontalPanRecognizer = makeRecognizer()

        init(
            isOpen: Bool,
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void
        ) {
            self.isOpen = isOpen
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        func install(from hostView: UIView) {
            self.hostView = hostView
            guard let window = hostView.window else {
                uninstall()
                return
            }
            guard installedWindow !== window else { return }
            uninstall()
            installedWindow = window
            window.addGestureRecognizer(horizontalPanRecognizer)

            navigationPopRecognizer = navigationController(from: hostView)?.interactivePopGestureRecognizer
            navigationPopRecognizer?.require(toFail: horizontalPanRecognizer)
        }

        func uninstall() {
            installedWindow?.removeGestureRecognizer(horizontalPanRecognizer)
            installedWindow = nil
            navigationPopRecognizer = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let hostView, hostView.window != nil else { return false }
            return hostView.bounds.contains(touch.location(in: hostView))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // A horizontal card action and the card's long-press drag must be
            // mutually exclusive. Allowing both recognizers to succeed made a
            // normal left swipe also reveal the drag-placement outline.
            false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
                let view = panRecognizer.view
            else { return true }

            let velocity = panRecognizer.velocity(in: view)
            let translation = panRecognizer.translation(in: view)
            let horizontalSignal = abs(velocity.x) > 1 ? velocity.x : translation.x
            let verticalSignal = abs(velocity.y) > 1 ? velocity.y : translation.y
            guard abs(horizontalSignal) > abs(verticalSignal) else { return false }

            // A rightward gesture belongs to this card only while its actions
            // are open. Otherwise the navigation controller may handle it as
            // the normal interactive back gesture.
            return horizontalSignal < 0 || isOpen
        }

        private func makeRecognizer() -> UIPanGestureRecognizer {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleHorizontalPan(_:)))
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = true
            recognizer.delegate = self
            return recognizer
        }

        @objc private func handleHorizontalPan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }

            let translation = recognizer.translation(in: view).x
            let velocity = recognizer.velocity(in: view).x
            let projectedTranslation = translation + velocity * 0.12
            guard abs(projectedTranslation) >= 44 else { return }

            if projectedTranslation < 0 {
                onSwipeLeft()
            } else {
                onSwipeRight()
            }
        }

        private func navigationController(from view: UIView) -> UINavigationController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let navigationController = current as? UINavigationController {
                    return navigationController
                }
                if let viewController = current as? UIViewController,
                   let navigationController = viewController.navigationController {
                    return navigationController
                }
                responder = current.next
            }
            return nil
        }
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }

    func installsKeyboardDismissal() -> some View {
        background(KeyboardDismissalInstaller())
    }
}

private struct KeyboardDismissalInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> HostView {
        HostView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        context.coordinator.install(in: uiView.window)
    }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class HostView: UIView {
        weak var coordinator: Coordinator?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.install(in: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private lazy var tapRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        func install(in window: UIWindow?) {
            guard installedWindow !== window else { return }
            uninstall()
            installedWindow = window
            window?.addGestureRecognizer(tapRecognizer)
        }

        func uninstall() {
            installedWindow?.removeGestureRecognizer(tapRecognizer)
            installedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touchedView = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView || view is UISearchBar {
                    return false
                }
                touchedView = view.superview
            }
            return true
        }

        @objc private func dismissKeyboard() {
            installedWindow?.endEditing(true)
        }
    }
}

extension Date {
    var compactDayText: String { formatted(.dateTime.month(.abbreviated).day()) }
    var chineseDateText: String { formatted(.dateTime.year().month().day()) }
    var timeText: String { formatted(.dateTime.hour().minute()) }
}
