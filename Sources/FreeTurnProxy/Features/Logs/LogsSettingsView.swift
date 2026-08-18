import SwiftUI

struct LogsSettingsView: View {
    @AppStorage(DefaultsKeys.telemetryEnabled) private var telemetryEnabled = true
    @AppStorage(DefaultsKeys.persistLogs) private var persistLogs = false
    @AppStorage(DefaultsKeys.logsMinLevel) private var logsMinLevel = ErrorLogger.LogLevel.wrn.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $telemetryEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Отправлять диагностику")
                            Text("Анонимные технические логи помогают находить и исправлять сбои подключения. Личные данные не передаются.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)

                    Toggle(isOn: $persistLogs) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Сохранять логи между подключениями")
                            Text("По умолчанию буфер очищается при каждом новом подключении.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker("Уровень логов", selection: $logsMinLevel) {
                        ForEach(ErrorLogger.LogLevel.allCases) { level in
                            Text(level.title).tag(level.rawValue)
                        }
                    }
                } footer: {
                    // Фильтр влияет только на то, что показывается на экране —
                    // в телеметрию по-прежнему уходят все уровни.
                    Text("Что показывать на экране логов. На отправляемую диагностику не влияет.")
                }
            }
            .navigationTitle("Настройки логов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
