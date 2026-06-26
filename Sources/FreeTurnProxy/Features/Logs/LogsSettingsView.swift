import SwiftUI

struct LogsSettingsView: View {
    @AppStorage(DefaultsKeys.telemetryEnabled) private var telemetryEnabled = true
    @AppStorage(DefaultsKeys.persistLogs) private var persistLogs = false
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
