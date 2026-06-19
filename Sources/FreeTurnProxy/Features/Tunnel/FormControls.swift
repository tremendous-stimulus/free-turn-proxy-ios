import SwiftUI

// Поле ввода с подписью и опциональной ошибкой формата.
struct LabeledField: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
            if let error { FieldError(error) }
        }
    }
}

struct FieldError: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
