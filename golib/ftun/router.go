package ftun

import "sync"

// router — то, что раньше было прямой склейкой двух половин дороги. Решение
// принимается по адресу назначения расшифрованного пакета (план
// vpn-lexical-rossum.md, фаза 5.2):
//
//	устройство → responder ─┬─ dst ∈ bypass → netstack → сокет мимо VPN
//	                        └─ иначе        → initiator → релей → TURN → VPS
//
// Ответы приходят с двух сторон (от initiator'а и от netstack) и сходятся
// обратно в responder.
type router struct {
	local  *endpoint // responder: сюда смотрит AmneziaWG
	remote *endpoint // initiator: отсюда уходит в релей

	bypass *BypassSet
	stack  *bypassStack

	wg      sync.WaitGroup
	closeCh chan struct{}
	once    sync.Once
}

func newRouter(local, remote *endpoint, bypass *BypassSet, stack *bypassStack) *router {
	return &router{
		local:   local,
		remote:  remote,
		bypass:  bypass,
		stack:   stack,
		closeCh: make(chan struct{}),
	}
}

func (r *router) start() {
	r.wg.Add(2)
	go r.pumpFromLocal()
	go r.pumpFromRemote()
	if r.stack != nil {
		r.wg.Add(1)
		go r.pumpFromStack()
	}
}

func (r *router) close() {
	r.once.Do(func() {
		close(r.closeCh)
		// Сначала дожидаемся помп, только потом рвём стек: pumpFromLocal может
		// быть между routesBypass() и stack.Inject(), а Inject в уже закрытый
		// gvisor-стек — use-after-close.
		r.wg.Wait()
		if r.stack != nil {
			r.stack.Close()
		}
	})
}

// Единственное место, где принимается решение о маршруте. Кэш приходит
// параметром, а не лежит в router: так он остаётся собственностью одной
// горутины по области видимости, а не по договорённости (см. routeCache).
// Проверка кэша идёт ПОСЛЕ nil-guard'а: у роутера из NewPipe bypass == nil,
// и до кэша дело не доходит вовсе.
func (r *router) routesBypass(cache *routeCache, pkt []byte) bool {
	if r.stack == nil || r.bypass == nil {
		return false
	}
	dst, ok := destination(pkt)
	if !ok {
		return false
	}
	if v, hit := cache.get(dst); hit {
		return v
	}
	v := r.bypass.Contains(dst)
	cache.put(dst, v)
	return v
}

func (r *router) pumpFromLocal() {
	defer r.wg.Done()
	// Владелец кэша — только эта горутина: дотянуться до него извне нельзя.
	cache := newRouteCache()
	for {
		select {
		case pkt, ok := <-r.local.outbound:
			if !ok {
				return
			}
			if r.routesBypass(cache, pkt) {
				r.stack.Inject(pkt)
				continue
			}
			if !r.remote.deliver(pkt) {
				return
			}
		case <-r.closeCh:
			return
		case <-r.local.closeCh:
			return
		}
	}
}

func (r *router) pumpFromRemote() {
	defer r.wg.Done()
	for {
		select {
		case pkt, ok := <-r.remote.outbound:
			if !ok {
				return
			}
			if !r.local.deliver(pkt) {
				return
			}
		case <-r.closeCh:
			return
		case <-r.remote.closeCh:
			return
		}
	}
}

func (r *router) pumpFromStack() {
	defer r.wg.Done()
	for {
		select {
		case pkt, ok := <-r.stack.Outbound():
			if !ok {
				return
			}
			if !r.local.deliver(pkt) {
				return
			}
		case <-r.closeCh:
			return
		case <-r.local.closeCh:
			return
		}
	}
}
