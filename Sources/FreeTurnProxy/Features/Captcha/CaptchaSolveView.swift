import SwiftUI
import WebKit

// Экран ручного решения captcha — прозрачный WebView на весь экран поверх
// затемнённого приложения. Фон VK-страницы гасим CSS, остаётся только виджет.
// Закрытие детектим внутри страницы (JS): тап вне блока captcha или по крестику
// шлёт captchaClose.
//
// DEBUG-захват: страница также шлёт полный outerHTML (captchaDOM) и описание
// тапнутого элемента (captchaTap) — Swift пишет это в Documents (видно в Files
// app), чтобы выгрузить живой DOM с реального устройства и подогнать селекторы.
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

    private static let mClose = "captchaClose"
    private static let mDOM = "captchaDOM"
    private static let mTap = "captchaTap"

    private static let injectedJS = """
    (function(){
      var s=document.createElement('style');
      s.innerHTML='html,body{background:transparent !important;background-color:transparent !important;}';
      document.documentElement.appendChild(s);

      function send(name,obj){ try{ window.webkit.messageHandlers[name].postMessage(obj);}catch(e){} }
      function desc(el){ if(!el||!el.tagName) return String(el);
        var c=(el.className&&el.className.toString)?el.className.toString().trim():'';
        return el.tagName.toLowerCase()+(el.id?('#'+el.id):'')+(c?('.'+c.split(/\\s+/).join('.')):''); }
      function path(el){ var a=[],n=0; while(el&&n<14){ a.push(desc(el)); el=el.parentElement; n++; } return a; }

      // Полный DOM после рендера виджета.
      setTimeout(function(){ send('\(mDOM)', document.documentElement.outerHTML); }, 1500);

      document.addEventListener('click', function(e){
        var t=e.target;
        send('\(mTap)', JSON.stringify({target: desc(t), path: path(t)}));
        if(t && t.closest){
          if(t.closest('[class*="close" i],[aria-label*="close" i],[aria-label*="закры" i]')){ send('\(mClose)',1); return; }
          if(!t.closest('iframe,canvas,button,form,[class*="captcha" i],[id*="captcha" i],[class*="vkc" i],[class*="slider" i],[class*="checkbox" i]')){ send('\(mClose)',1); return; }
        }
      }, true);
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onClose: onClose) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let script = WKUserScript(source: Self.injectedJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        for name in [Self.mClose, Self.mDOM, Self.mTap] {
            config.userContentController.add(context.coordinator, name: name)
        }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        let ucc = uiView.configuration.userContentController
        for name in [mClose, mDOM, mTap] { ucc.removeScriptMessageHandler(forName: name) }
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
            switch message.name {
            case CaptchaWebView.mClose:
                DispatchQueue.main.async { self.onClose() }
            case CaptchaWebView.mDOM:
                CaptchaDebug.writeDOM(String(describing: message.body))
            case CaptchaWebView.mTap:
                CaptchaDebug.appendTap(String(describing: message.body))
            default:
                break
            }
        }

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

// DEBUG: пишем живой DOM/тапы captcha в Documents (видно в Files app) — чтобы
// выгрузить с реального устройства. Временное, убрать после подгонки селекторов.
private enum CaptchaDebug {
    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func writeDOM(_ html: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let header = "<!-- captcha DOM @ \(stamp) -->\n"
        try? (header + html).write(to: dir.appendingPathComponent("captcha-dom.html"),
                                   atomically: true, encoding: .utf8)
    }

    static func appendTap(_ json: String) {
        let line = ISO8601DateFormatter().string(from: Date()) + " " + json + "\n"
        let url = dir.appendingPathComponent("captcha-taps.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
