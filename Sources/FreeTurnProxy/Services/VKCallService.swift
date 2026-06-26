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
        struct Inner: Decodable {
            let joinLink: String?
            enum CodingKeys: String, CodingKey { case joinLink = "join_link" }
        }
        struct VKError: Decodable {
            let errorCode: Int
            let errorMsg: String
            enum CodingKeys: String, CodingKey { case errorCode = "error_code"; case errorMsg = "error_msg" }
        }
        let response: Inner?
        let error: VKError?
    }
    let resp = try JSONDecoder().decode(Resp.self, from: data)
    if let e = resp.error { throw VKCallError.apiError(e.errorCode, e.errorMsg) }
    guard let link = resp.response?.joinLink else { throw VKCallError.noLink }
    return link
}
