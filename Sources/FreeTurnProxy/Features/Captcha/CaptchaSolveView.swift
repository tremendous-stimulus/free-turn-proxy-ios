import SwiftUI
import WebKit

// Экран ручного решения captcha — оверлей поверх затемнённого приложения (не
// full-screen sheet, иначе VK-виджет на своём белом фоне выглядел как попап на
// попапе). WebView прозрачный + CSS гасит фон VK-страницы, так что над
// приложением висит только сам виджет, прижатый к низу экрана. Тап по
// затемнённому фону (видимая часть приложения) прячет оверлей; при успехе Go
// закрывает его сам (hide -> isPresented=false). Вернуть окно, если закрыли не
// решив, можно кнопкой «Открыть captcha».
struct CaptchaSolveView: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Кнопка, а не onTapGesture: у Button хит-тестинг как у UIControl,
            // без арбитража жестов с WebView/TabView (из-за которого одиночный
            // тап «не регистрировался»).
            Button(action: onClose) {
                Color.black.opacity(0.5)
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()

            // Прижато к низу: html-контейнер VK упирается в низ экрана, виджет
            // выезжает снизу и остаётся внизу, а не висит посреди экрана.
            CaptchaWebView(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 600)
                .ignoresSafeArea(edges: .bottom)
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
