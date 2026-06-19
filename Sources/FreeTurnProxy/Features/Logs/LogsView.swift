import SwiftUI

struct LogsView: View {
    @StateObject private var vm = LogsViewModel()
    @State private var shareURL: URL?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(vm.logs.isEmpty ? "Логи появятся после подключения" : vm.logs)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .id("bottom")
            }
            .onChange(of: vm.logs) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .navigationTitle("Логи")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    shareURL = vm.exportFile()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(vm.logs.isEmpty)

                Button(role: .destructive) {
                    vm.clear()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: .init(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}
