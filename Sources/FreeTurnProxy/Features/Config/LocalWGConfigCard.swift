import SwiftUI

// Режим «приложение держит соединение» (план vpn-lexical-rossum.md, фаза 3/5.3):
// две карточки вместо мастера «сканер → имя → схема → экспорт». Конфиг общий
// на всё приложение — не привязан к конкретному профилю, поэтому эта карточка
// не принимает SavedConfig и переиспользуется и при редактировании профиля
// (TunnelDetailView), и при создании нового (ConfigEditorView).
struct LocalWGConfigCard: View {
    @ObservedObject var vm: LocalWGConfigViewModel
    // Порты релея, занятые профилями (порт → чьим туннелем занят). Оба сокета
    // на loopback, поэтому совпадение означает, что responder не забиндится.
    let relayPortOwners: [Int: String]
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 20) {
            explainer
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

    private var explainer: some View {
        Text("Общий конфиг WG для всех профилей — настраивается один раз и используется вне зависимости от того, какой профиль сейчас активен")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: – Карточка 1

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Конфиг вашего VPN-сервера", systemImage: "server.rack")
                .font(.headline)

            if let external = vm.external, !external.remoteConfText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(external.remoteEndpoint.isEmpty ? "Адрес сервера не найден в конфиге" : external.remoteEndpoint)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Добавлено \(external.createdAt.formatted(date: .abbreviated, time: .shortened))")
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: – Карточка 2

    private var amneziaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Локальная конфигурация WG", systemImage: "square.and.arrow.up.on.square")
                .font(.headline)

            LabeledField(title: "Название", icon: "character.cursor.ibeam",
                         placeholder: "freeturn-XXXX", text: $vm.nameText,
                         keyboard: .default, error: nil)
                .onSubmit { vm.commitName() }
                .onChange(of: vm.nameText) { _ in vm.commitName() }

            LabeledField(title: "Порт локального WG", icon: "number",
                         placeholder: "\(LocalWGConfig.defaultPort)", text: $vm.portText,
                         keyboard: .numberPad, error: portError)
                .onSubmit { vm.commitPort() }
                .onChange(of: vm.portText) { _ in vm.commitPort() }

            Button {
                vm.regenerateKeys()
            } label: {
                Label("Перегенерировать ключи", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!vm.hasServerConfig)

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
            .disabled(!vm.hasServerConfig || vm.sending)

            if let sentAt = vm.external?.sentAt {
                Text("Отправлен \(sentAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(vm.hasServerConfig ? 1 : 0.5)
    }

    private var portError: String? {
        guard !vm.portText.isEmpty else { return nil }
        guard Validators.port(vm.portText) else { return "Число от 1 до 65535" }
        guard let p = Int(vm.portText), let owner = relayPortOwners[p] else { return nil }
        return "Порт \(p) занят туннелем \(owner) — укажите другой"
    }
}
