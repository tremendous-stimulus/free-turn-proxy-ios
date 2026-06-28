import SwiftUI

struct CertExpiryBanner: View {
    let daysLeft: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Приложение скоро перестанет работать — осталось меньше \(daysLeft) \(Self.dayWord(forDays: daysLeft))", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            Text("Откройте SideStore → My Apps → Refresh All")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(daysLeft <= 2 ? Color.red : Color.orange)
    }

    static func dayWord(forDays daysLeft: Int) -> String {
        switch daysLeft % 10 {
        case 1 where daysLeft % 100 != 11: return "дня"
        default: return "дней"
        }
    }
}
