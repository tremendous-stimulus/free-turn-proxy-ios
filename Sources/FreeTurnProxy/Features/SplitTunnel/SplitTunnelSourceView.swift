import SwiftUI

// Push-редактор одного источника: имя всегда, URL для preset/url,
// редактируемый текст для manual/file, кнопка «Обновить сейчас» для удалённых
// источников, статус и превью первых строк содержимого.
struct SplitTunnelSourceView: View {
    @Binding var source: SplitTunnelSource

    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var refreshTick = 0

    var body: some View {
        Form {
            Section {
                Toggle("Включён", isOn: $source.isEnabled)
                LabeledField(title: "Название", icon: "character.cursor.ibeam",
                             placeholder: "Название", text: $source.name)
            }

            if source.kind.isRemote {
                Section("Ссылка") {
                    if source.kind == .preset {
                        Text(source.url ?? "").font(.caption).foregroundStyle(.secondary)
                    } else {
                        LabeledField(title: "URL", icon: "link", placeholder: "https://…",
                                     text: Binding(get: { source.url ?? "" }, set: { source.url = $0 }),
                                     keyboard: .URL)
                    }
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            HStack { ProgressView(); Text("Обновление…") }
                        } else {
                            Label("Обновить сейчас", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || source.url.flatMap(URL.init) == nil)
                    if let refreshError {
                        FieldError(refreshError)
                    }
                }
            } else {
                Section("Подсети, по одной на строку") {
                    TextEditor(text: Binding(get: { source.body ?? "" }, set: { source.body = $0 }))
                        .frame(minHeight: 200)
                        .font(.system(.footnote, design: .monospaced))
                }
            }

            Section("Статус") {
                statusRows
            }

            if let preview {
                Section("Превью") {
                    Text(preview)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(source.name.isEmpty ? "Источник" : source.name)
        .navigationBarTitleDisplayMode(.inline)
        .id(refreshTick)
    }

    private var meta: SplitTunnelListCache.Meta? {
        source.kind.isRemote ? SplitTunnelListCache.meta(for: source.id) : nil
    }

    @ViewBuilder
    private var statusRows: some View {
        if source.kind.isRemote {
            if let meta {
                LabeledContent("Подсетей", value: "\(meta.cidrCount)")
                LabeledContent("Обновлено", value: meta.fetchedAt.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text("Ещё не загружен").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            let count = AllowedIPsBuilder.parseListLines(source.body ?? "").count
            LabeledContent("Подсетей", value: "\(count)")
        }
    }

    private var preview: String? {
        let text = source.kind.isRemote ? (SplitTunnelListCache.body(for: source.id) ?? "") : (source.body ?? "")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).prefix(20)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func refresh() async {
        isRefreshing = true
        refreshError = nil
        let ok = await SplitTunnelListFetcher.refresh(source)
        if !ok { refreshError = "Не удалось загрузить список — проверьте ссылку и интернет" }
        isRefreshing = false
        refreshTick += 1
    }
}
