import Foundation

enum VKCallError: LocalizedError {
    case network(Error)
    case apiError(Int, String)
    case noLink

    var errorDescription: String? {
        switch self {
        case .network(let e):         return "Сеть: \(e.localizedDescription)"
        case .apiError(let c, let m): return "VK error \(c): \(m)"
        case .noLink:                 return "VK не вернул ссылку на звонок"
        }
    }
}

func vkCreateCall(token: String) async throws -> String {
    var comps = URLComponents(string: "https://api.vk.com/method/calls.start")!
    comps.queryItems = [
        .init(name: "access_token", value: token),
        .init(name: "v", value: "5.131"),
    ]
    let data: Data
    do { (data, _) = try await URLSession.shared.data(from: comps.url!) }
    catch { throw VKCallError.network(error) }

    struct Resp: Decodable {
        struct Inner: Decodable { let join_link: String? }
        struct VKError: Decodable { let error_code: Int; let error_msg: String }
        let response: Inner?
        let error: VKError?
    }
    let resp = try JSONDecoder().decode(Resp.self, from: data)
    if let e = resp.error { throw VKCallError.apiError(e.error_code, e.error_msg) }
    guard let link = resp.response?.join_link else { throw VKCallError.noLink }
    return link
}
