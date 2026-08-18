import Foundation
@testable import FreeTurnProxy

final class InMemoryLocalWGConfigStore: LocalWGConfigStoring {
    private var stored: LocalWGConfig?

    func save(_ config: LocalWGConfig) { stored = config }
    func load() -> LocalWGConfig? { stored }
    func delete() { stored = nil }
}
