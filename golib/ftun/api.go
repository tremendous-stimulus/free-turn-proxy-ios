// Package ftun — локальная терминация WG-in-WG (см.
// /Users/stepan/.claude/plans/vpn-lexical-rossum.md, фаза 1). gomobile-фасад
// этого файла — единственная точка входа для Swift-слоя (по аналогии с
// mobile/api.go апстрима и Sources/FreeTurnProxy/Services/MobileAPI.swift):
// пакет ftun → ObjC-префикс Ftun*.
package ftun

import (
	"encoding/json"
	"fmt"
	"sync"

	"github.com/amnezia-vpn/amneziawg-go/device"
)

// EventSink — приёмник логов и статуса от обоих девайсов. Реализуется на
// стороне Swift (аналог MobileEventSinkProtocol), см. EventSinkBridge.
type EventSink interface {
	// OnLog может прийти из любой горутины — реализация обязана быть
	// потокобезопасной и не блокировать вызывающего.
	OnLog(half string, level string, msg string)
}

// Snapshot — состояние обеих половин дороги, отдаётся поллингом (см. план,
// раздел "TunnelState" в фазе 2). Только плоские поля — gomobile не умеет
// экспортировать вложенные структуры без доп. геттеров.
type Snapshot struct {
	LocalUp               bool
	LocalHandshakeAgeSec  int64
	LocalTxBytes          int64
	LocalRxBytes          int64
	RemoteUp              bool
	RemoteHandshakeAgeSec int64
	RemoteTxBytes         int64
	RemoteRxBytes         int64
}

var (
	mu      sync.Mutex // защищает current — сессию нельзя трогать из Logger-колбэков, см. loggerFunc
	current *session

	sinkMu sync.Mutex // отдельный мьютекс: логгер зовётся синхронно изнутри newSession под mu
	sink   EventSink
)

// SetEventSink регистрирует приёмник логов до Start(). nil — отключить.
func SetEventSink(s EventSink) {
	sinkMu.Lock()
	defer sinkMu.Unlock()
	sink = s
}

// Start поднимает обе половины дороги. cfgJSON — StartConfig в JSON. Если
// сессия уже запущена, сначала останавливает её (идемпотентно, как
// MobileStart/MobileRestart у ядра v2).
func Start(cfgJSON string) error {
	var cfg StartConfig
	if err := json.Unmarshal([]byte(cfgJSON), &cfg); err != nil {
		return fmt.Errorf("невалидный JSON конфига: %w", err)
	}

	mu.Lock()
	defer mu.Unlock()

	if current != nil {
		current.close()
		current = nil
	}

	logger := &device.Logger{
		Verbosef: loggerFunc("verbose"),
		Errorf:   loggerFunc("error"),
	}

	s, err := newSession(cfg, logger)
	if err != nil {
		return err
	}
	current = s
	return nil
}

// Stop останавливает обе половины. Безопасно вызывать без предшествующего
// Start (нет активной сессии — no-op), как MobileStop.
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	if current == nil {
		return
	}
	current.close()
	current = nil
}

// Nudge — программный эквивалент тумблера AmneziaWG (план, фаза 1):
// заново взводит ретрансмит хендшейка на обеих половинах. Дешёвая ступень
// восстановления — не пересоздаёт сессию, не трогает конфиг. No-op, если
// сессия не запущена.
func Nudge() {
	mu.Lock()
	s := current
	mu.Unlock()
	if s == nil {
		return
	}
	s.nudge()
}

// Stats возвращает nil, если сессия не запущена.
func Stats() *Snapshot {
	mu.Lock()
	s := current
	mu.Unlock()
	if s == nil {
		return nil
	}

	localUp, localAge, localTx, localRx, err := s.local.stats()
	if err != nil {
		return nil
	}
	remoteUp, remoteAge, remoteTx, remoteRx, err := s.remote.stats()
	if err != nil {
		return nil
	}

	return &Snapshot{
		LocalUp:               localUp,
		LocalHandshakeAgeSec:  localAge,
		LocalTxBytes:          localTx,
		LocalRxBytes:          localRx,
		RemoteUp:              remoteUp,
		RemoteHandshakeAgeSec: remoteAge,
		RemoteTxBytes:         remoteTx,
		RemoteRxBytes:         remoteRx,
	}
}

func Version() string { return "ftun/0.1.0-dev" }

// loggerFunc заворачивает device.Logger-callback в вызов текущего EventSink.
// half в логах device.Device не различим на уровне Printf-формата, поэтому
// тег half передаётся через замыкание на месте создания Logger (см.
// newSession — оба device.Device делят один и тот же logger в фазе 1; если
// в будущем понадобится различать источник в UI, замыкание надо завести
// по одному на девайс).
func loggerFunc(level string) func(format string, args ...any) {
	return func(format string, args ...any) {
		sinkMu.Lock()
		s := sink
		sinkMu.Unlock()
		if s == nil {
			return
		}
		s.OnLog("", level, fmt.Sprintf(format, args...))
	}
}
