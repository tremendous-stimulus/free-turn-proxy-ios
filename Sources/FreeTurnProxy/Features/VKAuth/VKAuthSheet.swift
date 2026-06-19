import SwiftUI
import WebKit

// VK OAuth через WKWebView: грузим oauth.vk.com/authorize (implicit flow),
// перехватываем редирект на oauth.vk.com/blank.html и достаём access_token
// из фрагмента URL.
//
// Почему WKWebView, а не ASWebAuthenticationSession:
// .https-колбэк (iOS 17.4+) требует Associated Domains entitlement на домен
// редиректа (oauth.vk.com) — а этим доменом владеет VK, не мы, настроить
// associated domain невозможно, и сессия падает мгновенно. Кастомную схему
// VK для client_id 7793118 не принимает. Единственный рабочий путь —
// перехват навигации внутри WKWebView через navigationDelegate.

let vkOAuthURL = URL(string:
    "https://oauth.vk.com/authorize" +
    "?client_id=7793118" +
    "&scope=video" +
    "&redirect_uri=https://oauth.vk.com/blank.html" +
    "&response_type=token" +
    "&display=mobile" +
    "&v=5.131"
)!

private func parseFragment(_ fragment: String) -> [String: String] {
    var params: [String: String] = [:]
    for pair in fragment.split(separator: "&") {
        let kv = pair.split(separator: "=", maxSplits: 1)
        if kv.count == 2 { params[String(kv[0])] = String(kv[1]) }
    }
    return params
}

struct VKAuthSheet: View {
    let onToken: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VKWebView(url: vkOAuthURL) { token in
                onToken(token)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Войти в VK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

private struct VKWebView: UIViewRepresentable {
    let url: URL
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(authorizeURL: url, onToken: onToken) }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.navigationDelegate = context.coordinator
        context.coordinator.observe(wv)
        wv.load(URLRequest(url: url))
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let authorizeURL: URL
        let onToken: (String) -> Void
        private var fired = false
        private var retriedSilent = false
        private var urlObservation: NSKeyValueObservation?

        init(authorizeURL: URL, onToken: @escaping (String) -> Void) {
            self.authorizeURL = authorizeURL
            self.onToken = onToken
        }

        // Токен ловим во всех колбэках + по KVO на webView.url, т.к. VK может
        // доустанавливать фрагмент через location.hash (same-document навигация,
        // которую decidePolicyFor не видит).
        func observe(_ webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                self?.capture(from: wv.url, webView: wv)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, accessToken(from: url) != nil {
                decisionHandler(.cancel)
                capture(from: url, webView: webView)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            capture(from: webView.url, webView: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            capture(from: webView.url, webView: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            capture(from: webView.url, webView: webView)
        }

        private func capture(from url: URL?, webView: WKWebView) {
            guard !fired, let url else { return }

            // Прямой access_token (тёплый флоу) — финал.
            if let token = accessToken(from: url) {
                fired = true
                webView.stopLoading()
                onToken(token)
                return
            }

            // Холодный VK ID логин отдаёт silent_token — обменять его без
            // service-токена приложения нельзя. Но куки сессии уже выставлены,
            // поэтому один раз перезагружаем authorize: второй проход идёт
            // "тёплым" и возвращает прямой access_token.
            if !retriedSilent, isSilentToken(url) {
                retriedSilent = true
                webView.stopLoading()
                let authorizeURL = self.authorizeURL
                DispatchQueue.main.async { webView.load(URLRequest(url: authorizeURL)) }
            }
        }

        private func accessToken(from url: URL) -> String? {
            if let f = url.fragment, let t = parseFragment(f)["access_token"] { return t }
            if let q = url.query, let t = parseFragment(q)["access_token"] { return t }
            return nil
        }

        private func isSilentToken(_ url: URL) -> Bool {
            guard let f = url.fragment, let decoded = f.removingPercentEncoding else { return false }
            return decoded.contains("silent_token")
        }
    }
}
