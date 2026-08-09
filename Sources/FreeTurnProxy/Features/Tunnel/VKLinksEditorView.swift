import SwiftUI

// Редактор пула VK-ссылок: количество для генерации, кнопка генерации и
// построчный ручной редактор (добавить/убрать/поправить конкретную ссылку).
// Черновик — изменения применяются к TunnelViewModel.links только по
// «Сохранить», как и в ConfigEditorView.
struct VKLinksEditorView: View {
    private static let linkPlaceholder = "https://vk.com/call/join/…"

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: TunnelViewModel
    let onSave: ([String]) -> Void

    @State private var linkCount: Int
    @State private var links: [String]

    init(initialLinks: [String], vm: TunnelViewModel, onSave: @escaping ([String]) -> Void) {
        self.vm = vm
        self.onSave = onSave
        _links = State(initialValue: initialLinks.isEmpty ? [""] : initialLinks)
        _linkCount = State(initialValue: max(1, initialLinks.count))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    generateBlock
                    linksList
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("VK-ссылки")
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
            .sheet(isPresented: $vm.showVKWebFallback) {
                VKAuthSheet { token in
                    vm.vkAuthToken = token
                    Task { await generate() }
                }
            }
        }
    }

    // MARK: – Генерация

    private var generateBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $linkCount, in: 1...20) {
                Label("Количество ссылок: \(linkCount)", systemImage: "number")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await generate() }
            } label: {
                HStack(spacing: 6) {
                    if vm.creatingCall { ProgressView() }
                    Text("Сгенерировать")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(vm.creatingCall)
        }
    }

    private func generate() async {
        guard let result = await vm.generateLinkBatch(count: linkCount) else { return }
        links = result
    }

    // MARK: – Построчный редактор

    private var linksList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ссылки", systemImage: "link")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(links.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        // placeholder — через переменную String, не литерал: литерал
                        // трактуется как LocalizedStringKey и SwiftUI автолинкует
                        // голый https://-текст в нём синим.
                        TextField(Self.linkPlaceholder, text: $links[i])
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        if let e = linkError(at: i) { FieldError(e) }
                    }
                    if links.count > 1 {
                        Button {
                            links.remove(at: i)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                    }
                }
            }
            Button {
                links.append("")
            } label: {
                Label("Ещё ссылка", systemImage: "plus.circle")
                    .font(.footnote)
            }
        }
    }

    private func linkError(at index: Int) -> String? {
        guard links.indices.contains(index) else { return nil }
        let s = links[index].trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        return Validators.vkLink(s) ? nil : "Ссылка вида https://vk.com/call/join/…"
    }

    private var canSave: Bool {
        links.indices.allSatisfy { linkError(at: $0) == nil }
    }

    private func save() {
        let filtered = links
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onSave(filtered)
        dismiss()
    }
}
