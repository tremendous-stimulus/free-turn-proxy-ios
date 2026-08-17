package ftun

import (
	"net/netip"
	"strings"
)

// BypassSet — множество назначений, которые роутер уводит мимо туннеля
// (см. план vpn-lexical-rossum.md, фаза 5.2). Пустое множество = весь трафик
// идёт в туннель, то есть поведение фазы 1 (чистый pass-through).
type BypassSet struct {
	prefixes []netip.Prefix
	excludes []netip.Prefix
}

// NewBypassSet принимает CIDR и голые адреса; неразобранные записи молча
// пропускаются — список приходит из сети (подсети VK), и одна кривая строка
// не должна валить старт туннеля.
//
// exclude перебивает include и нужен обязательно: сеть самого VPN-сервера
// обычно приватная (у типового конфига это 10.8.0.0/24), и попади она под
// общее правило «приватное — мимо туннеля», трафик к собственному серверу
// ушёл бы напрямую и никуда не дошёл. Никаких диапазонов «по умолчанию» здесь
// нет намеренно: что обходить, решает Swift-слой, который один знает адрес
// туннеля.
func NewBypassSet(include, exclude []string) *BypassSet {
	return &BypassSet{
		prefixes: parsePrefixes(include),
		excludes: parsePrefixes(exclude),
	}
}

func parsePrefixes(list []string) []netip.Prefix {
	var out []netip.Prefix
	for _, raw := range list {
		s := strings.TrimSpace(raw)
		if s == "" {
			continue
		}
		if !strings.Contains(s, "/") {
			addr, err := netip.ParseAddr(s)
			if err != nil {
				continue
			}
			out = append(out, netip.PrefixFrom(addr, addr.BitLen()))
			continue
		}
		p, err := netip.ParsePrefix(s)
		if err != nil {
			continue
		}
		out = append(out, p.Masked())
	}
	return out
}

func (b *BypassSet) Contains(addr netip.Addr) bool {
	if b == nil || !addr.IsValid() {
		return false
	}
	addr = addr.Unmap()
	for _, p := range b.excludes {
		if p.Contains(addr) {
			return false
		}
	}
	for _, p := range b.prefixes {
		if p.Contains(addr) {
			return true
		}
	}
	return false
}

func (b *BypassSet) Len() int {
	if b == nil {
		return 0
	}
	return len(b.prefixes)
}

// destination достаёт адрес назначения из сырого IP-пакета. Второе значение —
// false, если пакет короче заголовка или это не IPv4/IPv6.
func destination(pkt []byte) (netip.Addr, bool) {
	if len(pkt) < 1 {
		return netip.Addr{}, false
	}
	switch pkt[0] >> 4 {
	case 4:
		if len(pkt) < 20 {
			return netip.Addr{}, false
		}
		return netip.AddrFrom4([4]byte(pkt[16:20])), true
	case 6:
		if len(pkt) < 40 {
			return netip.Addr{}, false
		}
		return netip.AddrFrom16([16]byte(pkt[24:40])), true
	default:
		return netip.Addr{}, false
	}
}
