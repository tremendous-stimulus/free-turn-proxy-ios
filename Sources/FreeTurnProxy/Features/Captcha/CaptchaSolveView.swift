import SwiftUI
import WebKit

// Экран ручного решения captcha — прозрачный WebView на весь экран поверх
// затемнённого приложения. Фон VK-страницы гасим CSS, остаётся только сам
// виджет. Закрытие детектим внутри страницы (JS): тап по крестику карточки или
// в любом месте вне модальной карточки VK шлёт captchaClose. WebView на весь
// экран — чтобы ловить тапы и в верхней части. При успехе Go закрывает оверлей
// сам (hide); закрыли не решив — вернуть кнопкой «Показать капчу».
struct CaptchaSolveView: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            CaptchaWebView(url: url, onClose: onClose)
                .ignoresSafeArea()
        }
        .transition(.opacity)
    }
}

private struct CaptchaWebView: UIViewRepresentable {
    let url: URL
    let onClose: () -> Void

    private static let closeMessage = "captchaClose"

    // VK Smart Captcha — VKUI-разметка: карточка vkc__ModalCard-module__host
    // (внутри — чекбокс/слайдер и крестик vkc__ModalCardBase-module__dismiss),
    // вокруг — фон vkc__VisuallyHiddenModalOverlay. Закрываем по крестику и по
    // тапу вне карточки; внутри карточки тап не трогаем (решение captcha).
    private static let injectedJS = """
    (function(){
      var s=document.createElement('style');
      s.innerHTML='html,body{background:transparent !important;background-color:transparent !important;}';
      document.documentElement.appendChild(s);
      function close(){ try{ window.webkit.messageHandlers.\(closeMessage).postMessage(1);}catch(e){} }
      document.addEventListener('click', function(e){
        var t=e.target;
        if(!t||!t.closest) return;
        if(t.closest('[class*="ModalCardBase-module__dismiss"]')){ close(); return; }
        if(!t.closest('[class*="ModalCard-module__host"]')){ close(); return; }
      }, true);
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onClose: onClose) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let script = WKUserScript(source: Self.injectedJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: Self.closeMessage)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: closeMessage)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let url: URL
        private let onClose: () -> Void
        private var retries = 0
        private let maxRetries = 15

        init(url: URL, onClose: @escaping () -> Void) {
            self.url = url
            self.onClose = onClose
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            DispatchQueue.main.async { self.onClose() }
        }

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
