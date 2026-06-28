import SwiftUI

struct TunnelView: View {
    @StateObject private var vm = TunnelViewModel()
    @ObservedObject private var proxy = ProxyManager.shared
    @ObservedObject private var store = ConfigStore.shared
    @ObservedObject private var captcha = CaptchaController.shared
    @State private var editorTarget: EditorTarget?
    @State private var pendingDelete: SavedConfig?
    @State private var showUndo = false
    @State private var showImportPicker = false
    @Environment(\.isBannerVisible) private var isBannerVisible

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    vkLinkField
                    configsSection
                    if let c = store.selected {
                        activeConfigSection(c)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Туннель")
            .navigationBarTitleDisplayMode(isBannerVisible ? .inline : .large)
            .alert("Ошибка", isPresented: .isNotNil($vm.errorText)) {
                Button("OK") { vm.errorText = nil }
            } message: {
                Text(vm.errorText ?? "")
            }
            .sheet(item: $editorTarget) { target in
                ConfigEditorView(initial: target.initial, isEditing: target.editingID != nil) { saved in
                    if let id = target.editingID {
                        var s = saved; s.id = id; store.update(s)
                    } else {
                        store.add(saved)
                    }
                }
            }
            .sheet(isPresented: .isNotNil($vm.shareURL)) {
                if let url = vm.shareURL { ShareSheet(items: [url]) }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.freeturn],
                allowsMultipleSelection: false,
                onCompletion: handleImportPick
            )
            .alert("Удалить «\(pendingDelete?.name ?? "")»?",
                   isPresented: .isNotNil($pendingDelete),
                   presenting: pendingDelete) { c in
                Button("Удалить", role: .destructive) { store.delete(c) }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Вернуть удалённую конфигурацию?", isPresented: $showUndo,
                   presenting: store.lastDeleted) { _ in
                Button("Вернуть") { store.undoDelete() }
                Button("Отмена", role: .cancel) {}
            } message: { d in
                Text("«\(d.config.name)»")
            }
            .onShake { if store.lastDeleted != nil { showUndo = true } }
            .onChange(of: store.pendingImport) { cfg in
                guard let cfg else { return }
                editorTarget = EditorTarget(initial: cfg, editingID: nil)
                store.pendingImport = nil
            }
            .onAppear {
                // Файл могли открыть до появления вью (холодный старт).
                if let cfg = store.pendingImport {
                    editorTarget = EditorTarget(initial: cfg, editingID: nil)
                    store.pendingImport = nil
                }
            }
        }
    }

    private func handleImportPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let cfg = try ConfigCodec.parse(contentsOf: url)
                editorTarget = EditorTarget(initial: cfg, editingID: nil)
            } catch {
                vm.errorText = error.localizedDescription
            }
        case .failure(let error):
            vm.errorText = error.localizedDescription
        }
    }

    // MARK: – Status

    private var statusSection: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusMessage)
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

    // MARK: – VK link

    private var vkLinkField: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Label("VK звонок", systemImage: "link")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Вставьте ссылку или сгенерируйте", text: $vm.link)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(proxy.isRunning)
                if let e = vm.linkError {
                    FieldError(e)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("link-validation-error")
                }
            }
            Button {
                Task { await vm.createCall() }
            } label: {
                HStack(spacing: 6) {
                    Text("Сгенерировать ссылку")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(vm.creatingCall || proxy.isRunning)
            .sheet(isPresented: $vm.showVKWebFallback) {
                VKAuthSheet { token in vm.onVKToken(token) }
            }
        }
    }

    // MARK: – Saved configs

    private var configsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.showShakeHint { shakeHintBubble }

            HStack {
                Label("Конфигурации", systemImage: "list.bullet")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button {
                        editorTarget = EditorTarget(initial: nil, editingID: nil)
                    } label: { Label("Добавить вручную", systemImage: "square.and.pencil") }
                    Button {
                        showImportPicker = true
                    } label: { Label("Импортировать из файла", systemImage: "doc.badge.plus") }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Добавить конфигурацию")
                .disabled(proxy.isRunning)
            }

            if store.configs.isEmpty {
                Text("Нет сохранённых конфигураций. Нажмите + чтобы добавить.")
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
                    editorTarget = EditorTarget(initial: c, editingID: c.id)
                } label: { Label("Редактировать", systemImage: "pencil") }
                    .disabled(proxy.isRunning && isSelected)
                Button {
                    vm.share(c)
                } label: { Label("Поделиться", systemImage: "square.and.arrow.up") }
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

    // MARK: – Active config actions

    private func activeConfigSection(_ c: SavedConfig) -> some View {
        VStack(spacing: 14) {
            statusSection

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
            hintRow("Если конфига AmneziaWG/WireGuard ещё нет, его можно сгенерировать во вкладке VPN.")
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

// Цель редактора: editingID == nil — добавление (initial может быть из импорта),
// иначе редактирование существующей записи.
struct EditorTarget: Identifiable {
    let id = UUID()
    var initial: SavedConfig?
    var editingID: UUID?
}
