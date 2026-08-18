package ftun

import (
	"math/rand"
	"net/netip"
	"testing"
)

func addrOf(i int) netip.Addr {
	return netip.AddrFrom4([4]byte{10, byte(i >> 16), byte(i >> 8), byte(i)})
}

func TestRouteCache_HitAndMiss(t *testing.T) {
	c := newRouteCache()
	a := netip.MustParseAddr("8.8.8.8")
	if _, hit := c.get(a); hit {
		t.Fatal("пустой кэш не может отвечать попаданием")
	}
	c.put(a, true)
	v, hit := c.get(a)
	if !hit || !v {
		t.Fatalf("ожидали попадание true, получили (%v, %v)", v, hit)
	}
	// Повторный put того же адреса обновляет значение, а не растит кэш.
	c.put(a, false)
	if v, _ := c.get(a); v {
		t.Error("значение должно было обновиться на false")
	}
	if c.len() != 1 {
		t.Errorf("размер кэша должен остаться 1, получили %d", c.len())
	}
}

func TestRouteCache_EvictsExactlyOneOldest(t *testing.T) {
	c := newRouteCache()
	for i := 0; i < cacheMax; i++ {
		c.put(addrOf(i), true)
	}
	if c.len() != cacheMax {
		t.Fatalf("кэш должен наполниться до %d, получили %d", cacheMax, c.len())
	}
	c.put(addrOf(cacheMax), true)
	if c.len() != cacheMax {
		t.Fatalf("размер кэша обязан упереться в потолок, получили %d", c.len())
	}
	if _, hit := c.get(addrOf(0)); hit {
		t.Error("самый старый адрес должен был вытесниться")
	}
	if _, hit := c.get(addrOf(1)); !hit {
		t.Error("вытесниться должен был ровно один адрес")
	}
	if _, hit := c.get(addrOf(cacheMax)); !hit {
		t.Error("только что добавленный адрес обязан быть в кэше")
	}
}

// Смысл LRU: обращение освежает запись. Адрес, к которому обращались, обязан
// пережить вытеснение, а давно не использованный — нет.
func TestRouteCache_ReadRefreshesEntry(t *testing.T) {
	c := newRouteCache()
	for i := 0; i < cacheMax; i++ {
		c.put(addrOf(i), true)
	}
	if _, hit := c.get(addrOf(0)); !hit {
		t.Fatal("адрес ещё должен быть в кэше")
	}
	c.put(addrOf(cacheMax), true) // вытесняет теперь addrOf(1), а не addrOf(0)
	if _, hit := c.get(addrOf(0)); !hit {
		t.Error("освежённый чтением адрес не должен был вытесниться")
	}
	if _, hit := c.get(addrOf(1)); hit {
		t.Error("вытеснить должно было самый давний адрес")
	}
}

// Кэш не имеет права менять решение: на длинной последовательности адресов
// ответы обязаны совпадать с прямым Contains.
func TestRouteCache_AgreesWithBypassSet(t *testing.T) {
	rnd := rand.New(rand.NewSource(7))
	set := NewBypassSet(randomPrefixes(rnd, 200), randomPrefixes(rnd, 20))
	// Адресов заметно больше потолка — вытеснение работает прямо по ходу.
	pool := make([]netip.Addr, cacheMax*3)
	for i := range pool {
		pool[i] = randomV4(rnd)
	}
	c := newRouteCache()
	for i := 0; i < len(pool)*4; i++ {
		a := pool[rnd.Intn(len(pool))]
		want := set.Contains(a)
		got, hit := c.get(a)
		if !hit {
			got = want
			c.put(a, want)
		}
		if got != want {
			t.Fatalf("%s: кэш вернул %v, Contains — %v", a, got, want)
		}
	}
	if c.len() > cacheMax {
		t.Errorf("кэш перерос потолок: %d", c.len())
	}
}
