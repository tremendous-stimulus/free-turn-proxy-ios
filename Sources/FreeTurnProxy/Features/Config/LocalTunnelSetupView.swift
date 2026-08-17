import SwiftUI

// Режим «приложение держит соединение» (план vpn-lexical-rossum.md, фаза 3):
// две карточки вместо мастера «сканер → имя → схема → экспорт». Профиль
// ставится в AmneziaWG один раз — дальше правки идут только здесь. Встраивается
// в экран деталей туннеля (TunnelDetailView), своей навигации не имеет.
struct LocalTunnelSetupView: View {
    @StateObject private var vm: LocalTunnelSetupViewModel
    @State private var showAddSheet = false

    init(savedConfig: SavedConfig) {
        _vm = StateObject(wrappedValue: LocalTunnelSetupViewModel(savedConfig: savedConfig))
    }

    var body: some View {
        VStack(spacing: 20) {
            serverCard
            amneziaCard
        }
        .sheet(isPresented: $showAddSheet) {
            AddServerConfigSheet { text in vm.addOrReplace(rawConfigText: text) }
        }
        .sheet(isPresented: $vm.showExport) {
            if let url = vm.exportURL { ShareSheet(items: [url]) }
        }
        .alert("Ошибка", isPresented: .isNotNil($vm.errorText)) {
            Button("OK") { vm.errorText = nil }
        } message: {
            Text(vm.errorText ?? "")
        }
    }

    // MARK: – Карточка 1

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Конфиг вашего VPN-сервера", systemImage: "server.rack")
                .font(.headline)

            if let profile = vm.profile {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.remoteEndpoint.isEmpty ? "Адрес сервера не найден в конфиге" : profile.remoteEndpoint)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Добавлено \(profile.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button { showAddSheet = true } label: {
                    Label("Заменить", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button { showAddSheet = true } label: {
                    Label("Добавить", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("Хранится только в этом приложении, наружу не выдаётся")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: – Карточка 2

    private var amneziaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Профиль для AmneziaWG", systemImage: "square.and.arrow.up.on.square")
                .font(.headline)

            Button {
                vm.sendToAmneziaWG()
            } label: {
                if vm.sending {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Отправить в AmneziaWG", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.profile == nil || vm.sending)

            if let sentAt = vm.profile?.sentAt {
                Text("Отправлен \(sentAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Ставится один раз. Дальше всё настраивается здесь.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(vm.profile == nil ? 0.5 : 1)
    }
}
