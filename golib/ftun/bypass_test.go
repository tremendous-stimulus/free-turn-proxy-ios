package ftun

import (
	"net/netip"
	"testing"
)

// Пустой список — весь трафик в туннель: это поведение фазы 1, на нём живут
// старые конфиги, и никаких «диапазонов по умолчанию» тут быть не должно.
func TestBypassSet_EmptyRoutesEverythingToTunnel(t *testing.T) {
	set := NewBypassSet(nil, nil)
	for _, ip := range []string{"10.1.2.3", "192.168.1.1", "8.8.8.8"} {
		if set.Contains(netip.MustParseAddr(ip)) {
			t.Errorf("%s не должен обходить туннель при пустом списке", ip)
		}
	}
}

// Сеть самого VPN-сервера обычно приватная — она обязана остаться в туннеле,
// даже когда приватные диапазоны целиком отправлены в обход.
func TestBypassSet_ExcludeBeatsInclude(t *testing.T) {
	set := NewBypassSet([]string{"10.0.0.0/8"}, []string{"10.8.0.0/24"})
	if set.Contains(netip.MustParseAddr("10.8.0.1")) {
		t.Error("сеть VPN-сервера обязана идти через туннель")
	}
	if !set.Contains(netip.MustParseAddr("10.9.0.1")) {
		t.Error("остальное приватное должно обходить туннель")
	}
}

func TestBypassSet_PublicAddressGoesToTunnel(t *testing.T) {
	set := NewBypassSet([]string{"192.168.0.0/16"}, nil)
	for _, ip := range []string{"8.8.8.8", "1.1.1.1", "185.202.207.126"} {
		if set.Contains(netip.MustParseAddr(ip)) {
			t.Errorf("%s не должен обходить туннель", ip)
		}
	}
}

func TestBypassSet_ExtraCIDRsAndBareAddresses(t *testing.T) {
	set := NewBypassSet([]string{"87.240.128.0/18", "93.186.225.194"}, nil)
	if !set.Contains(netip.MustParseAddr("87.240.190.1")) {
		t.Error("адрес из добавленной подсети должен обходить туннель")
	}
	if !set.Contains(netip.MustParseAddr("93.186.225.194")) {
		t.Error("голый адрес должен трактоваться как /32")
	}
	if set.Contains(netip.MustParseAddr("87.241.0.1")) {
		t.Error("соседняя подсеть не должна попадать в обход")
	}
}

// Список подсетей приезжает из сети — одна кривая строка не должна валить старт.
func TestBypassSet_MalformedEntriesIgnored(t *testing.T) {
	set := NewBypassSet([]string{"не-адрес", "", "10.0.0.0/99", "8.8.8.8/32"}, nil)
	if !set.Contains(netip.MustParseAddr("8.8.8.8")) {
		t.Error("валидная запись после кривых должна быть учтена")
	}
}

func TestDestination_IPv4(t *testing.T) {
	pkt := make([]byte, 20)
	pkt[0] = 0x45
	copy(pkt[16:20], []byte{192, 168, 1, 7})
	dst, ok := destination(pkt)
	if !ok || dst != netip.MustParseAddr("192.168.1.7") {
		t.Fatalf("получили %v (ok=%v)", dst, ok)
	}
}

func TestDestination_IPv6(t *testing.T) {
	pkt := make([]byte, 40)
	pkt[0] = 0x60
	copy(pkt[24:40], netip.MustParseAddr("2001:db8::1").AsSlice())
	dst, ok := destination(pkt)
	if !ok || dst != netip.MustParseAddr("2001:db8::1") {
		t.Fatalf("получили %v (ok=%v)", dst, ok)
	}
}

func TestDestination_TruncatedAndUnknown(t *testing.T) {
	if _, ok := destination([]byte{0x45, 0x00}); ok {
		t.Error("обрезанный IPv4 не должен разбираться")
	}
	if _, ok := destination(nil); ok {
		t.Error("пустой пакет не должен разбираться")
	}
	if _, ok := destination(make([]byte, 20)); ok {
		t.Error("неизвестная версия IP не должна разбираться")
	}
}

// Роутер без стека обхода обязан вести себя как pass-through фазы 1 —
// иначе старые конфиги (bypass-set пуст) поехали бы в никуда.
func TestRouter_WithoutStack_NeverBypasses(t *testing.T) {
	r := newRouter(newEndpoint("a", 1280), newEndpoint("b", 1280), NewBypassSet(nil, nil), nil)
	pkt := make([]byte, 20)
	pkt[0] = 0x45
	copy(pkt[16:20], []byte{192, 168, 1, 7})
	if r.routesBypass(newRouteCache(), pkt) {
		t.Error("без стека обхода маршрутизация невозможна")
	}
}
