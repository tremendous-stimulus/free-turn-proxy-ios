import SwiftUI

// SwiftUI's navigationBarBackButtonHidden прячет только кнопку — свайп назад
// остаётся активным (известная особенность фреймворка). Единственный доступ
// к самому жесту — через UIKit, отсюда представляемый пустой UIViewController.
private struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    let disabled: Bool

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = !disabled
    }

    // Гарантия на выход из экрана: если жест был выключен, он не должен
    // остаться выключенным для следующего экрана в стеке.
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

extension View {
    func interactivePopGestureDisabled(_ disabled: Bool) -> some View {
        background(InteractivePopGestureDisabler(disabled: disabled))
    }
}
