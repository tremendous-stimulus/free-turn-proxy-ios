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
    // clientId в этой форме не редактируется — он приходит из freeturn://
    // ссылки при импорте (см. Этап C) и должен просто пройти через save().
    private let clientId: String

    @State private var name: String
    @State private var peer: String
    @State private var manualCaptcha: Bool

    @State private var obfProfile: String
    @State private var obfKey: String
    @State private var obfTimingMsText: String

    @State private var transport: String
    @State private var mode: String
    @State private var bond: Bool

    @State private var threadsText: String
    @State private var streamsPerCredText: String

    @State private var dnsMode: String
    @State private var dns: String

    @State private var turnEndpoint: String
    @State private var listen: String
    @State private var debug: Bool

    init(initial: SavedConfig?, isEditing: Bool, onSave: @escaping (SavedConfig) -> Void) {
        self.isEditing = isEditing
        self.onSave = onSave
        self.prefilled = initial != nil
        self.clientId = initial?.clientId ?? ""
        _name = State(initialValue: initial?.name ?? "")
        _peer = State(initialValue: initial?.peer ?? "")
        _manualCaptcha = State(initialValue: initial?.manualCaptcha ?? false)

        _obfProfile = State(initialValue: initial?.obfProfile ?? "none")
        _obfKey = State(initialValue: initial?.obfKey ?? "")
        _obfTimingMsText = State(initialValue: initial.map { $0.obfTimingMs == 0 ? "" : String($0.obfTimingMs) } ?? "")

        _transport = State(initialValue: initial?.transport ?? "udp")
        _mode = State(initialValue: initial?.mode ?? "udp")
        _bond = State(initialValue: initial?.bond ?? false)

        _threadsText = State(initialValue: initial.map { $0.threads == 0 ? "" : String($0.threads) } ?? "")
        _streamsPerCredText = State(initialValue: initial.map { $0.streamsPerCred == 0 ? "" : String($0.streamsPerCred) } ?? "")

        _dnsMode = State(initialValue: initial?.dnsMode ?? "auto")
        _dns = State(initialValue: initial?.dns ?? "")

        let turnHost = initial?.turnHost ?? ""
        let turnPort = initial?.turnPort ?? ""
        _turnEndpoint = State(initialValue: turnHost.isEmpty && turnPort.isEmpty ? "" : "\(turnHost):\(turnPort)")
        _listen = State(initialValue: initial?.listen ?? "")
        _debug = State(initialValue: initial?.debug ?? false)
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

                    obfuscationSection
                    connectionSection
                    performanceSection
                    dnsSection
                    otherSection
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Редактирование" : "Новая конфигурация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Иконки вместо текста — «Отмена»/«Сохранить» в тулбаре сжимали
                // длинный тайтл шита в эллипсис.
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Image(systemName: "checkmark")
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: – Обфускация

    private var obfuscationSection: some View {
        section(title: "Обфускация", icon: "theatermasks") {
            VStack(alignment: .leading, spacing: 4) {
                Label("Профиль", systemImage: "eye.slash")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Профиль", selection: $obfProfile) {
                    Text("Нет").tag("none")
                    Text("rtpopus").tag("rtpopus")
                    Text("rtpopus2").tag("rtpopus2")
                }
                .pickerStyle(.segmented)
            }

            LabeledField(title: "Ключ обфускации", icon: "key.fill",
                         placeholder: "64 hex символа, если профиль не «Нет»", text: $obfKey,
                         keyboard: .asciiCapable, error: obfKeyError)

            if mode == "udp" {
                LabeledField(title: "Тайминг (мс)", icon: "timer",
                             placeholder: "0 по умолчанию", text: $obfTimingMsText,
                             keyboard: .numberPad, error: obfTimingMsError)
            }
        }
    }

    // MARK: – Соединение

    private var connectionSection: some View {
        section(title: "Соединение", icon: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 4) {
                Label("Транспорт TURN", systemImage: "arrow.left.arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Транспорт", selection: $transport) {
                    Text("UDP").tag("udp")
                    Text("TCP").tag("tcp")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("Режим прокси", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Режим", selection: $mode) {
                    Text("WireGuard (UDP)").tag("udp")
                    Text("Xray (TCP)").tag("tcp")
                }
                .pickerStyle(.segmented)
            }

            if mode == "tcp" {
                Toggle(isOn: $bond) {
                    Label("Bond", systemImage: "link.circle")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .tint(.green)
                .padding(.trailing, 2)
            }

            Toggle(isOn: $manualCaptcha) {
                Label("Решать капчу вручную", systemImage: "checkmark.shield")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .tint(.green)
            .padding(.trailing, 2)
        }
    }

    // MARK: – Производительность

    private var performanceSection: some View {
        section(title: "Производительность", icon: "speedometer") {
            LabeledField(title: "Потоков на TURN (-n)", icon: "square.stack.3d.up",
                         placeholder: "10 по умолчанию", text: $threadsText,
                         keyboard: .numberPad)

            LabeledField(title: "Стримов на учётку", icon: "person.3",
                         placeholder: "10 по умолчанию", text: $streamsPerCredText,
                         keyboard: .numberPad)
        }
    }

    // MARK: – DNS

    private var dnsSection: some View {
        section(title: "DNS", icon: "network") {
            VStack(alignment: .leading, spacing: 4) {
                Label("Режим", systemImage: "network")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Режим DNS", selection: $dnsMode) {
                    Text("Авто").tag("auto")
                    Text("Обычный").tag("plain")
                    Text("DoH").tag("doh")
                }
                .pickerStyle(.segmented)
            }

            LabeledField(title: "DNS-серверы", icon: "network",
                         placeholder: "8.8.8.8, 1.1.1.1 — по умолчанию, если пусто", text: $dns,
                         keyboard: .numbersAndPunctuation, error: dnsError)
        }
    }

    // MARK: – Прочее

    private var otherSection: some View {
        section(title: "Прочее", icon: "ellipsis.circle") {
            LabeledField(title: "Альтернативный TURN-узел", icon: "server.rack",
                         placeholder: "1.2.3.4:56000 — необязательно", text: $turnEndpoint,
                         keyboard: .asciiCapable, error: turnEndpointError)

            LabeledField(title: "Локальный адрес", icon: "antenna.radiowaves.left.and.right",
                         placeholder: "127.0.0.1:9000 по умолчанию", text: $listen,
                         keyboard: .asciiCapable, error: listenError)

            Toggle(isOn: $debug) {
                Label("Подробный лог ядра", systemImage: "ladybug")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .tint(.green)
            .padding(.trailing, 2)
        }
    }

    private func section<Content: View>(
        title: String, icon: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            VStack(spacing: 12) { content() }
                .padding(.top, 8)
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    // MARK: – Trimming helpers

    private var trimName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimPeer: String { peer.trimmingCharacters(in: .whitespaces) }
    private var trimObfKey: String { obfKey.trimmingCharacters(in: .whitespaces) }
    private var trimDns: String { dns.trimmingCharacters(in: .whitespaces) }
    private var trimListen: String { listen.trimmingCharacters(in: .whitespaces) }
    private var trimTurnEndpoint: String { turnEndpoint.trimmingCharacters(in: .whitespaces) }

    // host:port → (host, port), та же логика разбора, что в Validators.endpoint
    // (последнее двоеточие). Вызывать только когда endpoint уже валиден.
    private var turnHostPort: (host: String, port: String)? {
        guard let sep = trimTurnEndpoint.lastIndex(of: ":") else { return nil }
        return (String(trimTurnEndpoint[trimTurnEndpoint.startIndex..<sep]),
                String(trimTurnEndpoint[trimTurnEndpoint.index(after: sep)...]))
    }

    // MARK: – Валидация

    private var highlightEmpty: Bool { prefilled }

    private var nameError: String? {
        guard trimName.isEmpty else { return nil }
        return highlightEmpty ? "Укажите название" : nil
    }
    private var peerError: String? {
        guard !trimPeer.isEmpty else { return highlightEmpty ? "Укажите адрес сервера" : nil }
        return Validators.endpoint(trimPeer) ? nil : "Формат адрес:порт, напр. 1.2.3.4:56000"
    }
    private var obfKeyError: String? {
        guard !trimObfKey.isEmpty else { return nil }
        return Validators.hexKey(trimObfKey) ? nil : "64 hex-символа (0–9, a–f)"
    }
    private var obfTimingMsError: String? {
        guard !obfTimingMsText.isEmpty else { return nil }
        guard let v = Int(obfTimingMsText), v >= 0 else { return "Целое число ≥ 0" }
        return nil
    }
    private var dnsError: String? {
        guard !trimDns.isEmpty else { return nil }
        return Validators.dnsServers(trimDns) ? nil : "IPv4 через запятую, напр. 8.8.8.8, 1.1.1.1"
    }
    private var listenError: String? {
        guard !trimListen.isEmpty else { return nil }
        return Validators.endpoint(trimListen) ? nil : "Формат адрес:порт, напр. 127.0.0.1:9000"
    }
    private var turnEndpointError: String? {
        guard !trimTurnEndpoint.isEmpty else { return nil }
        return Validators.endpoint(trimTurnEndpoint) ? nil : "Формат адрес:порт, напр. 1.2.3.4:56000"
    }
    private var threadsError: String? {
        guard !threadsText.isEmpty else { return nil }
        guard let v = Int(threadsText), v >= 0 else { return "Целое число ≥ 0" }
        return nil
    }
    private var streamsPerCredError: String? {
        guard !streamsPerCredText.isEmpty else { return nil }
        guard let v = Int(streamsPerCredText), v >= 0 else { return "Целое число ≥ 0" }
        return nil
    }

    private var canSave: Bool {
        !trimName.isEmpty && Validators.endpoint(trimPeer)
            && obfKeyError == nil && obfTimingMsError == nil
            && dnsError == nil && listenError == nil
            && turnEndpointError == nil
            && threadsError == nil && streamsPerCredError == nil
    }

    private func save() {
        let turnHostPort = turnHostPort
        let c = SavedConfig(
            name: trimName, peer: trimPeer, obfKey: trimObfKey,
            dns: trimDns, listen: trimListen,
            transport: transport, manualCaptcha: manualCaptcha,
            obfProfile: obfProfile, obfTimingMs: Int(obfTimingMsText) ?? 0,
            mode: mode, bond: bond,
            threads: Int(threadsText) ?? 0, streamsPerCred: Int(streamsPerCredText) ?? 0,
            dnsMode: dnsMode, turnHost: turnHostPort?.host ?? "", turnPort: turnHostPort?.port ?? "",
            debug: debug, clientId: clientId
        )
        onSave(c)
        dismiss()
    }
}
