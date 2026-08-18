import SwiftUI
import UIKit

// SwiftUI Text.textSelection(.enabled) на тысячах строк лога рендерит
// выделение криво (не подсвечивает выбранное) и вешает контекстное меню
// Copy/Share под всем контейнером, а не рядом с выделением — известное
// ограничение на больших многострочных Text. UITextView даёт нормальное
// нативное выделение бесплатно.
struct SelectableLogText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.isScrollEnabled = true
        v.backgroundColor = .clear
        v.font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .regular)
        v.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        v.dataDetectorTypes = []
        v.text = text
        return v
    }

    // Пока у пользователя активно выделение — не трогаем text и не скроллим:
    // логи обновляются раз в 0.5с, и без этой проверки любое выделение
    // рвалось бы прежде, чем успеваешь нажать «Скопировать».
    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.selectedRange.length == 0 else { return }
        guard uiView.text != text else { return }
        uiView.text = text
        let bottom = max(0, uiView.contentSize.height - uiView.bounds.height + uiView.contentInset.bottom)
        uiView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    }
}
