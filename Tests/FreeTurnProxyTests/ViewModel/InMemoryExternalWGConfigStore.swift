import Foundation
@testable import FreeTurnProxy

final class InMemoryExternalWGConfigStore: ExternalWGConfigStoring {
    private var stored: [UUID: ExternalWGConfig] = [:]

    func save(_ config: ExternalWGConfig, for profileID: UUID) { stored[profileID] = config }
    func load(for profileID: UUID) -> ExternalWGConfig? { stored[profileID] }
    func delete(for profileID: UUID) { stored[profileID] = nil }
}
