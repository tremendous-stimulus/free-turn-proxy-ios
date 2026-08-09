import SwiftUI

struct RefreshReminderBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Не забудьте обновить приложение в SideStore", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                Text("Откройте SideStore → My Apps → Refresh All, иначе доступ пропадёт")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange)
    }
}
