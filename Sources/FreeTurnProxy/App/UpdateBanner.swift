import SwiftUI

struct UpdateBanner: View {
    let latestVersion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Доступна новая версия \(latestVersion) — обновите приложение", systemImage: "arrow.down.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            Text("Откройте SideStore → Sources → Free Turn → Update")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue)
    }
}
