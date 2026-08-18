package ftun

import (
	"net/netip"
	"sort"
	"strings"
)

// BypassSet — множество назначений, которые роутер уводит мимо туннеля
// (см. план vpn-lexical-rossum.md, фаза 5.2). Пустое множество = весь трафик
// идёт в туннель, то есть поведение фазы 1 (чистый pass-through).
//
// Внутри — не список префиксов, а отсортированный список непересекающихся
// диапазонов адресов. Причина: при раздельном туннелировании список приезжает
// от пользователя и легко доходит до десятков тысяч подсетей, а Contains
// зовётся на КАЖДЫЙ пакет — линейный перебор префиксов на таком списке кладёт
// туннель. Диапазоны позволяют искать бинарно, а заодно снимают exclude на
// этапе сборки: «exclude перебивает include» уже вычтено, в рантайме проверок
// две вместо двух проходов.
type BypassSet struct {
	// Отсортированы по start, не пересекаются и не смежны.
	ranges []addrRange
}

// Полуинтервал [start, end], границы включительно. Обе границы одного
// семейства: netip.Addr.Compare сортирует сперва по разрядности, поэтому
// IPv4 и IPv6 лежат в одном массиве непрерывными блоками и никогда не
// «перекрываются» при сравнении.
type addrRange struct {
	start netip.Addr
	end   netip.Addr
}

// NewBypassSet принимает CIDR и голые адреса; неразобранные записи молча
// пропускаются — список приходит из сети (подсети VK, списки блокировок), и
// одна кривая строка не должна валить старт туннеля.
//
// exclude перебивает include и нужен обязательно: сеть самого VPN-сервера
// обычно приватная (у типового конфига это 10.8.0.0/24), и попади она под
// общее правило «приватное — мимо туннеля», трафик к собственному серверу
// ушёл бы напрямую и никуда не дошёл. Никаких диапазонов «по умолчанию» здесь
// нет намеренно: что обходить, решает Swift-слой, который один знает адрес
// туннеля.
func NewBypassSet(include, exclude []string) *BypassSet {
	inc := mergeRanges(toRanges(parsePrefixes(include)))
	exc := mergeRanges(toRanges(parsePrefixes(exclude)))
	return &BypassSet{ranges: subtractRanges(inc, exc)}
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
			addr = addr.Unmap()
			out = append(out, netip.PrefixFrom(addr, addr.BitLen()))
			continue
		}
		p, err := netip.ParsePrefix(s)
		if err != nil {
			continue
		}
		out = append(out, unmapPrefix(p).Masked())
	}
	return out
}

// ::ffff:10.0.0.0/104 и 10.0.0.0/8 обязаны означать одно и то же: пакеты
// разбираются в destination() как честный IPv4, и v4-in-v6 запись иначе не
// совпала бы ни с чем.
func unmapPrefix(p netip.Prefix) netip.Prefix {
	if !p.Addr().Is4In6() || p.Bits() < 96 {
		return p
	}
	return netip.PrefixFrom(p.Addr().Unmap(), p.Bits()-96)
}

func toRanges(prefixes []netip.Prefix) []addrRange {
	out := make([]addrRange, 0, len(prefixes))
	for _, p := range prefixes {
		out = append(out, addrRange{start: p.Addr(), end: lastAddr(p)})
	}
	return out
}

// Последний адрес префикса: единицы во всех хостовых битах.
func lastAddr(p netip.Prefix) netip.Addr {
	bs := p.Addr().AsSlice()
	host := p.Addr().BitLen() - p.Bits()
	for i := len(bs) - 1; i >= 0 && host > 0; i-- {
		n := host
		if n > 8 {
			n = 8
		}
		bs[i] |= byte(0xFF) >> (8 - n)
		host -= n
	}
	addr, _ := netip.AddrFromSlice(bs)
	return addr
}

// Сортировка по началу + склейка пересекающихся и смежных диапазонов.
func mergeRanges(in []addrRange) []addrRange {
	if len(in) < 2 {
		return in
	}
	sort.Slice(in, func(i, j int) bool {
		if c := in[i].start.Compare(in[j].start); c != 0 {
			return c < 0
		}
		return in[i].end.Compare(in[j].end) < 0
	})
	out := in[:1]
	for _, r := range in[1:] {
		cur := &out[len(out)-1]
		next := cur.end.Next() // невалиден на максимуме семейства — склеивать уже нечего
		if r.start.Compare(cur.end) <= 0 || (next.IsValid() && r.start == next) {
			if r.end.Compare(cur.end) > 0 {
				cur.end = r.end
			}
			continue
		}
		out = append(out, r)
	}
	return out
}

// inc и exc — уже отсортированы и не пересекаются внутри себя.
func subtractRanges(inc, exc []addrRange) []addrRange {
	if len(exc) == 0 || len(inc) == 0 {
		return inc
	}
	out := make([]addrRange, 0, len(inc))
	j := 0
	for _, r := range inc {
		cur := r
		// Исключения левее текущего диапазона не понадобятся и дальше:
		// оба списка отсортированы.
		for j < len(exc) && exc[j].end.Compare(cur.start) < 0 {
			j++
		}
		for k := j; k < len(exc) && exc[k].start.Compare(cur.end) <= 0; k++ {
			e := exc[k]
			if e.start.Compare(cur.start) > 0 {
				out = append(out, addrRange{start: cur.start, end: e.start.Prev()})
			}
			if e.end.Compare(cur.end) >= 0 {
				cur.start = netip.Addr{} // диапазон съеден целиком
				break
			}
			cur.start = e.end.Next()
		}
		if cur.start.IsValid() && cur.start.Compare(cur.end) <= 0 {
			out = append(out, cur)
		}
	}
	return out
}

func (b *BypassSet) Contains(addr netip.Addr) bool {
	if b == nil || len(b.ranges) == 0 || !addr.IsValid() {
		return false
	}
	addr = addr.Unmap()
	// Первый диапазон, который кончается не раньше адреса. Если адрес вообще
	// где-то лежит, то только в нём: диапазоны не пересекаются.
	i := sort.Search(len(b.ranges), func(i int) bool {
		return b.ranges[i].end.Compare(addr) >= 0
	})
	return i < len(b.ranges) && b.ranges[i].start.Compare(addr) <= 0
}

func (b *BypassSet) IsEmpty() bool {
	return b == nil || len(b.ranges) == 0
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
