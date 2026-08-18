package ftun

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/device"
	"golang.org/x/crypto/curve25519"
)

// genKeypair — обычная X25519-пара, как та, что реальный WG-клиент кладёт
// в PrivateKey/PublicKey .conf. Внутренние типы amneziawg-go/device не
// экспортируют генератор, поэтому клэмпим руками по спецификации X25519.
func genKeypair(t *testing.T) (priv, pub string) {
	t.Helper()
	var sk [32]byte
	if _, err := rand.Read(sk[:]); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	sk[0] &= 248
	sk[31] &= 127
	sk[31] |= 64

	pk, err := curve25519.X25519(sk[:], curve25519.Basepoint)
	if err != nil {
		t.Fatalf("curve25519.X25519: %v", err)
	}
	return base64.StdEncoding.EncodeToString(sk[:]), base64.StdEncoding.EncodeToString(pk)
}

func mustGetFreePort(t *testing.T) int {
	t.Helper()
	l, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatalf("mustGetFreePort: %v", err)
	}
	defer l.Close()
	return l.LocalAddr().(*net.UDPAddr).Port
}

// Горутины device.Device доживают до конца теста и продолжают логировать —
// t.Logf после завершения теста даёт гонку с самим testing. Поэтому логгер
// глохнет в Cleanup: он выполняется до того, как тест помечен завершённым.
func testLogger(t *testing.T, tag string) *device.Logger {
	var mu sync.Mutex
	finished := false
	t.Cleanup(func() {
		mu.Lock()
		finished = true
		mu.Unlock()
	})
	logf := func(prefix string) func(string, ...any) {
		return func(format string, args ...any) {
			mu.Lock()
			defer mu.Unlock()
			if finished {
				return
			}
			t.Logf("["+tag+prefix+"] "+format, args...)
		}
	}
	return &device.Logger{Verbosef: logf(""), Errorf: logf(" ERR")}
}

// minimalIPv4Packet — на отправку WG (device/send.go RoutineReadFromTUN)
// смотрит только на version-нибл и байты dst по фиксированному смещению, но
// на ПРИЁМЕ (device/receive.go) уже валидирует Total Length (обрезает пакет
// по нему и требует >= 20 байт) и src против AllowedIPs пира — без этих двух
// полей decrypt-путь молча дропает пакет без единого лога.
func minimalIPv4Packet(src, dst net.IP, payload byte) []byte {
	const size = 24
	pkt := make([]byte, size)
	pkt[0] = 0x45 // version=4, IHL=5 (20 байт)
	binary.BigEndian.PutUint16(pkt[2:4], uint16(size))
	pkt[9] = 17 // UDP, не важно для маршрутизации
	copy(pkt[12:16], src.To4())
	copy(pkt[16:20], dst.To4())
	pkt[20] = payload
	return pkt
}

func waitFor(t *testing.T, timeout time.Duration, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !cond() {
		t.Fatalf("условие не выполнилось за %s", timeout)
	}
}

// TestEndToEnd_PassThrough поднимает полную дорогу из плана:
//
//	[fake AmneziaWG] --wg--> [наш responder] --pipe--> [наш initiator] --wg--> [fake VPS]
//
// и проверяет, что IP-пакет, отправленный из fake AmneziaWG, доходит до fake
// VPS через оба хендшейка и трубу между девайсами, и что ответ идёт обратно.
// "Апстрим-релей" не эмулируется отдельным процессом — как и в проде,
// внешний девайс шлёт обычный UDP на loopback-порт, а сам релей лишь
// перекладывает байты 1:1 (internal/proxy/udprelay, не наш код), так что
// fake VPS слушает прямо на relayAddr.
func TestEndToEnd_PassThrough(t *testing.T) {
	clientPriv, clientPub := genKeypair(t)
	localPriv, localPub := genKeypair(t)
	remotePriv, remotePub := genKeypair(t)
	vpsPriv, vpsPub := genKeypair(t)

	listenPort := mustGetFreePort(t)
	relayPort := mustGetFreePort(t)
	relayAddr := fmt.Sprintf("127.0.0.1:%d", relayPort)

	// --- fake VPS: слушает прямо на relayAddr, как обычный WG-сервер. Поднимается
	// первым: forcedPersistentKeepalive (план, фаза 1) шлёт хендшейк-инициацию сразу
	// по Up() внешней половины сессии, не дожидаясь исходящего пакета — как и в
	// проде, где relay уже слушает к моменту запуска ftun, VPS должен быть готов
	// принять этот первый хендшейк, а не только "ленивый", вызванный данными.
	vpsTun, vpsTest := NewPipe(1280)
	vpsBind := NewLoopbackBind()
	vpsDev := device.NewDevice(vpsTun, vpsBind, testLogger(t, "vps"))
	defer vpsDev.Close()
	vpsUAPI, err := (InterfaceConf{PrivateKey: vpsPriv, ListenPort: relayPort}).BuildUAPI([]PeerConf{{
		PublicKey:  remotePub,
		AllowedIPs: []string{"0.0.0.0/0"},
	}})
	if err != nil {
		t.Fatalf("vps BuildUAPI: %v", err)
	}
	if err := vpsDev.IpcSet(vpsUAPI); err != nil {
		t.Fatalf("vps IpcSet: %v", err)
	}
	if err := vpsDev.Up(); err != nil {
		t.Fatalf("vps Up: %v", err)
	}

	// --- наша сессия (device.go): responder на listenPort, initiator наружу на relayAddr ---
	remoteConf := fmt.Sprintf(
		"[Interface]\nPrivateKey = %s\n[Peer]\nPublicKey = %s\nAllowedIPs = 0.0.0.0/0\n",
		remotePriv, vpsPub,
	)
	cfg := StartConfig{
		RemoteConf:         remoteConf,
		LocalPrivateKey:    localPriv,
		LocalPeerPublicKey: clientPub,
		RelayAddr:          relayAddr,
		ListenPort:         listenPort,
		MTU:                1280,
	}
	sess, err := newSession(cfg, testLogger(t, "session"))
	if err != nil {
		t.Fatalf("newSession: %v", err)
	}
	defer sess.close()

	// --- fake AmneziaWG: отдельный device.Device, говорящий с нашим responder'ом ---
	clientTun, clientTest := NewPipe(1280)
	clientDev := device.NewDevice(clientTun, NewLoopbackBind(), testLogger(t, "client"))
	defer clientDev.Close()
	clientUAPI, err := (InterfaceConf{PrivateKey: clientPriv}).BuildUAPI([]PeerConf{{
		PublicKey:  localPub,
		Endpoint:   fmt.Sprintf("127.0.0.1:%d", listenPort),
		AllowedIPs: []string{"0.0.0.0/0"},
	}})
	if err != nil {
		t.Fatalf("client BuildUAPI: %v", err)
	}
	if err := clientDev.IpcSet(clientUAPI); err != nil {
		t.Fatalf("client IpcSet: %v", err)
	}
	if err := clientDev.Up(); err != nil {
		t.Fatalf("client Up: %v", err)
	}

	// Клиент шлёт IP-пакет в сторону 10.0.0.1, запуская хендшейк на локальной
	// половине (у внешней половины он уже мог уйти проактивно, см. выше).
	pkt := minimalIPv4Packet(net.ParseIP("10.8.0.2"), net.ParseIP("10.0.0.1"), 0xAA)
	if _, err := clientTest.Write([][]byte{pkt}, 0); err != nil {
		t.Fatalf("clientTest.Write: %v", err)
	}

	bufs := [][]byte{make([]byte, 1280)}
	sizes := []int{0}
	readTimeout := func(dev tunReader, label string) []byte {
		type result struct {
			n   int
			err error
		}
		ch := make(chan result, 1)
		go func() {
			n, err := dev.Read(bufs, sizes, 0)
			ch <- result{n, err}
		}()
		select {
		case r := <-ch:
			if r.err != nil {
				t.Fatalf("%s.Read: %v", label, r.err)
			}
			out := make([]byte, sizes[0])
			copy(out, bufs[0][:sizes[0]])
			return out
		case <-time.After(5 * time.Second):
			t.Fatalf("%s.Read: таймаут — пакет не дошёл", label)
			return nil
		}
	}

	got := readTimeout(vpsTest, "vpsTest")
	if len(got) < 21 || got[20] != 0xAA {
		t.Fatalf("VPS получил не тот пакет: % x", got)
	}

	// Ответ идёт обратно тем же путём.
	reply := minimalIPv4Packet(net.ParseIP("10.0.0.1"), net.ParseIP("10.8.0.2"), 0xBB)
	if _, err := vpsTest.Write([][]byte{reply}, 0); err != nil {
		t.Fatalf("vpsTest.Write: %v", err)
	}
	gotReply := readTimeout(clientTest, "clientTest")
	if len(gotReply) < 21 || gotReply[20] != 0xBB {
		t.Fatalf("клиент получил не тот ответ: % x", gotReply)
	}

	// Обе половины дороги должны показывать живой хендшейк.
	waitFor(t, 2*time.Second, func() bool {
		up, age, _, _, err := sess.local.stats()
		return err == nil && up && age >= 0
	})
	waitFor(t, 2*time.Second, func() bool {
		up, age, _, _, err := sess.remote.stats()
		return err == nil && up && age >= 0
	})
}

type tunReader interface {
	Read(bufs [][]byte, sizes []int, offset int) (int, error)
}

// TestNewSession_ForcesPersistentKeepalive — план, фаза 1: keepalive
// принудительно проставляется на обе половины независимо от того, что было
// (или не было) в пользовательском remoteConf, иначе amneziawg-go сдаётся
// навсегда после серии неудачных хендшейков и не восстанавливается сам.
func TestNewSession_ForcesPersistentKeepalive(t *testing.T) {
	_, clientPub := genKeypair(t)
	localPriv, _ := genKeypair(t)
	remotePriv, _ := genKeypair(t)
	_, vpsPub := genKeypair(t)

	// PersistentKeepalive не задан в .conf — реалистичный случай, дефолт
	// пользовательских конфигов.
	remoteConf := fmt.Sprintf(
		"[Interface]\nPrivateKey = %s\n[Peer]\nPublicKey = %s\nAllowedIPs = 0.0.0.0/0\n",
		remotePriv, vpsPub,
	)
	cfg := StartConfig{
		RemoteConf:         remoteConf,
		LocalPrivateKey:    localPriv,
		LocalPeerPublicKey: clientPub,
		RelayAddr:          "127.0.0.1:1", // не набирается в этом тесте — только сборка UAPI
		ListenPort:         mustGetFreePort(t),
		MTU:                1280,
	}
	sess, err := newSession(cfg, testLogger(t, "session"))
	if err != nil {
		t.Fatalf("newSession: %v", err)
	}
	defer sess.close()

	localUAPI, err := sess.local.device.IpcGet()
	if err != nil {
		t.Fatalf("local IpcGet: %v", err)
	}
	if !strings.Contains(localUAPI, "persistent_keepalive_interval=25\n") {
		t.Fatalf("local UAPI без форсированного keepalive:\n%s", localUAPI)
	}

	remoteUAPI, err := sess.remote.device.IpcGet()
	if err != nil {
		t.Fatalf("remote IpcGet: %v", err)
	}
	if !strings.Contains(remoteUAPI, "persistent_keepalive_interval=25\n") {
		t.Fatalf("remote UAPI без форсированного keepalive:\n%s", remoteUAPI)
	}
}

// TestNudge_NoActiveSession — Nudge() (api.go) обязан быть безопасным no-op
// без запущенной сессии: лестница восстановления в ProxyManager может
// вызвать его в состоянии гонки со Stop().
func TestNudge_NoActiveSession(t *testing.T) {
	Stop() // на случай, если предыдущий тест в этом же процессе оставил сессию
	Nudge()
}

// TestSession_Nudge — session.nudge() не паникует на реальной сессии (обе
// половины поднялись, LookupPeer находит пира по сохранённому ключу).
func TestSession_Nudge(t *testing.T) {
	_, clientPub := genKeypair(t)
	localPriv, _ := genKeypair(t)
	remotePriv, _ := genKeypair(t)
	_, vpsPub := genKeypair(t)

	remoteConf := fmt.Sprintf(
		"[Interface]\nPrivateKey = %s\n[Peer]\nPublicKey = %s\nAllowedIPs = 0.0.0.0/0\n",
		remotePriv, vpsPub,
	)
	cfg := StartConfig{
		RemoteConf:         remoteConf,
		LocalPrivateKey:    localPriv,
		LocalPeerPublicKey: clientPub,
		RelayAddr:          "127.0.0.1:1",
		ListenPort:         mustGetFreePort(t),
		MTU:                1280,
	}
	sess, err := newSession(cfg, testLogger(t, "session"))
	if err != nil {
		t.Fatalf("newSession: %v", err)
	}
	defer sess.close()

	sess.nudge()
}
