import SwiftUI

// Экран одного профиля: настройки релея отдельно от настройки реального
// VPN-подключения (режим хендшейка + его конфиг) — переключаются верхней
// горизонтальной менюшкой. Статус и кнопка подключения на этом экране не
// живут — они остаются на списке (TunnelView), там же, где были всегда.
//
// Черновой режим: все правки (поля профиля, режим VPN, добавление/замена
// конфига WG-сервера) идут в локальный draft/wgConfigVM и не касаются
// ConfigStore/Keychain, пока не нажата галочка — крестик отбрасывает всё,
// включая только что загруженный конфиг сервера. При создании профиля
// (isNew) он не появляется в списке вообще, пока не подтверждён.
struct TunnelDetailView: View {
    let configID: UUID
    let isNew: Bool
    @ObservedObject var vm: TunnelViewModel

    @ObservedObject private var store = ConfigStore.shared
    @ObservedObject private var proxy = ProxyManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var section = Section.tunnel
    @State private var showLegacyCapture = false
    @State private var pendingLegacyConfig: String?
    @StateObject private var legacyVM = ConfigViewModel()
    @StateObject private var wgConfigVM: LocalWGConfigViewModel

    @State private var draft: SavedConfig
    // Валидность встроенного редактора: он коммитит любое значение, включая
    // невалидное, поэтому галочку гасим отсюда.
    @State private var editorValid = true
    // nil при создании — тогда сравнивать draft не с чем, экран всегда «грязный».
    private let original: SavedConfig?

    private enum Section: String, CaseIterable {
        case tunnel = "Туннель"
        case vpn = "VPN подключение"
    }

    init(configID: UUID, isNew: Bool, initialDraft: SavedConfig, vm: TunnelViewModel) {
        self.configID = configID
        self.isNew = isNew
        self.vm = vm
        self._draft = State(initialValue: initialDraft)
        self.original = isNew ? nil : initialDraft
        self._wgConfigVM = StateObject(wrappedValue: LocalWGConfigViewModel(profileID: configID))
    }

    private var isSelected: Bool { store.selectedID == configID }
    private var hasUnsavedChanges: Bool { isNew || draft != original || wgConfigVM.isDirty }

    // Адрес релея этого профиля: пустое поле «Локальный адрес» = дефолт ядра.
    private var draftRelayAddr: String {
        let v = draft.listen.trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? AppSettings.defaultListen : v
    }

    private var relayPort: Int? { Validators.port(ofEndpoint: draftRelayAddr) }

    // Кто из профилей занимает какой порт релея. Конфиг локального WG общий на
    // все профили, поэтому совпадение с ЛЮБЫМ профилем рано или поздно всплывёт
    // как «address already in use» — блокируем сразу, а не когда пользователь
    // переключится на тот профиль.
    private var relayPortOwners: [Int: String] {
        var owners: [Int: String] = [:]
        for c in store.configs where c.id != configID {
            let raw = c.listen.trimmingCharacters(in: .whitespaces)
            guard let p = Validators.port(ofEndpoint: raw.isEmpty ? AppSettings.defaultListen : raw) else { continue }
            owners[p] = "профиля «\(c.name)»"
        }
        // Черновик перебивает сохранённое значение текущего профиля.
        if let relayPort {
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            owners[relayPort] = name.isEmpty ? "этого профиля" : "профиля «\(name)»"
        }
        return owners
    }

    // Релей и WG-responder оба сидят на loopback: одинаковый порт — responder
    // не забиндится, туннель поднимется, а интернета не будет. Ловим на
    // сохранении, а не в рантайме.
    private var hasPortCollision: Bool {
        guard draft.useLocalTunnel, let local = wgConfigVM.local else { return false }
        return relayPortOwners[local.port] != nil
    }

    private var canConfirm: Bool {
        editorValid
            && !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && Validators.endpoint(draft.peer)
            && (!draft.useLocalTunnel || wgConfigVM.hasServerConfig)
            && !hasPortCollision
    }

    var body: some View {
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
                        ConfigEditorView(initial: draft, isEditing: true, embedded: true,
                                         onValidityChange: { editorValid = $0 }) { saved in
                            var s = saved; s.id = configID; s.useLocalTunnel = draft.useLocalTunnel
                            draft = s
                        }
                        .disabled(proxy.isRunning && isSelected)
                    case .vpn:
                        modeCard
                        if draft.useLocalTunnel {
                            LocalWGConfigCard(vm: wgConfigVM, relayPortOwners: relayPortOwners)
                        } else {
                            legacyCard
                        }
                    }
                }
                .padding([.horizontal, .bottom])
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Заголовок держит сохранённое имя, а не то, что сейчас набрано в
        // поле — пока не нажата галочка, ничего не применяется, и заголовок
        // не должен выглядеть так, будто переименование уже случилось.
        .navigationTitle(isNew ? "Новый профиль" : (original?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .interactivePopGestureDisabled(hasUnsavedChanges)
        .toolbar {
            if hasUnsavedChanges {
                ToolbarItem(placement: .cancellationAction) {
                    Button { cancelChanges() } label: { Image(systemName: "xmark") }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { confirm() } label: { Image(systemName: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(!canConfirm)
                }
            }
        }
        // Выбор профиля — явное действие в списке (тап по строке). Открытие
        // экрана его не меняет: раньше это меняли в onAppear, и выход по ✗
        // оставлял выбранным не тот профиль, с которого пришли.
        .onChange(of: store.configs) { _ in
            // Профиль удалили снаружи (второй экран/шорткат) — новый профиль
            // тут ни при чём, он в store.configs до подтверждения не попадает.
            if !isNew, store.configs.first(where: { $0.id == configID }) == nil { dismiss() }
        }
        // Разбор откладываем до полного закрытия первого шита: showNaming,
        // выставленный из ещё анимирующегося шита, на iOS 16 регулярно теряется
        // — пользователь сканирует QR, и не происходит ничего.
        .sheet(isPresented: $showLegacyCapture, onDismiss: {
            guard let text = pendingLegacyConfig else { return }
            pendingLegacyConfig = nil
            // Endpoint берём из черновика открытого профиля, а не из глобально
            // выбранного: генерируем мы для того профиля, что на экране.
            legacyVM.relayEndpoint = draftRelayAddr
            legacyVM.stage(rawConfig: text, defaultName: draft.name.isEmpty ? "tunnel" : draft.name)
        }) {
            AddServerConfigSheet { text in pendingLegacyConfig = text }
        }
        .sheet(isPresented: $legacyVM.showNaming, onDismiss: { legacyVM.resetExport() }) {
            ConfigSheet(vm: legacyVM)
        }
    }

    // MARK: – Подтверждение/отмена

    private func confirm() {
        wgConfigVM.persist()
        if isNew {
            store.add(draft)
        } else {
            store.update(draft)
        }
        dismiss()
    }

    private func cancelChanges() {
        wgConfigVM.discard()
        dismiss()
    }

    // MARK: – Режим

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Режим подключения к VPN", systemImage: "arrow.triangle.branch")
                .font(.headline)

            modeOption(
                title: "Туннель + WireGuard/AmneziaWG",
                description: "Рекомендуется при использовании WireGuard/AmneziaWG, обеспечивает наилучшую стабильность соединения. Вы загружаете конфигурацию VPN, приложение само устанавливает и мониторит подключение. Приложение генерирует локальную конфигурацию для WireGuard, которая проксирует трафик через туннель",
                isSelected: draft.useLocalTunnel
            ) { draft.useLocalTunnel = true }

            modeOption(
                title: "Только туннель",
                description: "Поднять только туннель на локальном порту до сервера. Приложение не следит за состоянием подключения - при отсутствии интернета нужно будет переподключиться самостоятельно",
                isSelected: !draft.useLocalTunnel
            ) { draft.useLocalTunnel = false }

            if draft.useLocalTunnel && !wgConfigVM.hasServerConfig {
                Text("Чтобы сохранить профиль в этом режиме, сначала добавьте конфиг вашего VPN-сервера ниже")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
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

    // MARK: – Старый режим: генерация .conf

    private var legacyCard: some View {
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
