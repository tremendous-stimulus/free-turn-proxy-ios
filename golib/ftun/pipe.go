package ftun

import (
	"os"
	"sync"

	"github.com/amnezia-vpn/amneziawg-go/tun"
)

// endpoint — tun.Device поверх пары каналов в памяти. В отличие от прямой
// склейки двух девайсов (фаза 1), входящая и исходящая очереди разведены:
// девайс читает из inbound и пишет в outbound, а кто и куда перекладывает
// пакеты — решает router (см. router.go, план фаза 5.2).
type endpoint struct {
	name string
	mtu  int

	inbound  chan []byte
	outbound chan []byte

	events    chan tun.Event
	closeCh   chan struct{}
	closeOnce sync.Once
}

func newEndpoint(name string, mtu int) *endpoint {
	return &endpoint{
		name:     name,
		mtu:      mtu,
		inbound:  make(chan []byte, 256),
		outbound: make(chan []byte, 256),
		events:   make(chan tun.Event, 8),
		closeCh:  make(chan struct{}),
	}
}

// NewPipe создаёт пару tun.Device, склеенную чистым pass-through: всё
// записанное в одну половину читается из другой. Это поведение фазы 1;
// маршрутизация появляется, когда router получает непустой BypassSet.
func NewPipe(mtu int) (a tun.Device, b tun.Device) {
	local, remote := newEndpoint("ftun-local", mtu), newEndpoint("ftun-remote", mtu)
	newRouter(local, remote, nil, nil).start()
	return local, remote
}

func (e *endpoint) File() *os.File { return nil }

func (e *endpoint) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	select {
	case pkt, ok := <-e.inbound:
		if !ok {
			return 0, os.ErrClosed
		}
		sizes[0] = copy(bufs[0][offset:], pkt)
		n := 1
		for n < len(bufs) {
			select {
			case pkt2, ok := <-e.inbound:
				if !ok {
					return n, nil
				}
				sizes[n] = copy(bufs[n][offset:], pkt2)
				n++
			default:
				return n, nil
			}
		}
		return n, nil
	case <-e.closeCh:
		return 0, os.ErrClosed
	}
}

func (e *endpoint) Write(bufs [][]byte, offset int) (int, error) {
	written := 0
	for _, buf := range bufs {
		if offset > len(buf) {
			continue
		}
		pkt := make([]byte, len(buf)-offset)
		copy(pkt, buf[offset:])
		// Отдельная проверка перед select: при обоих готовых case'ах select
		// выбирает случайно, и запись в закрытый конец иногда «удавалась».
		select {
		case <-e.closeCh:
			return written, os.ErrClosed
		default:
		}
		select {
		case e.outbound <- pkt:
			written++
		case <-e.closeCh:
			return written, os.ErrClosed
		}
	}
	return written, nil
}

// deliver кладёт пакет в очередь на чтение девайсом. Вызывается только
// роутером.
func (e *endpoint) deliver(pkt []byte) bool {
	select {
	case e.inbound <- pkt:
		return true
	case <-e.closeCh:
		return false
	}
}

func (e *endpoint) MTU() (int, error) { return e.mtu, nil }

func (e *endpoint) Name() (string, error) { return e.name, nil }

func (e *endpoint) Events() <-chan tun.Event { return e.events }

func (e *endpoint) BatchSize() int { return 1 }

func (e *endpoint) Close() error {
	e.closeOnce.Do(func() {
		close(e.closeCh)
		close(e.events)
	})
	return nil
}
