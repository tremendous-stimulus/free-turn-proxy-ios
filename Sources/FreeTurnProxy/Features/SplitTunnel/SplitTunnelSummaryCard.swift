import SwiftUI

// Карточка-вход на экране «VPN подключение»: тумблер + итог + переход на
// полный экран источников. Живёт в черновике профиля (Binding), как и
// LocalWGConfigCard рядом — своей персистенции не имеет, коммит/откат уже
// даёт черновой механизм TunnelDetailView.
struct SplitTunnelSummaryCard: View {
    @Binding var config: SplitTunnelConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $config.enabled) {
                Label("Раздельное туннелирование", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
            }
            .tint(.green)

            if config.enabled {
                NavigationLink {
                    SplitTunnelView(config: $config)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(config.mode.title).font(.subheadline)
                            Text(summaryLine)
                                .font(.caption)
                                .foregroundStyle(config.isUnsafeIncludeSetup ? .red : .secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var summaryLine: String {
        if config.isUnsafeIncludeSetup {
            return "Список пуст — добавьте источник, иначе весь трафик пойдёт мимо VPN"
        }
        let n = config.activeSources.count
        return n == 0 ? "Источников нет" : "\(n) " + pluralize(n)
    }

    private func pluralize(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "источник" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "источника" }
        return "источников"
    }
}
