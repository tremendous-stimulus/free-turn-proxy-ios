package ftun

import (
	"context"
	"fmt"
	"io"
	"net"
	"strconv"
	"sync"
	"time"

	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/tcpip"
	"gvisor.dev/gvisor/pkg/tcpip/adapters/gonet"
	"gvisor.dev/gvisor/pkg/tcpip/header"
	"gvisor.dev/gvisor/pkg/tcpip/link/channel"
	"gvisor.dev/gvisor/pkg/tcpip/network/ipv4"
	"gvisor.dev/gvisor/pkg/tcpip/network/ipv6"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
	"gvisor.dev/gvisor/pkg/tcpip/transport/icmp"
	"gvisor.dev/gvisor/pkg/tcpip/transport/tcp"
	"gvisor.dev/gvisor/pkg/tcpip/transport/udp"
	"gvisor.dev/gvisor/pkg/waiter"
)

const bypassNIC tcpip.NICID = 1

// Обходное UDP-«соединение» держим ровно столько, сколько по нему идёт трафик:
// у UDP нет FIN, а сокет на каждый поток нам не бесплатен.
const udpIdleTimeout = 60 * time.Second

const dialTimeout = 10 * time.Second

// bypassStack — userspace TCP/IP стек для трафика, уходящего мимо туннеля
// (план vpn-lexical-rossum.md, фаза 5.2). Сырой IP-пакет из приложения в сеть
// не инжектируется (raw-сокет требует root), поэтому обходной трафик
// терминируется здесь и переоткрывается обычными сокетами — которые
// protectControl выводит из-под системного VPN.
type bypassStack struct {
	stack    *stack.Stack
	ep       *channel.Endpoint
	outbound chan []byte

	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
	once   sync.Once

	// Живые релеи. io.Copy внутри relay не разблокируется ни отменой
	// контекста, ни закрытием link-endpoint'а — только реальным закрытием
	// сокета, поэтому Close() обязан знать про каждое соединение, иначе один
	// idle-коннект вешает wg.Wait() навсегда.
	mu     sync.Mutex
	conns  map[net.Conn]struct{}
	closed bool

	dialer net.Dialer
	logf   func(format string, args ...any)
}

func newBypassStack(mtu int, logf func(format string, args ...any)) (*bypassStack, error) {
	if logf == nil {
		logf = func(string, ...any) {}
	}
	s := stack.New(stack.Options{
		NetworkProtocols: []stack.NetworkProtocolFactory{ipv4.NewProtocol, ipv6.NewProtocol},
		TransportProtocols: []stack.TransportProtocolFactory{
			tcp.NewProtocol, udp.NewProtocol, icmp.NewProtocol4, icmp.NewProtocol6,
		},
	})

	ctx, cancel := context.WithCancel(context.Background())
	b := &bypassStack{
		stack:    s,
		ep:       channel.New(1024, uint32(mtu), ""),
		outbound: make(chan []byte, 256),
		ctx:      ctx,
		cancel:   cancel,
		conns:    make(map[net.Conn]struct{}),
		dialer:   net.Dialer{Control: protectControl, Timeout: dialTimeout},
		logf:     logf,
	}

	if err := s.CreateNIC(bypassNIC, b.ep); err != nil {
		cancel()
		return nil, fmt.Errorf("CreateNIC: %v", err)
	}
	// Пакеты адресованы не нам, а произвольным хостам в интернете, поэтому
	// стек обязан принимать «чужие» адреса (promiscuous) и разрешать
	// endpoint'ам садиться на них же при ответе (spoofing).
	if err := s.SetPromiscuousMode(bypassNIC, true); err != nil {
		cancel()
		return nil, fmt.Errorf("SetPromiscuousMode: %v", err)
	}
	if err := s.SetSpoofing(bypassNIC, true); err != nil {
		cancel()
		return nil, fmt.Errorf("SetSpoofing: %v", err)
	}
	s.SetRouteTable([]tcpip.Route{
		{Destination: header.IPv4EmptySubnet, NIC: bypassNIC},
		{Destination: header.IPv6EmptySubnet, NIC: bypassNIC},
	})

	tcpFwd := tcp.NewForwarder(s, 0, 2048, b.handleTCP)
	s.SetTransportProtocolHandler(tcp.ProtocolNumber, tcpFwd.HandlePacket)
	udpFwd := udp.NewForwarder(s, b.handleUDP)
	s.SetTransportProtocolHandler(udp.ProtocolNumber, udpFwd.HandlePacket)

	b.wg.Add(1)
	go b.readLoop()
	return b, nil
}

// Inject отдаёт стеку пакет, пришедший с устройства.
func (b *bypassStack) Inject(pkt []byte) {
	if len(pkt) == 0 {
		return
	}
	pkb := stack.NewPacketBuffer(stack.PacketBufferOptions{Payload: buffer.MakeWithData(pkt)})
	switch pkt[0] >> 4 {
	case 4:
		b.ep.InjectInbound(header.IPv4ProtocolNumber, pkb)
	case 6:
		b.ep.InjectInbound(header.IPv6ProtocolNumber, pkb)
	default:
		pkb.DecRef()
	}
}

// Outbound — пакеты, которые стек шлёт обратно на устройство.
func (b *bypassStack) Outbound() <-chan []byte { return b.outbound }

func (b *bypassStack) readLoop() {
	defer b.wg.Done()
	for {
		pkt := b.ep.ReadContext(b.ctx)
		if pkt.IsNil() {
			return
		}
		view := pkt.ToView()
		pkt.DecRef()
		out := make([]byte, view.Size())
		if _, err := view.Read(out); err != nil {
			continue
		}
		select {
		case b.outbound <- out:
		case <-b.ctx.Done():
			return
		}
	}
}

// addConns регистрирует пару соединений релея. false — стек уже закрывается,
// соединения закрыты здесь же, вызывающий должен просто выйти.
func (b *bypassStack) addConns(cs ...net.Conn) bool {
	b.mu.Lock()
	if b.closed {
		b.mu.Unlock()
		for _, c := range cs {
			c.Close()
		}
		return false
	}
	for _, c := range cs {
		b.conns[c] = struct{}{}
	}
	b.mu.Unlock()
	return true
}

func (b *bypassStack) removeConns(cs ...net.Conn) {
	b.mu.Lock()
	for _, c := range cs {
		delete(b.conns, c)
	}
	b.mu.Unlock()
}

func (b *bypassStack) closeConns() {
	b.mu.Lock()
	b.closed = true
	live := make([]net.Conn, 0, len(b.conns))
	for c := range b.conns {
		live = append(live, c)
	}
	b.conns = nil
	b.mu.Unlock()
	for _, c := range live {
		c.Close()
	}
}

func (b *bypassStack) Close() {
	b.once.Do(func() {
		b.cancel()
		// Соединения рвём до wg.Wait(): иначе релей-горутины висят в io.Copy
		// на живом сокете и Close() не возвращается никогда — а зовут его с
		// главного потока (ProxyManager.stop → ftun.Stop).
		b.closeConns()
		b.ep.Close()
		b.wg.Wait()
		b.stack.Close()
		close(b.outbound)
	})
}

// MARK: - форвардеры

func (b *bypassStack) handleTCP(r *tcp.ForwarderRequest) {
	id := r.ID()
	dst := net.JoinHostPort(id.LocalAddress.String(), strconv.Itoa(int(id.LocalPort)))

	// Дозваниваемся до реального адреса ДО CreateEndpoint: иначе мы бы приняли
	// соединение у устройства и только потом выяснили, что снаружи оно не
	// открывается. Диал блокирующий, поэтому в отдельной горутине — колбэк
	// форвардера держать нельзя.
	b.wg.Add(1)
	go func() {
		defer b.wg.Done()
		remote, err := b.dialer.DialContext(b.ctx, "tcp", dst)
		if err != nil {
			b.logf("bypass: tcp %s: %v", dst, err)
			r.Complete(true)
			return
		}
		var wq waiter.Queue
		ep, terr := r.CreateEndpoint(&wq)
		if terr != nil {
			remote.Close()
			r.Complete(true)
			return
		}
		r.Complete(false)
		local := gonet.NewTCPConn(&wq, ep)
		if !b.addConns(local, remote) {
			return
		}
		defer b.removeConns(local, remote)
		relay(local, remote)
	}()
}

func (b *bypassStack) handleUDP(r *udp.ForwarderRequest) {
	id := r.ID()
	dst := net.JoinHostPort(id.LocalAddress.String(), strconv.Itoa(int(id.LocalPort)))

	var wq waiter.Queue
	ep, terr := r.CreateEndpoint(&wq)
	if terr != nil {
		b.logf("bypass: udp %s: CreateEndpoint: %v", dst, terr)
		return
	}
	local := gonet.NewUDPConn(b.stack, &wq, ep)

	b.wg.Add(1)
	go func() {
		defer b.wg.Done()
		remote, err := b.dialer.DialContext(b.ctx, "udp", dst)
		if err != nil {
			b.logf("bypass: udp %s: %v", dst, err)
			local.Close()
			return
		}
		if !b.addConns(local, remote) {
			return
		}
		defer b.removeConns(local, remote)
		relayUDP(local, remote)
	}()
}

// relay качает байты в обе стороны и закрывает обе половины, как только
// умолкла любая из них.
func relay(a, b net.Conn) {
	var once sync.Once
	stop := func() {
		once.Do(func() {
			a.Close()
			b.Close()
		})
	}
	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); defer stop(); io.Copy(a, b) }()
	go func() { defer wg.Done(); defer stop(); io.Copy(b, a) }()
	wg.Wait()
}

// relayUDP — то же, но с idle-таймаутом вместо FIN.
func relayUDP(local, remote net.Conn) {
	var once sync.Once
	stop := func() {
		once.Do(func() {
			local.Close()
			remote.Close()
		})
	}
	var wg sync.WaitGroup
	wg.Add(2)
	pump := func(dst, src net.Conn) {
		defer wg.Done()
		defer stop()
		buf := make([]byte, 65535)
		for {
			if err := src.SetReadDeadline(time.Now().Add(udpIdleTimeout)); err != nil {
				return
			}
			n, err := src.Read(buf)
			if n > 0 {
				if _, werr := dst.Write(buf[:n]); werr != nil {
					return
				}
			}
			if err != nil {
				return
			}
		}
	}
	go pump(remote, local)
	go pump(local, remote)
	wg.Wait()
}
