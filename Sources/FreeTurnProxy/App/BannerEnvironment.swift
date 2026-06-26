import SwiftUI

private struct BannerVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isBannerVisible: Bool {
        get { self[BannerVisibleKey.self] }
        set { self[BannerVisibleKey.self] = newValue }
    }
}
