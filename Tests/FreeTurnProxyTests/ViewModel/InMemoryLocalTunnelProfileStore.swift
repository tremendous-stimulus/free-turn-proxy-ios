import Foundation
@testable import FreeTurnProxy

final class InMemoryLocalTunnelProfileStore: LocalTunnelProfileStoring {
    private var storage: [UUID: LocalTunnelProfile] = [:]

    func save(_ profile: LocalTunnelProfile) { storage[profile.id] = profile }
    func load(_ id: UUID) -> LocalTunnelProfile? { storage[id] }
    func delete(_ id: UUID) { storage[id] = nil }
}
