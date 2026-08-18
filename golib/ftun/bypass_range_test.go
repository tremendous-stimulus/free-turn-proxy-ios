package ftun

import (
	"fmt"
	"math/rand"
	"net/netip"
	"testing"
)

// Наивная реализация «как было»: линейный перебор, exclude перебивает include.
// Она и есть эталон — новая внутренность (диапазоны + бинарный поиск) обязана
// отвечать ровно то же самое.
func naiveContains(include, exclude []string, addr netip.Addr) bool {
	addr = addr.Unmap()
	for _, p := range parsePrefixes(exclude) {
		if p.Contains(addr) {
			return false
		}
	}
	for _, p := range parsePrefixes(include) {
		if p.Contains(addr) {
			return true
		}
	}
	return false
}

func randomV4(rnd *rand.Rand) netip.Addr {
	return netip.AddrFrom4([4]byte{byte(rnd.Intn(256)), byte(rnd.Intn(256)), byte(rnd.Intn(256)), byte(rnd.Intn(256))})
}

func randomPrefixes(rnd *rand.Rand, n int) []string {
	out := make([]string, 0, n)
	for i := 0; i < n; i++ {
		bits := 8 + rnd.Intn(25) // /8../32 — как в реальных списках блокировок
		out = append(out, fmt.Sprintf("%s/%d", randomV4(rnd), bits))
	}
	return out
}

func TestBypassSet_MatchesNaiveOnRandomSet(t *testing.T) {
	rnd := rand.New(rand.NewSource(20260818))
	include := randomPrefixes(rnd, 500)
	exclude := randomPrefixes(rnd, 50)
	set := NewBypassSet(include, exclude)

	for i := 0; i < 20000; i++ {
		addr := randomV4(rnd)
		want := naiveContains(include, exclude, addr)
		if got := set.Contains(addr); got != want {
			t.Fatalf("%s: получили %v, эталон %v", addr, got, want)
		}
	}
	// И отдельно — адреса из самих подсетей, иначе случайные почти всегда мимо.
	for _, p := range parsePrefixes(include) {
		addr := p.Addr()
		if got, want := set.Contains(addr), naiveContains(include, exclude, addr); got != want {
			t.Fatalf("%s: получили %v, эталон %v", addr, got, want)
		}
	}
}

func TestBypassSet_MergesOverlappingAndAdjacent(t *testing.T) {
	set := NewBypassSet([]string{"10.0.0.0/9", "10.128.0.0/9", "10.5.0.0/16"}, nil)
	if len(set.ranges) != 1 {
		t.Fatalf("смежные и вложенные подсети должны схлопнуться в один диапазон, получили %d", len(set.ranges))
	}
	for _, ip := range []string{"10.0.0.0", "10.127.255.255", "10.128.0.0", "10.255.255.255"} {
		if !set.Contains(netip.MustParseAddr(ip)) {
			t.Errorf("%s должен попадать в объединённый диапазон", ip)
		}
	}
	if set.Contains(netip.MustParseAddr("11.0.0.0")) {
		t.Error("соседний адрес за границей не должен попадать")
	}
}

// Дыра посреди диапазона: сеть VPN-сервера внутри широкого include.
func TestBypassSet_ExcludePunchesHole(t *testing.T) {
	set := NewBypassSet([]string{"10.0.0.0/8"}, []string{"10.8.0.0/24"})
	if len(set.ranges) != 2 {
		t.Fatalf("исключение в середине должно разрезать диапазон надвое, получили %d", len(set.ranges))
	}
	for _, ip := range []string{"10.7.255.255", "10.9.0.0", "10.0.0.0", "10.255.255.255"} {
		if !set.Contains(netip.MustParseAddr(ip)) {
			t.Errorf("%s должен обходить туннель", ip)
		}
	}
	for _, ip := range []string{"10.8.0.0", "10.8.0.1", "10.8.0.255"} {
		if set.Contains(netip.MustParseAddr(ip)) {
			t.Errorf("%s обязан остаться в туннеле", ip)
		}
	}
}

func TestBypassSet_ExcludeSwallowsWholeRange(t *testing.T) {
	set := NewBypassSet([]string{"10.8.0.0/24", "192.168.0.0/16"}, []string{"10.0.0.0/8"})
	if set.Contains(netip.MustParseAddr("10.8.0.1")) {
		t.Error("полностью исключённый диапазон не должен остаться")
	}
	if !set.Contains(netip.MustParseAddr("192.168.1.1")) {
		t.Error("не затронутый исключением диапазон должен уцелеть")
	}
}

// Границы адресного пространства: Next()/Prev() там невалидны, и арифметика
// диапазонов не должна на этом спотыкаться.
func TestBypassSet_AddressSpaceEdges(t *testing.T) {
	set := NewBypassSet([]string{"0.0.0.0/0"}, []string{"0.0.0.0/8", "255.0.0.0/8"})
	if set.Contains(netip.MustParseAddr("0.0.0.1")) {
		t.Error("нижний край исключён")
	}
	if set.Contains(netip.MustParseAddr("255.255.255.255")) {
		t.Error("верхний край исключён")
	}
	if !set.Contains(netip.MustParseAddr("1.0.0.0")) || !set.Contains(netip.MustParseAddr("254.255.255.255")) {
		t.Error("середина должна остаться")
	}

	full := NewBypassSet([]string{"0.0.0.0/0"}, nil)
	for _, ip := range []string{"0.0.0.0", "8.8.8.8", "255.255.255.255"} {
		if !full.Contains(netip.MustParseAddr(ip)) {
			t.Errorf("%s должен попадать в 0.0.0.0/0", ip)
		}
	}
	if full.Contains(netip.MustParseAddr("2001:db8::1")) {
		t.Error("IPv4-диапазон не должен ловить IPv6")
	}
}

func TestBypassSet_IPv6AndMixedFamilies(t *testing.T) {
	set := NewBypassSet([]string{"2001:db8::/32", "10.0.0.0/8", "::ffff:172.16.0.0/108"}, []string{"2001:db8:1::/48"})
	if !set.Contains(netip.MustParseAddr("2001:db8::1")) {
		t.Error("IPv6 из диапазона должен обходить туннель")
	}
	if set.Contains(netip.MustParseAddr("2001:db8:1::5")) {
		t.Error("исключённая IPv6-подсеть должна остаться в туннеле")
	}
	if !set.Contains(netip.MustParseAddr("10.1.2.3")) {
		t.Error("IPv4 рядом с IPv6 в одном списке должен работать")
	}
	if !set.Contains(netip.MustParseAddr("172.16.5.5")) {
		t.Error("v4-in-v6 запись должна совпадать с обычным IPv4-адресом")
	}
	if set.Contains(netip.MustParseAddr("2002::1")) {
		t.Error("чужой IPv6 не должен попадать")
	}
}

func TestBypassSet_IsEmpty(t *testing.T) {
	var nilSet *BypassSet
	if !nilSet.IsEmpty() || !NewBypassSet(nil, nil).IsEmpty() {
		t.Error("пустое множество обязано считаться пустым")
	}
	if !NewBypassSet([]string{"10.0.0.0/8"}, []string{"10.0.0.0/8"}).IsEmpty() {
		t.Error("исключение, съевшее весь список, оставляет множество пустым")
	}
	if NewBypassSet([]string{"10.0.0.0/8"}, nil).IsEmpty() {
		t.Error("непустое множество не должно считаться пустым")
	}
}

// Тот самый сценарий, ради которого всё переделывалось: список масштаба
// реальных блокировок РФ. Contains зовётся на каждый пакет, и линейный
// перебор здесь давал бы десятки тысяч сравнений на пакет.
func BenchmarkContains(b *testing.B) {
	rnd := rand.New(rand.NewSource(1))
	set := NewBypassSet(randomPrefixes(rnd, 40000), randomPrefixes(rnd, 100))
	addrs := make([]netip.Addr, 1024)
	for i := range addrs {
		addrs[i] = randomV4(rnd)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		set.Contains(addrs[i%len(addrs)])
	}
}

// Эталон «как было»: тот же список, но линейным перебором префиксов. Держим
// рядом с BenchmarkContains, чтобы разница в отчёте была видна глазами, а не
// принималась на веру.
func BenchmarkContainsLinear(b *testing.B) {
	rnd := rand.New(rand.NewSource(1))
	prefixes := parsePrefixes(randomPrefixes(rnd, 40000))
	addrs := make([]netip.Addr, 1024)
	for i := range addrs {
		addrs[i] = randomV4(rnd)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		addr := addrs[i%len(addrs)]
		for _, p := range prefixes {
			if p.Contains(addr) {
				break
			}
		}
	}
}

func BenchmarkContainsCached(b *testing.B) {
	rnd := rand.New(rand.NewSource(1))
	set := NewBypassSet(randomPrefixes(rnd, 40000), randomPrefixes(rnd, 100))
	// Рабочий набор клиента: горстка адресов, по которым и идёт трафик.
	addrs := make([]netip.Addr, 64)
	for i := range addrs {
		addrs[i] = randomV4(rnd)
	}
	cache := newRouteCache()
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		a := addrs[i%len(addrs)]
		if _, hit := cache.get(a); hit {
			continue
		}
		cache.put(a, set.Contains(a))
	}
}
