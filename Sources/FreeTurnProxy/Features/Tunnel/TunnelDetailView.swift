import SwiftUI

// Экран одной конфигурации: настройки релея отдельно от настройки реального
// VPN-подключения (режим хендшейка + его конфиг) — переключаются верхней
// горизонтальной менюшкой. Статус и кнопка подключения на этом экране не
// живут — они остаются на списке (TunnelView), там же, где были всегда.
struct TunnelDetailView: View {
    let configID: UUID
    @ObservedObject var vm: TunnelViewModel

    @ObservedObject private var store = ConfigStore.shared
    @ObservedObject private var proxy = ProxyManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var section = Section.tunnel
    @State private var showLegacyCapture = false
    @StateObject private var legacyVM = ConfigViewModel()

    private enum Section: String, CaseIterable {
        case tunnel = "Туннель"
        case vpn = "VPN подключение"
    }

    private var config: SavedConfig? { store.configs.first(where: { $0.id == configID }) }
    private var isSelected: Bool { store.selectedID == configID }

    var body: some View {
        Group {
            if let config {
                VStack(spacing: 0) {
                    Picker("Раздел", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    ScrollView {
                        VStack(spacing: 20) {
                            switch section {
                            case .tunnel:
                                ConfigEditorView(initial: config, isEditing: true, embedded: true) { saved in
                                    var s = saved; s.id = configID; store.update(s)
                                }
                                .disabled(proxy.isRunning && isSelected)
                            case .vpn:
                                modeCard(config)
                                if config.useLocalTunnel {
                                    LocalTunnelSetupView(savedConfig: config).id(config.id)
                                } else {
                                    legacyCard(config)
                                }
                            }
                        }
                        .padding([.horizontal, .bottom])
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            } else {
                EmptyView()
            }
        }
        .navigationTitle(config?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !proxy.isRunning { store.select(configID) }
        }
        .onChange(of: store.configs) { _ in
            if config == nil { dismiss() }
        }
        .sheet(isPresented: $showLegacyCapture) {
            AddServerConfigSheet { text in
                legacyVM.stage(rawConfig: text, defaultName: config?.name ?? "tunnel")
            }
        }
        .sheet(isPresented: $legacyVM.showNaming, onDismiss: { legacyVM.resetExport() }) {
            ConfigSheet(vm: legacyVM)
        }
    }

    // MARK: – Режим

    private func modeCard(_ c: SavedConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Режим хендшейка", systemImage: "arrow.triangle.branch")
                .font(.headline)

            modeOption(
                title: "Ключи остаются у вас",
                description: "Приложение только перекладывает пакеты, ваш приватный ключ уходит прямо в AmneziaWG — приложение не может расшифровать ваш трафик. Обрыв связи с релеем рвёт и хендшейк с вашим сервером.",
                isSelected: !c.useLocalTunnel
            ) { setMode(c, useLocalTunnel: false) }

            modeOption(
                title: "Приложение держит соединение",
                description: "Приложение хранит ваш конфиг и само поддерживает связь с сервером — обрыв релея чинится сам, вы этого не замечаете. Приложению нужно доверять: оно видит расшифрованный трафик.",
                isSelected: c.useLocalTunnel
            ) { setMode(c, useLocalTunnel: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(proxy.isRunning && isSelected)
    }

    private func modeOption(title: String, description: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func setMode(_ c: SavedConfig, useLocalTunnel: Bool) {
        guard c.useLocalTunnel != useLocalTunnel else { return }
        var updated = c
        updated.useLocalTunnel = useLocalTunnel
        store.update(updated)
    }

    // MARK: – Старый режим: генерация .conf

    private func legacyCard(_ c: SavedConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Конфиг для AmneziaWG", systemImage: "square.and.arrow.up.on.square")
                .font(.headline)
            Button { showLegacyCapture = true } label: {
                Label("Сгенерировать .conf", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let error = legacyVM.inputError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Конфиг вашего VPN-сервера в приложении не хранится — каждый раз собирается заново из отсканированного/загруженного файла.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
