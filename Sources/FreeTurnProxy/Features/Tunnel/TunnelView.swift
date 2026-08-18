import SwiftUI

struct TunnelView: View {
    @StateObject private var vm = TunnelViewModel()
    @ObservedObject private var proxy = ProxyManager.shared
    @ObservedObject private var store = ConfigStore.shared
    @ObservedObject private var captcha = CaptchaController.shared
    @State private var pendingDelete: SavedConfig?
    @State private var showUndo = false
    @State private var showImportPicker = false
    @State private var showLinksEditor = false
    @State private var showLinkInput = false
    @State private var linkInputText = ""
    @State private var showQRScan = false
    @State private var navPath = NavigationPath()
    // Черновики создаваемых профилей — живут только тут, до подтверждения
    // (галочка в TunnelDetailView) в ConfigStore не попадают. Ключ — id
    // черновика, тот же, что уходит в navPath как ProfileRoute.new(id:).
    @State private var pendingDrafts: [UUID: SavedConfig] = [:]
    @Environment(\.isBannerVisible) private var isBannerVisible
    // Ненавязчивая подсказка про новый режим подключения — только тем, кто
    // обновился с предыдущей версии (на свежей установке нечего «пробовать
    // заново», режим и так дефолтный). Флаг считается один раз на старте
    // (LaunchState), крестик гасит его насовсем.
    @AppStorage(DefaultsKeys.isUpgradedUser) private var isUpgradedUser: Bool?
    private var showNewModeHint: Bool { isUpgradedUser == true }

    // Литерал-плейсхолдер трактовался бы как LocalizedStringKey, и SwiftUI
    // автолинкует в нём голый "https://"-подобный текст синим.
    private static let linkInputPlaceholder = "freeturn://…"

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(spacing: 24) {
                    configsSection
                    editLinksButton
                    if let c = store.selected {
                        activeConfigSection(c)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Профили")
            .navigationBarTitleDisplayMode(isBannerVisible ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { addConfigMenu }
            }
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .existing(let id):
                    TunnelDetailView(configID: id, isNew: false, initialDraft: store.configs.first(where: { $0.id == id }) ?? SavedConfig(name: "", peer: ""), vm: vm)
                case .new(let id):
                    TunnelDetailView(configID: id, isNew: true, initialDraft: pendingDrafts[id] ?? SavedConfig(name: "", peer: ""), vm: vm)
                        .onDisappear { pendingDrafts[id] = nil }
                }
            }
            .alert("Ошибка", isPresented: .isNotNil($vm.errorText)) {
                Button("OK") { vm.errorText = nil }
            } message: {
                Text(vm.errorText ?? "")
            }
            .sheet(isPresented: .isNotNil($vm.shareURL)) {
                if let url = vm.shareURL { ShareSheet(items: [url]) }
            }
            .sheet(isPresented: .isNotNil($vm.shareLink)) {
                if let link = vm.shareLink {
                    if vm.shareLinkIsQR { FreeturnLinkShareView(link: link) }
                    else { ShareSheet(items: [link]) }
                }
            }
            .sheet(isPresented: $showLinksEditor) {
                VKLinksEditorView(initialLinks: vm.links, vm: vm) { newLinks in
                    vm.links = newLinks
                }
            }
            .sheet(isPresented: $showQRScan) {
                FreeturnLinkScanSheet { cfg in addAndOpen(cfg) }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.freeturn],
                allowsMultipleSelection: false,
                onCompletion: handleImportPick
            )
            .alert("Ввести ссылку", isPresented: $showLinkInput) {
                TextField(Self.linkInputPlaceholder, text: $linkInputText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Импортировать") { importLink() }
                Button("Отмена", role: .cancel) { linkInputText = "" }
            } message: {
                Text("Вставьте ссылку freeturn://, полученную от владельца сервера")
            }
            .alert("Удалить «\(pendingDelete?.name ?? "")»?",
                   isPresented: .isNotNil($pendingDelete),
                   presenting: pendingDelete) { c in
                Button("Удалить", role: .destructive) { store.delete(c) }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Вернуть удалённый профиль?", isPresented: $showUndo,
                   presenting: store.lastDeleted) { _ in
                Button("Вернуть") { store.undoDelete() }
                Button("Отмена", role: .cancel) {}
            } message: { d in
                Text("«\(d.config.name)»")
            }
            .onShake { if store.lastDeleted != nil { showUndo = true } }
            .onChange(of: store.pendingImport) { cfg in
                guard let cfg else { return }
                addAndOpen(cfg)
                store.pendingImport = nil
            }
            .onAppear {
                // Файл могли открыть до появления вью (холодный старт).
                if let cfg = store.pendingImport {
                    addAndOpen(cfg)
                    store.pendingImport = nil
                }
            }
        }
    }

    // Добавление и импорт (ссылка/QR/файл/вручную) ведут на один и тот же
    // экран, что и редактирование — без отдельного попапа с полями: там уже
    // есть всё нужное (имя, адрес, режим VPN), включая режим WG-in-WG. В
    // ConfigStore профиль попадает только по галочке на этом экране — до
    // этого момента он существует лишь как черновик здесь.
    private func addAndOpen(_ cfg: SavedConfig) {
        pendingDrafts[cfg.id] = cfg
        navPath.append(ProfileRoute.new(id: cfg.id))
    }

    private func importLink() {
        let text = linkInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        linkInputText = ""
        guard !text.isEmpty else { return }
        do {
            let cfg = try FreeturnLink.parse(text, defaultName: "Импортировано по ссылке")
            addAndOpen(cfg)
        } catch {
            vm.errorText = error.localizedDescription
        }
    }

    private func handleImportPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let cfg = try ConfigCodec.parse(contentsOf: url)
                addAndOpen(cfg)
            } catch {
                vm.errorText = error.localizedDescription
            }
        case .failure(let error):
            vm.errorText = error.localizedDescription
        }
    }

    // MARK: – Статус и подключение

    private func activeConfigSection(_ c: SavedConfig) -> some View {
        VStack(spacing: 14) {
            statusRow(color: statusColor, text: statusMessage)

            if captcha.pendingURL != nil {
                // Во время капчи: «отключиться» ужимается в кружок-стоп, а
                // «Показать капчу» занимает оставшееся место справа.
                HStack(spacing: 12) {
                    Button { vm.toggle() } label: {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.red, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button { captcha.reopen() } label: {
                        Label("Показать капчу", systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.orange)
                }
            } else {
                Button { vm.toggle() } label: {
                    Label(
                        proxy.isRunning ? "Отключиться" : "Подключиться",
                        systemImage: proxy.isRunning ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(proxy.isRunning ? .red : .blue)
                .disabled(!vm.canConnect && !proxy.isRunning)
            }

            if proxy.state == .connected {
                statsBlock
                amneziaHint
            }
        }
    }

    private func statusRow(color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var statusColor: Color {
        switch proxy.state {
        case .connected:                             return .green
        case .connecting, .captcha, .retryBackoff:   return .yellow
        case .error:                                 return .red
        case .idle:                                  return .secondary.opacity(0.4)
        }
    }

    private var statusMessage: String {
        switch proxy.state {
        case .connecting: return "Подключение..."
        case .connected:  return "Подключено"
        case .captcha:    return "Нужно решить капчу"
        case .retryBackoff:
            let s = proxy.retryBackoffSeconds
            return "Переподключаемся через \(s > 1 ? s : 1) с" // чтобы на нуле не фликерило
        case .error:      return "Ошибка"
        case .idle:       return "Не подключено"
        }
    }

    private var statsBlock: some View {
        VStack(spacing: 6) {
            Divider()
            HStack {
                statCell(icon: "arrow.trianglehead.branch", label: "Стримы",
                         stat: "\(proxy.connectedStreams)/\(proxy.totalStreams)", substat: "стримов")
                Divider().frame(height: 36)
                statCell(icon: "arrow.up", label: "Отправлено",
                         stat: formatRate(proxy.txRateBytesPerSec), substat: formatBytes(proxy.txTotalBytes))
                Divider().frame(height: 36)
                statCell(icon: "arrow.down", label: "Получено",
                         stat: formatRate(proxy.rxRateBytesPerSec), substat: formatBytes(proxy.rxTotalBytes))
            }
        }
    }

    private func statCell(icon: String, label: String, stat: String, substat: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(.blue).font(.caption)
                Text(stat).font(.subheadline.bold()).monospacedDigit()
            }
            Text(substat).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var amneziaHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            hintRow("Если конфига AmneziaWG/WireGuard ещё нет, его можно сгенерировать в деталях этого профиля.")
            hintRow("Конфиг уже есть? Просто откройте AmneziaWG/WireGuard и включите VPN.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hintRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: – VK link

    private var editLinksButton: some View {
        Button {
            showLinksEditor = true
        } label: {
            Label("Редактировать VK-ссылки", systemImage: "link.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(proxy.isRunning)
    }

    // MARK: – Saved configs

    private var addConfigMenu: some View {
        Menu {
            Button {
                addAndOpen(SavedConfig(name: "", peer: ""))
            } label: { Label("Настроить вручную", systemImage: "square.and.pencil") }
            Button {
                showLinkInput = true
            } label: { Label("Ввести ссылку", systemImage: "link") }
            Button {
                showQRScan = true
            } label: { Label("Сканировать QR", systemImage: "qrcode.viewfinder") }
            Button {
                showImportPicker = true
            } label: { Label("Загрузить файл", systemImage: "doc.badge.plus") }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Добавить профиль")
        .disabled(proxy.isRunning)
    }

    private var configsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showNewModeHint { newModeHintBubble }
            if store.showShakeHint { shakeHintBubble }

            if store.configs.isEmpty {
                Text("Нет сохранённых профилей. Нажмите «Добавить», чтобы создать первый.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.configs) { configRow($0) }
            }
        }
        .animation(.default, value: store.showShakeHint)
    }

    private func configRow(_ c: SavedConfig) -> some View {
        let isSelected = store.selectedID == c.id
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.subheadline.bold())
                Text(c.peer).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Menu {
                Button {
                    navPath.append(ProfileRoute.existing(c.id))
                } label: { Label("Редактировать", systemImage: "pencil") }
                    .disabled(proxy.isRunning && isSelected)
                Menu {
                    Button {
                        vm.share(c)
                    } label: { Label("Файл", systemImage: "doc") }
                    Button {
                        vm.shareLinkText(c)
                    } label: { Label("Ссылка", systemImage: "link") }
                    Button {
                        vm.shareLinkQR(c)
                    } label: { Label("QR-код", systemImage: "qrcode") }
                } label: {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    pendingDelete = c
                } label: { Label("Удалить", systemImage: "trash") }
                    .disabled(proxy.isRunning && isSelected)
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { if !proxy.isRunning { store.select(c.id) } }
        .opacity(proxy.isRunning && !isSelected ? 0.4 : 1)
    }

    // Подсказка про новый режим подключения — в отличие от shakeHintBubble не
    // скрывается сама по себе, только по нажатию на крестик, и после этого
    // не появляется больше никогда (флаг в UserDefaults).
    private var newModeHintBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text("Попробуйте новый режим подключения к WG/AWG с улучшенной стабильностью")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation { isUpgradedUser = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // Разовая подсказка про шейк-отмену удаления, авто-скрытие через ~4с.
    private var shakeHintBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
            Text("Удаление можно отменить, потряхнув телефон")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { store.dismissShakeHint() }
        }
    }
}

// Пункт навигации к TunnelDetailView: существующий профиль (id уже в
// ConfigStore) или черновик нового (id только в TunnelView.pendingDrafts,
// пока пользователь не подтвердит создание галочкой).
enum ProfileRoute: Hashable {
    case existing(UUID)
    case new(id: UUID)
}
