import SwiftUI
import WebKit

// Экран ручного решения captcha — оверлей поверх затемнённого приложения (не
// full-screen sheet, иначе VK-виджет на своём белом фоне выглядел как попап на
// попапе). WebView прозрачный + CSS гасит фон VK-страницы, так что над
// приложением висит только сам виджет. При успехе Go закрывает оверлей сам
// (hide -> isPresented=false). Крестик просто прячет — Go-решатель добивается
// своего таймаута, а вернуть окно можно кнопкой «Открыть captcha».
struct CaptchaSolveView: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    Text("Captcha")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 4)

                CaptchaWebView(url: url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 520)
            }
            .padding(20)
        }
        .transition(.opacity)
    }
}

private struct CaptchaWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Гасим фон VK-страницы, чтобы остался только сам виджет captcha поверх
        // приложения. forMainFrameOnly:false — виджет может жить в iframe.
        let css = "html,body,#root,#app,#app-root{background:transparent !important;background-color:transparent !important;}"
        let js = "var s=document.createElement('style');s.innerHTML='\(css)';document.documentElement.appendChild(s);"
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
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
