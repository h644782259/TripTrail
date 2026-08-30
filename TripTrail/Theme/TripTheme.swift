import SwiftUI

extension Color {
    static let tripInk = Color(red: 0.10, green: 0.23, blue: 0.21)
    static let tripLake = Color(red: 0.30, green: 0.58, blue: 0.59)
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
