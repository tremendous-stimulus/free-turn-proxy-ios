import SwiftUI
import UniformTypeIdentifiers

// Полный экран источников раздельного туннелирования. Работает с
// Binding<SplitTunnelConfig> в черновике профиля — своей вью-модели и
// persist() не нужны, подтверждение/откат уже даёт TunnelDetailView.
struct SplitTunnelView: View {
    @Binding var config: SplitTunnelConfig

    @State private var showAddDialog = false
    @State private var showPresetPicker = false
    @State private var showURLSheet = false
    @State private var showManualSheet = false
    @State private var showFileImporter = false
    @State private var isRefreshingAll = false
    @State private var refreshTick = 0 // дёргаем, чтобы перечитать meta после обновления

    var body: some View {
        Form {
            Section {
                Picker("Режим", selection: $config.mode) {
                    ForEach(SplitTunnelConfig.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(config.mode.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if config.isUnsafeIncludeSetup {
                Section {
                    Label("Список пуст — включения без единого источника отправили бы весь трафик мимо VPN. Добавьте хотя бы один источник.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Источники") {
                ForEach($config.sources) { $source in
                    NavigationLink {
                        SplitTunnelSourceView(source: $source)
                    } label: {
                        sourceRow(source)
                    }
                }
                .onDelete { config.sources.remove(atOffsets: $0) }

                Button { showAddDialog = true } label: {
                    Label("Добавить источник", systemImage: "plus.circle")
                }
                .confirmationDialog("Добавить источник", isPresented: $showAddDialog) {
                    Button("Пресет…") { showPresetPicker = true }
                    Button("По ссылке") { showURLSheet = true }
                    Button("Из файла") { showFileImporter = true }
                    Button("Ввести вручную") { showManualSheet = true }
                }
                .confirmationDialog("Пресет", isPresented: $showPresetPicker) {
                    ForEach(SplitTunnelPresets.all, id: \.id) { preset in
                        Button(preset.name) { addPreset(preset) }
                    }
                }
            }

            if !config.sources.isEmpty {
                Section {
                    Button {
                        Task { await refreshAll() }
                    } label: {
                        if isRefreshingAll {
                            HStack { ProgressView(); Text("Обновление…") }
                        } else {
                            Label("Обновить все", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshingAll)
                }
                Section {
                    Text(totalLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Раздельное туннелирование")
        .navigationBarTitleDisplayMode(.inline)
        .id(refreshTick)
        .sheet(isPresented: $showURLSheet) {
            AddURLSourceSheet { name, url in
                config.sources.append(SplitTunnelSource(kind: .url, name: name, url: url))
                showURLSheet = false
            }
        }
        .sheet(isPresented: $showManualSheet) {
            AddManualSourceSheet { name, body in
                config.sources.append(SplitTunnelSource(kind: .manual, name: name, body: body))
                showManualSheet = false
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .data],
                      allowsMultipleSelection: false, onCompletion: handleFileImport)
    }

    private func sourceRow(_ source: SplitTunnelSource) -> some View {
        let meta = SplitTunnelListCache.meta(for: source.id)
        return HStack {
            Image(systemName: source.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(source.isEnabled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.subheadline)
                Text(sourceCaption(source, meta: meta))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let meta { Text("\(meta.cidrCount)").font(.caption).foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let idx = config.sources.firstIndex(where: { $0.id == source.id }) {
                config.sources[idx].isEnabled.toggle()
            }
        }
    }

    private func sourceCaption(_ source: SplitTunnelSource, meta: SplitTunnelListCache.Meta?) -> String {
        guard let meta else { return source.kind.title + " · ещё не загружен" }
        return "\(source.kind.title) · обновлено \(meta.fetchedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var totalLine: String {
        let n = config.sources.filter(\.isEnabled).reduce(0) { sum, s in
            sum + (SplitTunnelListCache.meta(for: s.id)?.cidrCount ?? 0)
        }
        return config.mode == .exclude
            ? "Мимо туннеля пойдёт \(n) подсетей"
            : "Через туннель пойдёт \(n) подсетей"
    }

    private func addPreset(_ preset: SplitTunnelPresets.Preset) {
        guard !config.sources.contains(where: { $0.presetID == preset.id }) else { return }
        config.sources.append(SplitTunnelPresets.source(for: preset))
        let source = config.sources[config.sources.count - 1]
        Task {
            await SplitTunnelListFetcher.refresh(source)
            await MainActor.run { refreshTick += 1 }
        }
    }

    private func refreshAll() async {
        isRefreshingAll = true
        for source in config.sources where source.kind.isRemote {
            await SplitTunnelListFetcher.refresh(source)
        }
        isRefreshingAll = false
        refreshTick += 1
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        config.sources.append(SplitTunnelSource(kind: .file, name: url.lastPathComponent, body: text))
    }
}

// MARK: – Мелкие шиты добавления источника

private struct AddURLSourceSheet: View {
    let onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledField(title: "Название", icon: "character.cursor.ibeam",
                             placeholder: "Мой список", text: $name)
                LabeledField(title: "Ссылка", icon: "link", placeholder: "https://…",
                             text: $url, keyboard: .URL)
            }
            .navigationTitle("По ссылке")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        onAdd(name.isEmpty ? url : name, url)
                    }
                    .disabled(URL(string: url) == nil)
                }
            }
        }
    }
}

private struct AddManualSourceSheet: View {
    let onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var body_ = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledField(title: "Название", icon: "character.cursor.ibeam",
                             placeholder: "Вручную", text: $name)
                Section("Подсети, по одной на строку") {
                    TextEditor(text: $body_).frame(minHeight: 160)
                }
            }
            .navigationTitle("Вручную")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        onAdd(name.isEmpty ? "Вручную" : name, body_)
                    }
                    .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
