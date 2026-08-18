package ftun

import (
	"container/list"
	"net/netip"
)

// Потолок кэша решений. 4096 адресов с запасом покрывают рабочий набор
// клиента (десятки хостов на соединение), а память под них — единицы
// десятков килобайт.
const cacheMax = 4096

// routeCache — LRU-кэш ответа BypassSet.Contains по адресу назначения.
// Бинарный поиск и так дёшев, но он идёт на каждый пакет, а трафик по своей
// природе бьётся в горстку адресов — попадание в кэш снимает поиск целиком.
//
// Синхронизации здесь нет намеренно, и держится это не на договорённости, а
// на области видимости: экземпляр создаётся локальной переменной внутри
// pumpFromLocal и передаётся параметром. Указатель на него не лежит ни в
// одной структуре, доступной другой горутине, поэтому второй участник, от
// которого мог бы защищать мьютекс, физически не может появиться иначе как
// явной передачей указателя между горутинами. Обращения (get из
// routesBypass, следом put там же) — обычные синхронные вызовы на стеке
// одной горутины, строго по очереди.
//
// Если помп когда-нибудь станет несколько, каждая заводит свой кэш первой
// строкой — схема масштабируется без единой блокировки.
type routeCache struct {
	m  map[netip.Addr]*list.Element // значение элемента — *cacheEntry
	ll *list.List                   // голова — самый свежий, хвост — кандидат на вытеснение
}

type cacheEntry struct {
	addr  netip.Addr
	allow bool
}

func newRouteCache() *routeCache {
	return &routeCache{m: make(map[netip.Addr]*list.Element, cacheMax), ll: list.New()}
}

func (c *routeCache) get(a netip.Addr) (bool, bool) {
	e, ok := c.m[a]
	if !ok {
		return false, false
	}
	c.ll.MoveToFront(e) // обращение освежает запись — в этом и есть LRU
	return e.Value.(*cacheEntry).allow, true
}

func (c *routeCache) put(a netip.Addr, v bool) {
	if e, ok := c.m[a]; ok {
		e.Value.(*cacheEntry).allow = v
		c.ll.MoveToFront(e)
		return
	}
	if c.ll.Len() >= cacheMax {
		// Вытесняем хвост и переиспользуем и узел списка, и саму запись: в
		// установившемся режиме промах не аллоцирует ничего.
		oldest := c.ll.Back()
		ent := oldest.Value.(*cacheEntry)
		delete(c.m, ent.addr)
		ent.addr, ent.allow = a, v
		c.ll.MoveToFront(oldest)
		c.m[a] = oldest
		return
	}
	c.m[a] = c.ll.PushFront(&cacheEntry{addr: a, allow: v})
}

func (c *routeCache) len() int { return c.ll.Len() }
