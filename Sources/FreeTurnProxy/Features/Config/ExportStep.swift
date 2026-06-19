import SwiftUI
import UIKit

// Экран после генерации: объясняет, как загрузить конфиг в AmneziaWG/WireGuard,
// и даёт сохранить файл в Файлы либо отправить через share sheet.
struct ExportStep: View {
    let url: URL
    let onClose: () -> Void

    @State private var showShare = false
    @State private var showSave = false

    private let steps = [
        "Нажмите кнопку «Поделиться» справа.",
        "В списке выберите AmneziaWG. Если её нет — пролистайте вправо, нажмите «Ещё» и включите её звёздочкой (это нужно один раз).",
        "В AmneziaWG появится новое подключение — включите его.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Конфиг готов. Осталось загрузить его в приложение-VPN.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(steps.indices, id: \.self) { i in
                            stepRow(number: i + 1, text: steps[i])
                        }
                    }

                    Divider()

                    Label {
                        Text("Либо нажмите «Сохранить конфиг», выберите папку, а потом в AmneziaWG: + → «Импорт из файла».")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }

            buttons.padding()
        }
        .navigationTitle("Загрузка конфига")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { onClose() }
            }
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: [url]) }
        .sheet(isPresented: $showSave) { DocumentExporter(url: url) }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.blue.opacity(0.12))
                .clipShape(Circle())
                .foregroundStyle(.blue)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button { showSave = true } label: {
                Label("Сохранить конфиг", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
