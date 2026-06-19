import SwiftUI
import UIKit

// Системный жест «потрясти телефон»: UIWindow по цепочке респондеров ловит
// motionShake и шлёт нотификацию, которую слушает модификатор .onShake.
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}

private struct ShakeDetector: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)
        ) { _ in action() }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(action: action))
    }
}
