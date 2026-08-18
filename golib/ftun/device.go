package ftun

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/device"
)

// StartConfig — вход Start() (api.go), приходит из Swift-слоя как JSON.
// Наши собственные ключи (LocalPrivateKey/LocalPeerPublicKey) генерирует
// LocalTunnelIdentity в фазе 2, а не этот модуль — здесь только оркестрация
// двух WG-девайсов. Address/DNS для локального .conf, который уходит в
// AmneziaWG, тоже собирает Swift-слой (LocalConfigBuilder): это чисто
// клиентская WG-настройка ОС, наш roundtrip-движок про неё ничего не знает.
type StartConfig struct {
	// RemoteConf — текст реального wg/awg .conf пользователя целиком.
	RemoteConf string `json:"remoteConf"`
	// LocalPrivateKey — base64, приватный ключ локального responder'а.
	LocalPrivateKey string `json:"localPrivateKey"`
	// LocalPeerPublicKey — base64, публичный ключ клиента, которому
	// разрешено подключаться к responder'у (тот, что уходит в AmneziaWG).
	LocalPeerPublicKey string `json:"localPeerPublicKey"`
	// RelayAddr — адрес апстрим-релея ядра v2 (CoreConfig.Proxy.listen),
	// например "127.0.0.1:9001". Подставляется вместо Endpoint из RemoteConf.
	RelayAddr string `json:"relayAddr"`
	// ListenPort — порт локального responder'а, например 9000.
	ListenPort int `json:"listenPort"`
	// MTU — общий для обоих девайсов; см. план, раздел "MTU".
	MTU int `json:"mtu"`
	// BypassCIDRs — назначения, которые роутер уводит мимо туннеля (план,
	// фаза 5.2): подсети VK и приватные диапазоны. Пустой список = поведение
	// фазы 1, весь трафик в туннель.
	BypassCIDRs []string `json:"bypassCIDRs"`
	// BypassExcludeCIDRs перебивает BypassCIDRs — сюда идёт сеть самого
	// VPN-сервера, иначе она попала бы под «приватное мимо туннеля».
	BypassExcludeCIDRs []string `json:"bypassExcludeCIDRs"`
}

func (c StartConfig) validate() error {
	if strings.TrimSpace(c.RemoteConf) == "" {
		return fmt.Errorf("remoteConf пуст")
	}
	if err := validateKey(c.LocalPrivateKey); err != nil {
		return fmt.Errorf("localPrivateKey: %w", err)
	}
	if err := validateKey(c.LocalPeerPublicKey); err != nil {
		return fmt.Errorf("localPeerPublicKey: %w", err)
	}
	if strings.TrimSpace(c.RelayAddr) == "" {
		return fmt.Errorf("relayAddr пуст")
	}
	if c.ListenPort <= 0 || c.ListenPort > 65535 {
		return fmt.Errorf("listenPort вне диапазона: %d", c.ListenPort)
	}
	if c.MTU <= 0 {
		return fmt.Errorf("mtu должен быть положительным: %d", c.MTU)
	}
	return nil
}

// forcedPersistentKeepalive — вопреки .conf пользователя и умолчанию,
// keepalive всегда включён на ВНЕШНЕЙ половине. Без него amneziawg-go
// сдаётся навсегда после MaxTimerHandshakes неудачных хендшейков
// (device/timers.go: expiredRetransmitHandshake) и не восстанавливается сам
// даже когда причина обрыва (смена сети, кратковременный дроп) уже прошла —
// см. план /Users/stepan/.claude/plans/swirling-spinning-meteor.md, причина
// №1. Keepalive перевзводит ретрансмит хендшейка на каждый пакет
// (timersAnyAuthenticatedPacketTraversal), поэтому «giving up» перестаёт
// быть терминальным.
//
// На ЛОКАЛЬНОЙ половине его ставить нельзя, и это не вкусовщина. Локальная
// половина — responder: Endpoint её пира (AmneziaWG на устройстве) неизвестен,
// пока клиент сам не пришлёт первый хендшейк. А device.upLocked() при
// ненулевом keepalive дёргает SendKeepalive() сразу по Up() → нет keypair →
// SendHandshakeInitiation → SendBuffers → "no known endpoint for peer" →
// device.Logger.Errorf. Дальше самоподдерживающийся цикл: ретрансмит каждые
// 5с (18 попыток), «giving up» гасит sendKeepalive, но НЕ persistentKeepalive,
// тот через 25с снова зовёт SendKeepalive → handshakeAttempts сбрасывается
// в 0 → по кругу. Пока пользователь не включил VPN (нормальный порядок
// действий!), это бесконечный поток ERR в логах и в телеметрии.
//
// Направление, которое реально надо держать живым, — клиент → ftun, и оно
// закрывается строкой PersistentKeepalive в конфиге, который мы отдаём в
// AmneziaWG (Sources/.../LocalConfigBuilder.swift): там инициатор, и он
// endpoint знает.
const forcedPersistentKeepalive = 25

// half — одна из двух половин дороги (см. план, раздел "Экран туннеля").
type half struct {
	device *device.Device
	// peerKeys — публичные ключи пиров этой половины, для Nudge() (api.go):
	// программный аналог тумблера AmneziaWG, LookupPeer+SendHandshakeInitiation
	// на сдавшемся пире. Заполнены только у внешней половины — локальную
	// пинать нечем и незачем, см. session.nudge.
	peerKeys []device.NoisePublicKey
}

// nudge шлёт свежую (не-retry) инициацию хендшейка каждому пиру половины —
// SendHandshakeInitiation(isRetry: false) сбрасывает handshakeAttempts, то
// есть заново взводит ретрансмиты у пира, который уже "giving up". No-op,
// если пир не найден (например, устройство уже закрыто).
func (h *half) nudge() {
	for _, pk := range h.peerKeys {
		if peer := h.device.LookupPeer(pk); peer != nil {
			peer.SendHandshakeInitiation(false)
		}
	}
}

func keyToNoisePublicKey(base64Key string) (device.NoisePublicKey, error) {
	var pk device.NoisePublicKey
	hexKey, err := keyToHex(base64Key)
	if err != nil {
		return pk, err
	}
	if err := pk.FromHex(hexKey); err != nil {
		return pk, fmt.Errorf("NoisePublicKey: %w", err)
	}
	return pk, nil
}

func (h *half) stats() (up bool, handshakeAgeSec int64, txBytes, rxBytes int64, err error) {
	raw, err := h.device.IpcGet()
	if err != nil {
		return false, 0, 0, 0, err
	}
	return parseIpcStats(raw)
}

// parseIpcStats достаёт только то, что нужно Stats() (api.go): само наличие
// секции пира уже значит, что девайс поднят; свежий handshake — что он жив.
func parseIpcStats(raw string) (up bool, handshakeAgeSec int64, txBytes, rxBytes int64, err error) {
	var handshakeSec int64
	for _, line := range strings.Split(raw, "\n") {
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		switch key {
		case "public_key":
			up = true
		case "last_handshake_time_sec":
			handshakeSec, err = strconv.ParseInt(value, 10, 64)
			if err != nil {
				return false, 0, 0, 0, fmt.Errorf("last_handshake_time_sec: %w", err)
			}
		case "tx_bytes":
			v, err2 := strconv.ParseInt(value, 10, 64)
			if err2 != nil {
				return false, 0, 0, 0, fmt.Errorf("tx_bytes: %w", err2)
			}
			txBytes += v
		case "rx_bytes":
			v, err2 := strconv.ParseInt(value, 10, 64)
			if err2 != nil {
				return false, 0, 0, 0, fmt.Errorf("rx_bytes: %w", err2)
			}
			rxBytes += v
		}
	}
	if handshakeSec == 0 {
		return up, 0, txBytes, rxBytes, nil
	}
	return up, time.Now().Unix() - handshakeSec, txBytes, rxBytes, nil
}

// session — обе половины дороги плюс труба между ними (pipe.go). Владеет
// временем жизни обоих device.Device; закрывается только целиком.
type session struct {
	local  half // responder: AmneziaWG (127.0.0.1:<ListenPort>) ↔ router
	remote half // initiator: router ↔ апстрим-релей (RelayAddr)
	router *router
}

func newSession(cfg StartConfig, logger *device.Logger) (*session, error) {
	if err := cfg.validate(); err != nil {
		return nil, err
	}
	remoteConf, err := ParseConf(cfg.RemoteConf)
	if err != nil {
		return nil, fmt.Errorf("не удалось разобрать remoteConf: %w", err)
	}

	localTun := newEndpoint("ftun-local", cfg.MTU)
	remoteTun := newEndpoint("ftun-remote", cfg.MTU)

	// Стек обхода поднимаем только когда есть что обходить: без него роутер
	// вырождается в pass-through фазы 1, и лишний userspace-стек в памяти
	// висеть не должен.
	bypass := NewBypassSet(cfg.BypassCIDRs, cfg.BypassExcludeCIDRs)
	var stk *bypassStack
	if !bypass.IsEmpty() {
		var err error
		stk, err = newBypassStack(cfg.MTU, func(format string, args ...any) {
			logger.Verbosef(format, args...)
		})
		if err != nil {
			return nil, fmt.Errorf("не удалось поднять стек обхода: %w", err)
		}
	}
	rt := newRouter(localTun, remoteTun, bypass, stk)

	localIface := InterfaceConf{
		PrivateKey: cfg.LocalPrivateKey,
		ListenPort: cfg.ListenPort,
	}
	// Без PersistentKeepalive — см. комментарий к forcedPersistentKeepalive:
	// у responder'а нет endpoint'а пира до первого хендшейка клиента.
	localPeers := []PeerConf{{
		PublicKey:  cfg.LocalPeerPublicKey,
		AllowedIPs: []string{"0.0.0.0/0", "::/0"},
	}}
	localUAPI, err := localIface.BuildUAPI(localPeers)
	if err != nil {
		rt.close()
		return nil, fmt.Errorf("не удалось собрать UAPI локального девайса: %w", err)
	}

	localDev := device.NewDevice(localTun, NewLoopbackBind(), logger)
	if err := localDev.IpcSet(localUAPI); err != nil {
		localDev.Close()
		remoteTun.Close()
		rt.close()
		return nil, fmt.Errorf("IpcSet локального девайса: %w", err)
	}

	remotePeers := make([]PeerConf, len(remoteConf.Peers))
	for i, p := range remoteConf.Peers {
		p.Endpoint = cfg.RelayAddr // апстрим всегда идёт через локальный релей, не напрямую
		p.PersistentKeepalive = forcedPersistentKeepalive
		remotePeers[i] = p
	}
	remoteIface := remoteConf.Interface
	remoteIface.ListenPort = 0 // эфемерный порт на loopback, наружу не публикуется
	remoteUAPI, err := remoteIface.BuildUAPI(remotePeers)
	if err != nil {
		localDev.Close()
		remoteTun.Close()
		rt.close()
		return nil, fmt.Errorf("не удалось собрать UAPI внешнего девайса: %w", err)
	}
	remotePeerKeys, err := peerKeysOf(remotePeers)
	if err != nil {
		localDev.Close()
		remoteTun.Close()
		rt.close()
		return nil, fmt.Errorf("ключи пиров внешнего девайса: %w", err)
	}

	remoteDev := device.NewDevice(remoteTun, NewLoopbackBind(), logger)
	if err := remoteDev.IpcSet(remoteUAPI); err != nil {
		localDev.Close()
		remoteDev.Close()
		rt.close()
		return nil, fmt.Errorf("IpcSet внешнего девайса: %w", err)
	}

	if err := localDev.Up(); err != nil {
		localDev.Close()
		remoteDev.Close()
		rt.close()
		return nil, fmt.Errorf("Up локального девайса: %w", err)
	}
	if err := remoteDev.Up(); err != nil {
		localDev.Close()
		remoteDev.Close()
		rt.close()
		return nil, fmt.Errorf("Up внешнего девайса: %w", err)
	}

	rt.start()

	return &session{
		local:  half{device: localDev},
		remote: half{device: remoteDev, peerKeys: remotePeerKeys},
		router: rt,
	}, nil
}

func peerKeysOf(peers []PeerConf) ([]device.NoisePublicKey, error) {
	keys := make([]device.NoisePublicKey, len(peers))
	for i, p := range peers {
		pk, err := keyToNoisePublicKey(p.PublicKey)
		if err != nil {
			return nil, fmt.Errorf("[Peer] #%d: %w", i, err)
		}
		keys[i] = pk
	}
	return keys, nil
}

// nudge — см. half.nudge. Пинаем только внешнюю половину: ступень 0 лестницы
// восстановления по плану (фаза 2.3) адресована именно ей («remote-половина
// молчит»), а инициация в сторону локального пира до того, как пользователь
// включил AmneziaWG, — гарантированный "no known endpoint for peer" на уровне
// Errorf плюс сброс handshakeAttempts, то есть новая серия ретрансмитов в
// пустоту (см. комментарий к forcedPersistentKeepalive).
func (s *session) nudge() {
	s.remote.nudge()
}

func (s *session) close() {
	// localTun/remoteTun закрываются самим device.Device.Close() — он
	// закрывает переданный ему tun.Device; роутер выходит по их closeCh.
	s.local.device.Close()
	s.remote.device.Close()
	s.router.close()
}
