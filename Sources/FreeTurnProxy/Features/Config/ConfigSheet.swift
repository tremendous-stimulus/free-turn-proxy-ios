import SwiftUI

// Двухшаговый поток внутри одного sheet: ввод названия → экран экспорта.
struct ConfigSheet: View {
    @ObservedObject var vm: ConfigViewModel

    var body: some View {
        NavigationStack {
            NameStep(vm: vm)
                .navigationDestination(isPresented: $vm.showExport) {
                    if let url = vm.exportURL {
                        ExportStep(url: url, onClose: vm.closeSheet)
                    }
                }
        }
        .presentationDetents([.large])
    }
}

private struct NameStep: View {
    @ObservedObject var vm: ConfigViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Название туннеля", systemImage: "character.cursor.ibeam")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("tunnel", text: $vm.tunnelName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .focused($focused)
                }

                if let error {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                Button {
                    loading = true
                    error = nil
                    vm.generate { err in
                        loading = false
                        error = err
                    }
                } label: {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Продолжить", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(loading || vm.tunnelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Новый туннель")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
        .onAppear { focused = true }
    }
}
