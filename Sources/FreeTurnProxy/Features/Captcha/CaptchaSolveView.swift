import SwiftUI
import WebKit

// Экран ручного решения captcha. Грузит локальный прокси VK-страницы; при
// успешном решении Go закрывает sheet сам (hide -> request=nil). «Отмена»
// просто прячет окно — Go-решатель добивается своего таймаута.
struct CaptchaSolveView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CaptchaWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Captcha")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
        }
    }
}

private struct CaptchaWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let url: URL
        private var retries = 0
        private let maxRetries = 15

        init(url: URL) { self.url = url }

        // Локальный прокси мог ещё не подняться к моменту первого запроса —
        // ретраим загрузку с короткой паузой несколько раз.
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            retry(webView)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            retry(webView)
        }

        private func retry(_ webView: WKWebView) {
            guard retries < maxRetries else { return }
            retries += 1
            let url = self.url
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak webView] in
                webView?.load(URLRequest(url: url))
            }
        }
    }
}
