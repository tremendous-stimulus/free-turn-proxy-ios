package ftun

import (
	"sync"
	"syscall"
)

// Protector — тот же контракт, что у mobile.Protector апстрима: хост выводит
// сокет из-под системного VPN (на iOS это setsockopt IP_BOUND_IF, см.
// Sources/FreeTurnProxy/Services/SocketProtector.swift). Обход в netstack без
// этого бессмыслен: сокет, которым мы переоткрываем обходное соединение, сам
// уйдёт обратно в туннель — то есть в петлю.
//
// Один и тот же Swift-класс реализует и MobileProtectorProtocol, и
// FtunProtectorProtocol: селектор у них совпадает.
type Protector interface {
	Protect(fd int) bool
}

var (
	protectMu sync.RWMutex
	protector Protector
)

// SetProtect регистрирует протектор. nil — отключить (обход пойдёт обычными
// сокетами, то есть через туннель; полезно только на десктопе и в тестах).
func SetProtect(p Protector) {
	protectMu.Lock()
	defer protectMu.Unlock()
	protector = p
}

// protectControl — Control-функция для net.Dialer/net.ListenConfig.
func protectControl(_, _ string, c syscall.RawConn) error {
	protectMu.RLock()
	p := protector
	protectMu.RUnlock()
	if p == nil {
		return nil
	}
	return c.Control(func(fd uintptr) { p.Protect(int(fd)) })
}
