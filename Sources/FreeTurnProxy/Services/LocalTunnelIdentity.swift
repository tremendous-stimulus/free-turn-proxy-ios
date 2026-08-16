import Foundation
import CryptoKit

struct WGKeyPair: Equatable {
    let privateKeyBase64: String
    let publicKeyBase64: String
}

// Генерация X25519-пар для локального туннеля (план, фаза 2 — две пары на
// профиль: локальный responder и клиент, см. LocalTunnelProfileFactory).
// В отличие от ClientIdentity (случайные байты для идентификатора без
// криптографического смысла), здесь нужен настоящий WireGuard-совместимый
// keypair — CryptoKit единственный источник X25519 в проекте.
enum LocalTunnelIdentity {
    static func generateKeyPair() -> WGKeyPair {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return WGKeyPair(
            privateKeyBase64: priv.rawRepresentation.base64EncodedString(),
            publicKeyBase64: priv.publicKey.rawRepresentation.base64EncodedString()
        )
    }
}
