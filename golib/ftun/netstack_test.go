package ftun

import (
	"net"
	"testing"
	"time"
)

// Регрессия: один живой idle-релей вешал Close() навсегда — io.Copy не
// разблокируется ни отменой контекста, ни закрытием link-endpoint'а, а зовут
// Close() с главного потока приложения.
func TestBypassStack_CloseUnblocksIdleRelay(t *testing.T) {
	b, err := newBypassStack(1280, nil)
	if err != nil {
		t.Fatalf("newBypassStack: %v", err)
	}

	// Пара net.Pipe молчит и не имеет таймаутов — тот же тупик, что даёт
	// открытый, но простаивающий TCP-коннект.
	localA, localB := net.Pipe()
	remoteA, remoteB := net.Pipe()
	defer localB.Close()
	defer remoteB.Close()

	if !b.addConns(localA, remoteA) {
		t.Fatal("addConns на живом стеке обязан регистрировать соединения")
	}
	b.wg.Add(1)
	go func() {
		defer b.wg.Done()
		defer b.removeConns(localA, remoteA)
		relay(localA, remoteA)
	}()

	done := make(chan struct{})
	go func() {
		b.Close()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Close() не вернулся при живом релее")
	}
}

// После закрытия регистрация обязана отказывать и сама закрывать соединения,
// иначе релей, дозвонившийся во время Close(), переживёт стек.
func TestBypassStack_AddConnsAfterCloseClosesThem(t *testing.T) {
	b, err := newBypassStack(1280, nil)
	if err != nil {
		t.Fatalf("newBypassStack: %v", err)
	}
	b.Close()

	c, peer := net.Pipe()
	defer peer.Close()
	if b.addConns(c) {
		t.Fatal("addConns после Close() обязан вернуть false")
	}
	// Чтение из закрытой половины net.Pipe возвращает ошибку сразу, без
	// таймаута — если бы addConns не закрыл её, вызов бы заблокировался.
	if _, err := c.Read(make([]byte, 1)); err == nil {
		t.Fatal("соединение должно быть закрыто")
	}
}
