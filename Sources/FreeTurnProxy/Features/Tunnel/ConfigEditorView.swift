import SwiftUI

// Редактор сохранённой конфигурации (только ручной ввод). Поля можно
// предзаполнить из импортированного файла — невалидные подсветятся ошибками.
struct ConfigEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let isEditing: Bool
    let onSave: (SavedConfig) -> Void

    // Подсвечивать пустые обязательные поля сразу (для импорта/правки),
    // а на чистой ручной форме — не пугать красным до ввода.
    private let prefilled: Bool

    @State private var name: String
    @State private var peer: String
    @State private var obfKey: String
    @State private var dns: String
    @State private var listen: String
    @State private var transport: String

    init(initial: SavedConfig?, isEditing: Bool, onSave: @escaping (SavedConfig) -> Void) {
        self.isEditing = isEditing
        self.onSave = onSave
        self.prefilled = initial != nil
        _name = State(initialValue: initial?.name ?? "")
        _peer = State(initialValue: initial?.peer ?? "")
        _obfKey = State(initialValue: initial?.obfKey ?? "")
        _dns = State(initialValue: initial?.dns ?? "")
        _listen = State(initialValue: initial?.listen ?? "")
        _transport = State(initialValue: initial?.transport ?? "udp")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LabeledField(title: "Название (обязательно)", icon: "character.cursor.ibeam",
                                 placeholder: "Например, Мой сервер", text: $name,
                                 error: nameError)

                    LabeledField(title: "Адрес сервера (обязательно)", icon: "server.rack",
                                 placeholder: "1.2.3.4:56000", text: $peer,
                                 keyboard: .asciiCapable, error: peerError)

                    LabeledField(title: "Ключ обфускации", icon: "key.fill",
                                 placeholder: "64 hex символа, если сервер с rtpopus", text: $obfKey,
                                 keyboard: .asciiCapable, error: obfKeyError)

                    DisclosureGroup {
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Транспорт", systemImage: "arrow.left.arrow.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Picker("Транспорт", selection: $transport) {
                                    Text("UDP").tag("udp")
                                    Text("TCP").tag("tcp")
                                }
                                .pickerStyle(.segmented)
                            }

                            LabeledField(title: "DNS", icon: "network",
                                         placeholder: "8.8.8.8 по умолчанию", text: $dns,
                                         keyboard: .numbersAndPunctuation, error: dnsError)

                            LabeledField(title: "Локальный адрес", icon: "antenna.radiowaves.left.and.right",
                                         placeholder: "127.0.0.1:9000 по умолчанию", text: $listen,
                                         keyboard: .asciiCapable, error: listenError)
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Расширенные настройки", systemImage: "slider.horizontal.3")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Редактирование" : "Новая конфигурация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(!canSave)
                }
            }
        }
    }

    // MARK: – Валидация

    private var highlightEmpty: Bool { prefilled }

    private var nameError: String? {
        guard name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return highlightEmpty ? "Укажите название" : nil
    }
    private var peerError: String? {
        let s = peer.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return highlightEmpty ? "Укажите адрес сервера" : nil }
        return Validators.endpoint(s) ? nil : "Формат адрес:порт, напр. 1.2.3.4:56000"
    }
    private var obfKeyError: String? {
        let s = obfKey.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        return Validators.hexKey(s) ? nil : "64 hex-символа (0–9, a–f)"
    }
    private var dnsError: String? {
        let s = dns.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        return Validators.ipv4(s) ? nil : "Должен быть IPv4, напр. 8.8.8.8"
    }
    private var listenError: String? {
        let s = listen.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        return Validators.endpoint(s) ? nil : "Формат адрес:порт, напр. 127.0.0.1:9000"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Validators.endpoint(peer.trimmingCharacters(in: .whitespaces))
            && obfKeyError == nil && dnsError == nil && listenError == nil
    }

    private func save() {
        let c = SavedConfig(
            name: name.trimmingCharacters(in: .whitespaces),
            peer: peer.trimmingCharacters(in: .whitespaces),
            obfKey: obfKey.trimmingCharacters(in: .whitespaces),
            dns: dns.trimmingCharacters(in: .whitespaces),
            listen: listen.trimmingCharacters(in: .whitespaces),
            transport: transport
        )
        onSave(c)
        dismiss()
    }
}
