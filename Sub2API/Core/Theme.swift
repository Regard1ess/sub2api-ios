import SwiftUI
import UIKit

enum Theme {
    static let page = adaptiveColor(light: RGB(0.933, 0.949, 0.965), dark: RGB(0.039, 0.055, 0.082))
    static let card = adaptiveColor(light: RGB(1.000, 1.000, 1.000), dark: RGB(0.078, 0.102, 0.141))
    static let muted = adaptiveColor(light: RGB(0.957, 0.973, 0.988), dark: RGB(0.118, 0.153, 0.200))
    static let overlay = adaptiveColor(light: RGB(0.910, 0.933, 0.961), dark: RGB(0.157, 0.200, 0.259))
    static let formField = adaptiveColor(light: RGB(0.902, 0.914, 0.929), dark: RGB(0.105, 0.109, 0.116))
    static let formFieldBorder = adaptiveColor(light: RGB(0.737, 0.776, 0.824), dark: RGB(0.244, 0.252, 0.266))
    static let border = adaptiveColor(light: RGB(0.847, 0.882, 0.918), dark: RGB(0.231, 0.286, 0.361))
    static let primary = adaptiveColor(light: RGB(0.059, 0.463, 0.431), dark: RGB(0.365, 0.918, 0.831))
    static let primarySoft = adaptiveColor(light: RGB(0.800, 0.984, 0.945), dark: RGB(0.055, 0.239, 0.212))
    static let text = adaptiveColor(light: RGB(0.059, 0.090, 0.165), dark: RGB(0.910, 0.941, 0.973))
    static let subtext = adaptiveColor(light: RGB(0.357, 0.404, 0.478), dark: RGB(0.663, 0.706, 0.761))
    static let subtleText = adaptiveColor(light: RGB(0.541, 0.588, 0.659), dark: RGB(0.494, 0.529, 0.592))
    static let success = adaptiveColor(light: RGB(0.082, 0.502, 0.239), dark: RGB(0.388, 0.851, 0.557))
    static let successSoft = adaptiveColor(light: RGB(0.863, 0.988, 0.906), dark: RGB(0.063, 0.227, 0.133))
    static let warning = adaptiveColor(light: RGB(0.706, 0.325, 0.035), dark: RGB(0.961, 0.722, 0.357))
    static let warningSoft = adaptiveColor(light: RGB(0.996, 0.953, 0.780), dark: RGB(0.275, 0.192, 0.059))
    static let danger = adaptiveColor(light: RGB(0.706, 0.137, 0.094), dark: RGB(1.000, 0.478, 0.420))
    static let dangerSoft = adaptiveColor(light: RGB(0.996, 0.886, 0.886), dark: RGB(0.290, 0.106, 0.094))
    static let chartBlue = adaptiveColor(light: RGB(0.145, 0.388, 0.922), dark: RGB(0.471, 0.647, 1.000))
    static let chartViolet = adaptiveColor(light: RGB(0.427, 0.365, 0.961), dark: RGB(0.655, 0.545, 0.980))
    static let chartSlate = adaptiveColor(light: RGB(0.392, 0.455, 0.545), dark: RGB(0.580, 0.639, 0.722))

    static let glassSheenStrong = adaptiveColor(light: RGB(1.000, 1.000, 1.000, 0.34), dark: RGB(1.000, 1.000, 1.000, 0.10))
    static let glassSheenSoft = adaptiveColor(light: RGB(1.000, 1.000, 1.000, 0.10), dark: RGB(1.000, 1.000, 1.000, 0.04))
    static let glassBorderStrong = adaptiveColor(light: RGB(1.000, 1.000, 1.000, 0.52), dark: RGB(1.000, 1.000, 1.000, 0.18))
    static let glassBorderSoft = adaptiveColor(light: RGB(1.000, 1.000, 1.000, 0.18), dark: RGB(1.000, 1.000, 1.000, 0.07))
    static let glassHairline = adaptiveColor(light: RGB(1.000, 1.000, 1.000, 0.30), dark: RGB(1.000, 1.000, 1.000, 0.10))
    static let glassShadow = adaptiveColor(light: RGB(0.000, 0.000, 0.000, 0.16), dark: RGB(0.000, 0.000, 0.000, 0.42))
    static let floatingTitleTint = adaptiveColor(light: RGB(0.780, 0.835, 0.886, 0.42), dark: RGB(1.000, 1.000, 1.000, 0.04))
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .surfaceStyle(cornerRadius: 18)
    }

    func surfaceStyle(cornerRadius: CGFloat) -> some View {
        self
            .background(Theme.card)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border.opacity(0.55), lineWidth: 0.8)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func liquidGlassChrome(cornerRadius: CGFloat, shadowRadius: CGFloat = 18, shadowY: CGFloat = 10) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.42)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Theme.glassBorderStrong,
                                Theme.glassBorderSoft,
                                Theme.border.opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.glassHairline.opacity(0.7), lineWidth: 0.7)
                    .blur(radius: 0.5)
                    .mask {
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.glassShadow.opacity(0.65), radius: shadowRadius, x: 0, y: shadowY)
    }

    func hideSystemNavigationChrome() -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .background(InteractivePopGestureRestorer())
    }
}

private struct InteractivePopGestureRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.restoreInteractivePopGesture()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var restoredNavigationController: UINavigationController?

        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            restoreInteractivePopGesture()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreInteractivePopGesture()
        }

        func restoreInteractivePopGesture() {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let navigationController = self.navigationController ?? self.parentNavigationController,
                      let gesture = navigationController.interactivePopGestureRecognizer else {
                    return
                }

                self.restoredNavigationController = navigationController
                gesture.isEnabled = true
                gesture.delegate = self
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === restoredNavigationController?.interactivePopGestureRecognizer else {
                return true
            }
            guard let navigationController = restoredNavigationController else {
                return false
            }
            return navigationController.viewControllers.count > 1 && navigationController.transitionCoordinator == nil
        }

        private var parentNavigationController: UINavigationController? {
            var current = parent
            while let controller = current {
                if let navigationController = controller as? UINavigationController {
                    return navigationController
                }
                current = controller.parent
            }
            return nil
        }
    }
}

private struct RGB {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

private func adaptiveColor(light: RGB, dark: RGB) -> Color {
    Color(uiColor: UIColor { traits in
        let color = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    })
}
