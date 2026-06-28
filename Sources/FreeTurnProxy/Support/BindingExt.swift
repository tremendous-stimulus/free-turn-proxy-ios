import SwiftUI

extension Binding {
    static func isNotNil<T>(_ source: Binding<T?>) -> Binding<Bool> where Value == Bool {
        Binding<Bool>(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}
