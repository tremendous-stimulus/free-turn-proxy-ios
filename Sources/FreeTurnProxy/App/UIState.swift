import Foundation

// Глобальный реестр текущей вкладки. ProxyManager использует это, чтобы решить,
// слать ли пуш о статусе туннеля: если вкладка «Туннель» открыта и приложение
// активно — пользователь и так видит UI, дублировать пушем нет смысла.
enum UIState {
    static let tunnelTabTag = 0
    static var currentTab: Int = tunnelTabTag
}
