package ftun

import (
	"net"
	"net/netip"
	"sync"

	"github.com/amnezia-vpn/amneziawg-go/conn"
)

// LoopbackBind — conn.Bind поверх net.UDPConn, зафиксированного на 127.0.0.1.
// Используется для обоих девайсов (см. device.go): и для локального
// responder'а (порт фиксирован — 127.0.0.1:9000, куда AmneziaWG шлёт
// хендшейк; source-адрес клиента заранее не известен и приходит в первом же
// пакете — эту часть берёт на себя стандартный механизм conn.Endpoint, не
// нужен отдельный "listen"-режим), и для внешнего initiator'а (порт
// эфемерный, единственный пир — локальный релей на 127.0.0.1:9001, его adress
// уже зафиксирован в UAPI как endpoint пира). StdNetBind из amneziawg-go не
// годится ни для той, ни для другой роли: он слушает wildcard-адрес
// (0.0.0.0), а нам нужно, чтобы оба внутренних сокета были видны только на
// loopback и не всплывали на реальных сетевых интерфейсах.
type LoopbackBind struct {
	mu   sync.Mutex
	conn *net.UDPConn
}

func NewLoopbackBind() *LoopbackBind {
	return &LoopbackBind{}
}

type loopbackEndpoint struct {
	addr netip.AddrPort
}

func (e *loopbackEndpoint) ClearSrc()           {}
func (e *loopbackEndpoint) SrcToString() string { return "" }
func (e *loopbackEndpoint) DstToString() string { return e.addr.String() }
func (e *loopbackEndpoint) DstIP() netip.Addr   { return e.addr.Addr() }
func (e *loopbackEndpoint) SrcIP() netip.Addr   { return netip.Addr{} }
func (e *loopbackEndpoint) DstToBytes() []byte {
	b, _ := e.addr.MarshalBinary()
	return b
}

var (
	_ conn.Bind     = (*LoopbackBind)(nil)
	_ conn.Endpoint = (*loopbackEndpoint)(nil)
)

func (b *LoopbackBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.conn != nil {
		return nil, 0, conn.ErrBindAlreadyOpen
	}

	udpConn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: int(port)})
	if err != nil {
		return nil, 0, err
	}
	b.conn = udpConn

	actualPort := uint16(udpConn.LocalAddr().(*net.UDPAddr).Port)
	recv := func(bufs [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		n, addrPort, err := udpConn.ReadFromUDPAddrPort(bufs[0])
		if err != nil {
			return 0, err
		}
		sizes[0] = n
		eps[0] = &loopbackEndpoint{addr: addrPort}
		return 1, nil
	}
	return []conn.ReceiveFunc{recv}, actualPort, nil
}

func (b *LoopbackBind) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.conn == nil {
		return nil
	}
	err := b.conn.Close()
	b.conn = nil
	return err
}

func (b *LoopbackBind) SetMark(mark uint32) error { return nil }

func (b *LoopbackBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	b.mu.Lock()
	udpConn := b.conn
	b.mu.Unlock()
	if udpConn == nil {
		return net.ErrClosed
	}
	dst := ep.(*loopbackEndpoint).addr
	for _, buf := range bufs {
		if _, err := udpConn.WriteToUDPAddrPort(buf, dst); err != nil {
			return err
		}
	}
	return nil
}

func (b *LoopbackBind) ParseEndpoint(s string) (conn.Endpoint, error) {
	addr, err := netip.ParseAddrPort(s)
	if err != nil {
		return nil, err
	}
	return &loopbackEndpoint{addr: addr}, nil
}

func (b *LoopbackBind) BatchSize() int { return 1 }
