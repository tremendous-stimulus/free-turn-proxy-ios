package ftun

import (
	"bufio"
	"fmt"
	"strconv"
	"strings"
)

// Парсер wg/awg .conf (INI-подобный формат) в структуру, из которой строится
// UAPI-конфиг для amneziawg-go. В отличие от ConfigPatcher (Swift-слой,
// Sources/FreeTurnProxy/Services/ConfigPatcher.swift), который сегодня лишь
// транзитит .conf как текст, здесь поля реально разбираются и валидируются —
// в т.ч. Amnezia-поля Jc/Jmin/Jmax/S1-S4/H1-H4/I1-I5, которых конфиг не знал.

// InterfaceConf — секция [Interface].
type InterfaceConf struct {
	PrivateKey string // base64, 32 байта
	Address    []string
	DNS        []string
	MTU        int
	ListenPort int

	// AmneziaWG obfuscation-поля. Нулевое значение = не задано = не шлём в UAPI.
	Jc, Jmin, Jmax     int
	S1, S2, S3, S4     int
	H1, H2, H3, H4     string
	I1, I2, I3, I4, I5 string
}

// PeerConf — секция [Peer]. .conf допускает несколько таких секций подряд.
type PeerConf struct {
	PublicKey           string // base64, 32 байта
	PresharedKey        string // base64, 32 байта; пусто = не используется
	Endpoint            string
	AllowedIPs          []string
	PersistentKeepalive int
}

// Conf — итог разбора всего файла.
type Conf struct {
	Interface InterfaceConf
	Peers     []PeerConf
}

// ParseConf разбирает текст .conf. Синтаксис: секции [Interface]/[Peer],
// строки "Ключ = значение", ";"/"#" — комментарии, пустые строки игнорируются.
// Списковые поля (Address/DNS/AllowedIPs) — через запятую внутри одной строки,
// как в оригинальном wg(8)-формате.
func ParseConf(text string) (*Conf, error) {
	conf := &Conf{}
	var currentPeer *PeerConf
	inInterface := false
	haveInterface := false

	scanner := bufio.NewScanner(strings.NewReader(text))
	for scanner.Scan() {
		line := stripComment(scanner.Text())
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		if strings.HasPrefix(line, "[") {
			section := strings.ToLower(strings.TrimSpace(strings.Trim(line, "[]")))
			switch section {
			case "interface":
				inInterface = true
				haveInterface = true
				currentPeer = nil
			case "peer":
				inInterface = false
				conf.Peers = append(conf.Peers, PeerConf{})
				currentPeer = &conf.Peers[len(conf.Peers)-1]
			default:
				return nil, fmt.Errorf("неизвестная секция %q", line)
			}
			continue
		}

		key, value, ok := strings.Cut(line, "=")
		if !ok {
			return nil, fmt.Errorf("не удалось разобрать строку %q", line)
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)

		var err error
		if inInterface {
			err = setInterfaceField(&conf.Interface, key, value)
		} else if currentPeer != nil {
			err = setPeerField(currentPeer, key, value)
		} else {
			return nil, fmt.Errorf("строка %q вне секции [Interface]/[Peer]", line)
		}
		if err != nil {
			return nil, err
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}

	if !haveInterface {
		return nil, fmt.Errorf("в конфиге нет секции [Interface]")
	}
	if err := validateKey(conf.Interface.PrivateKey); err != nil {
		return nil, fmt.Errorf("[Interface] PrivateKey: %w", err)
	}
	if len(conf.Peers) == 0 {
		return nil, fmt.Errorf("в конфиге нет ни одной секции [Peer]")
	}
	for i := range conf.Peers {
		p := &conf.Peers[i]
		if err := validateKey(p.PublicKey); err != nil {
			return nil, fmt.Errorf("[Peer] #%d PublicKey: %w", i, err)
		}
		if p.PresharedKey != "" {
			if err := validateKey(p.PresharedKey); err != nil {
				return nil, fmt.Errorf("[Peer] #%d PresharedKey: %w", i, err)
			}
		}
	}

	return conf, nil
}

// BuildUAPI сериализует связку "наш приватный ключ интерфейса + список
// пиров" в текст UAPI-протокола amneziawg-go (device.Device.IpcSet). Используется
// для обоих девайсов: и для внешнего (реальные PrivateKey/obfuscation-поля из
// пользовательского .conf, Endpoint пира подменён на адрес релея), и для
// локального responder'а (синтетические ключи из LocalTunnelIdentity, без
// Amnezia-полей — внутренний туннель ванильный).
//
// Формат протокола: https://www.wireguard.com/xplatform/#configuration-protocol
func (i InterfaceConf) BuildUAPI(peers []PeerConf) (string, error) {
	privHex, err := keyToHex(i.PrivateKey)
	if err != nil {
		return "", fmt.Errorf("PrivateKey: %w", err)
	}

	var b strings.Builder
	fmt.Fprintf(&b, "private_key=%s\n", privHex)
	if i.ListenPort != 0 {
		fmt.Fprintf(&b, "listen_port=%d\n", i.ListenPort)
	}
	b.WriteString("replace_peers=true\n")

	writeIntIfSet(&b, "jc", i.Jc)
	writeIntIfSet(&b, "jmin", i.Jmin)
	writeIntIfSet(&b, "jmax", i.Jmax)
	writeIntIfSet(&b, "s1", i.S1)
	writeIntIfSet(&b, "s2", i.S2)
	writeIntIfSet(&b, "s3", i.S3)
	writeIntIfSet(&b, "s4", i.S4)
	writeStrIfSet(&b, "h1", i.H1)
	writeStrIfSet(&b, "h2", i.H2)
	writeStrIfSet(&b, "h3", i.H3)
	writeStrIfSet(&b, "h4", i.H4)
	writeStrIfSet(&b, "i1", i.I1)
	writeStrIfSet(&b, "i2", i.I2)
	writeStrIfSet(&b, "i3", i.I3)
	writeStrIfSet(&b, "i4", i.I4)
	writeStrIfSet(&b, "i5", i.I5)

	for idx, p := range peers {
		pubHex, err := keyToHex(p.PublicKey)
		if err != nil {
			return "", fmt.Errorf("[Peer] #%d PublicKey: %w", idx, err)
		}
		fmt.Fprintf(&b, "public_key=%s\n", pubHex)
		if p.PresharedKey != "" {
			pskHex, err := keyToHex(p.PresharedKey)
			if err != nil {
				return "", fmt.Errorf("[Peer] #%d PresharedKey: %w", idx, err)
			}
			fmt.Fprintf(&b, "preshared_key=%s\n", pskHex)
		}
		if p.Endpoint != "" {
			fmt.Fprintf(&b, "endpoint=%s\n", p.Endpoint)
		}
		fmt.Fprintf(&b, "persistent_keepalive_interval=%d\n", p.PersistentKeepalive)
		if len(p.AllowedIPs) == 0 {
			return "", fmt.Errorf("[Peer] #%d: пустой AllowedIPs", idx)
		}
		for _, ip := range p.AllowedIPs {
			fmt.Fprintf(&b, "allowed_ip=%s\n", ip)
		}
	}

	return b.String(), nil
}

func writeIntIfSet(b *strings.Builder, key string, v int) {
	if v != 0 {
		fmt.Fprintf(b, "%s=%d\n", key, v)
	}
}

func writeStrIfSet(b *strings.Builder, key, v string) {
	if v != "" {
		fmt.Fprintf(b, "%s=%s\n", key, v)
	}
}

func stripComment(line string) string {
	for _, c := range []byte{';', '#'} {
		if idx := strings.IndexByte(line, c); idx >= 0 {
			line = line[:idx]
		}
	}
	return line
}

func splitList(value string) []string {
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func setInterfaceField(i *InterfaceConf, key, value string) error {
	var err error
	switch strings.ToLower(key) {
	case "privatekey":
		i.PrivateKey = value
	case "address":
		i.Address = append(i.Address, splitList(value)...)
	case "dns":
		i.DNS = append(i.DNS, splitList(value)...)
	case "mtu":
		i.MTU, err = strconv.Atoi(value)
	case "listenport":
		i.ListenPort, err = strconv.Atoi(value)
	case "jc":
		i.Jc, err = strconv.Atoi(value)
	case "jmin":
		i.Jmin, err = strconv.Atoi(value)
	case "jmax":
		i.Jmax, err = strconv.Atoi(value)
	case "s1":
		i.S1, err = strconv.Atoi(value)
	case "s2":
		i.S2, err = strconv.Atoi(value)
	case "s3":
		i.S3, err = strconv.Atoi(value)
	case "s4":
		i.S4, err = strconv.Atoi(value)
	case "h1":
		i.H1 = value
	case "h2":
		i.H2 = value
	case "h3":
		i.H3 = value
	case "h4":
		i.H4 = value
	case "i1":
		i.I1 = value
	case "i2":
		i.I2 = value
	case "i3":
		i.I3 = value
	case "i4":
		i.I4 = value
	case "i5":
		i.I5 = value
	default:
		// Незнакомые поля (Table, PostUp, SaveConfig, ...) молча игнорируем —
		// как и оригинальный ConfigPatcher, мы не система применения роутинга ОС.
	}
	if err != nil {
		return fmt.Errorf("[Interface] %s=%q: %w", key, value, err)
	}
	return nil
}

func setPeerField(p *PeerConf, key, value string) error {
	var err error
	switch strings.ToLower(key) {
	case "publickey":
		p.PublicKey = value
	case "presharedkey":
		p.PresharedKey = value
	case "endpoint":
		p.Endpoint = value
	case "allowedips":
		p.AllowedIPs = append(p.AllowedIPs, splitList(value)...)
	case "persistentkeepalive":
		p.PersistentKeepalive, err = strconv.Atoi(value)
	default:
		// PersistentKeepalive off / незнакомые поля.
	}
	if err != nil {
		return fmt.Errorf("[Peer] %s=%q: %w", key, value, err)
	}
	return nil
}
