package ftun

import (
	"testing"
	"time"
)

// ipv4Packet собирает минимальный корректный IPv4-пакет до указанного адреса.
func ipv4Packet(dst [4]byte) []byte {
	pkt := make([]byte, 20)
	pkt[0] = 0x45
	pkt[9] = 6 // TCP
	copy(pkt[12:16], []byte{10, 8, 0, 2})
	copy(pkt[16:20], dst[:])
	return pkt
}

func newTestRouter(t *testing.T, include, exclude []string) (*router, *endpoint, *endpoint) {
	t.Helper()
	local, remote := newEndpoint("local", 1280), newEndpoint("remote", 1280)
	stk, err := newBypassStack(1280, nil)
	if err != nil {
		t.Fatalf("newBypassStack: %v", err)
	}
	r := newRouter(local, remote, NewBypassSet(include, exclude), stk)
	r.start()
	t.Cleanup(func() {
		local.Close()
		remote.Close()
		r.close()
	})
	return r, local, remote
}

func TestRouter_NonBypassedPacketReachesRemote(t *testing.T) {
	_, local, remote := newTestRouter(t, []string{"192.168.0.0/16"}, nil)

	if _, err := local.Write([][]byte{ipv4Packet([4]byte{8, 8, 8, 8})}, 0); err != nil {
		t.Fatalf("Write: %v", err)
	}
	select {
	case pkt := <-remote.inbound:
		if dst, _ := destination(pkt); dst.String() != "8.8.8.8" {
			t.Fatalf("до внешней половины дошёл пакет на %v", dst)
		}
	case <-time.After(time.Second):
		t.Fatal("пакет вне bypass-set обязан уйти во внешнюю половину")
	}
}

func TestRouter_BypassedPacketDoesNotReachRemote(t *testing.T) {
	_, local, remote := newTestRouter(t, []string{"192.168.0.0/16"}, nil)

	if _, err := local.Write([][]byte{ipv4Packet([4]byte{192, 168, 1, 7})}, 0); err != nil {
		t.Fatalf("Write: %v", err)
	}
	select {
	case pkt := <-remote.inbound:
		dst, _ := destination(pkt)
		t.Fatalf("пакет на %v ушёл в туннель, хотя должен был обойти его", dst)
	case <-time.After(200 * time.Millisecond):
	}
}

// Исключение обязано работать и на живом роутере, не только в BypassSet:
// сеть VPN-сервера приватная, но идти должна через туннель.
func TestRouter_ExcludedPrefixStillReachesRemote(t *testing.T) {
	_, local, remote := newTestRouter(t, []string{"10.0.0.0/8"}, []string{"10.8.0.0/24"})

	if _, err := local.Write([][]byte{ipv4Packet([4]byte{10, 8, 0, 1})}, 0); err != nil {
		t.Fatalf("Write: %v", err)
	}
	select {
	case <-remote.inbound:
	case <-time.After(time.Second):
		t.Fatal("сеть VPN-сервера обязана идти через туннель")
	}
}

// Ответы внешней половины всегда возвращаются в responder, независимо от
// маршрутизации исходящих.
func TestRouter_RemoteRepliesReachLocal(t *testing.T) {
	_, local, remote := newTestRouter(t, []string{"192.168.0.0/16"}, nil)

	if _, err := remote.Write([][]byte{ipv4Packet([4]byte{10, 8, 0, 2})}, 0); err != nil {
		t.Fatalf("Write: %v", err)
	}
	select {
	case <-local.inbound:
	case <-time.After(time.Second):
		t.Fatal("ответ внешней половины не дошёл до responder'а")
	}
}
