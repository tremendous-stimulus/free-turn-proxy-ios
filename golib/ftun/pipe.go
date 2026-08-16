package ftun

import (
	"os"
	"sync"

	"github.com/amnezia-vpn/amneziawg-go/tun"
)

// pipeEnd — реализация tun.Device поверх канала в памяти. Пара pipeEnd,
// созданная NewPipe, и есть "роутер" между двумя WG-девайсами (см. device.go):
// то, что один девайс расшифровал и записал в свой tun, читает как входящий
// IP-пакет другой девайс, и наоборот. В фазе 1 это чистый pass-through —
// без NAT и без фильтрации, см. план (раздел "Роутер — чистый L3 pass-through").
type pipeEnd struct {
	name string
	mtu  int

	peer *pipeEnd
	in   chan []byte

	events    chan tun.Event
	closeCh   chan struct{}
	closeOnce sync.Once
}

// NewPipe создаёт связанную пару tun.Device: всё записанное в одну половину
// читается из другой.
func NewPipe(mtu int) (a tun.Device, b tun.Device) {
	pa := &pipeEnd{
		name:    "ftun-local",
		mtu:     mtu,
		in:      make(chan []byte, 256),
		events:  make(chan tun.Event, 8),
		closeCh: make(chan struct{}),
	}
	pb := &pipeEnd{
		name:    "ftun-remote",
		mtu:     mtu,
		in:      make(chan []byte, 256),
		events:  make(chan tun.Event, 8),
		closeCh: make(chan struct{}),
	}
	pa.peer = pb
	pb.peer = pa
	return pa, pb
}

func (e *pipeEnd) File() *os.File { return nil }

func (e *pipeEnd) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	select {
	case pkt, ok := <-e.in:
		if !ok {
			return 0, os.ErrClosed
		}
		sizes[0] = copy(bufs[0][offset:], pkt)
		n := 1
		for n < len(bufs) {
			select {
			case pkt2, ok := <-e.in:
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

func (e *pipeEnd) Write(bufs [][]byte, offset int) (int, error) {
	written := 0
	for _, buf := range bufs {
		if offset > len(buf) {
			continue
		}
		pkt := make([]byte, len(buf)-offset)
		copy(pkt, buf[offset:])
		select {
		case <-e.peer.closeCh:
			return written, os.ErrClosed
		case <-e.closeCh:
			return written, os.ErrClosed
		default:
		}
		select {
		case e.peer.in <- pkt:
			written++
		case <-e.peer.closeCh:
			return written, os.ErrClosed
		case <-e.closeCh:
			return written, os.ErrClosed
		}
	}
	return written, nil
}

func (e *pipeEnd) MTU() (int, error) { return e.mtu, nil }

func (e *pipeEnd) Name() (string, error) { return e.name, nil }

func (e *pipeEnd) Events() <-chan tun.Event { return e.events }

func (e *pipeEnd) BatchSize() int { return 1 }

func (e *pipeEnd) Close() error {
	e.closeOnce.Do(func() {
		close(e.closeCh)
		close(e.events)
	})
	return nil
}
