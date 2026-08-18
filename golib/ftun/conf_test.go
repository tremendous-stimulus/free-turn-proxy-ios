package ftun

import (
	"encoding/base64"
	"strings"
	"testing"
)

func genB64Key(t *testing.T, seed byte) string {
	t.Helper()
	raw := make([]byte, 32)
	for i := range raw {
		raw[i] = seed
	}
	return base64.StdEncoding.EncodeToString(raw)
}

func TestParseConf_MinimalWireGuard(t *testing.T) {
	priv := genB64Key(t, 1)
	pub := genB64Key(t, 2)
	text := "[Interface]\n" +
		"PrivateKey = " + priv + "\n" +
		"Address = 10.8.0.2/32\n" +
		"DNS = 1.1.1.1\n" +
		"MTU = 1280\n" +
		"\n" +
		"[Peer]\n" +
		"PublicKey = " + pub + "\n" +
		"Endpoint = vpn.example.com:51820\n" +
		"AllowedIPs = 0.0.0.0/0, ::/0\n" +
		"PersistentKeepalive = 25\n"

	conf, err := ParseConf(text)
	if err != nil {
		t.Fatalf("ParseConf: %v", err)
	}
	if conf.Interface.PrivateKey != priv {
		t.Errorf("PrivateKey = %q, want %q", conf.Interface.PrivateKey, priv)
	}
	if len(conf.Interface.Address) != 1 || conf.Interface.Address[0] != "10.8.0.2/32" {
		t.Errorf("Address = %v", conf.Interface.Address)
	}
	if conf.Interface.MTU != 1280 {
		t.Errorf("MTU = %d, want 1280", conf.Interface.MTU)
	}
	if len(conf.Peers) != 1 {
		t.Fatalf("len(Peers) = %d, want 1", len(conf.Peers))
	}
	p := conf.Peers[0]
	if p.PublicKey != pub {
		t.Errorf("PublicKey = %q, want %q", p.PublicKey, pub)
	}
	if p.Endpoint != "vpn.example.com:51820" {
		t.Errorf("Endpoint = %q", p.Endpoint)
	}
	if len(p.AllowedIPs) != 2 || p.AllowedIPs[0] != "0.0.0.0/0" || p.AllowedIPs[1] != "::/0" {
		t.Errorf("AllowedIPs = %v", p.AllowedIPs)
	}
	if p.PersistentKeepalive != 25 {
		t.Errorf("PersistentKeepalive = %d, want 25", p.PersistentKeepalive)
	}
}

func TestParseConf_AmneziaFields(t *testing.T) {
	priv := genB64Key(t, 3)
	pub := genB64Key(t, 4)
	text := "[Interface]\n" +
		"PrivateKey = " + priv + "\n" +
		"Jc = 5\n" +
		"Jmin = 50\n" +
		"Jmax = 1000\n" +
		"S1 = 68\n" +
		"S2 = 88\n" +
		"H1 = 1234567\n" +
		"H2 = 2345678\n" +
		"H3 = 3456789\n" +
		"H4 = 4567890\n" +
		"\n" +
		"[Peer]\n" +
		"PublicKey = " + pub + "\n" +
		"AllowedIPs = 0.0.0.0/0\n"

	conf, err := ParseConf(text)
	if err != nil {
		t.Fatalf("ParseConf: %v", err)
	}
	i := conf.Interface
	if i.Jc != 5 || i.Jmin != 50 || i.Jmax != 1000 {
		t.Errorf("Jc/Jmin/Jmax = %d/%d/%d", i.Jc, i.Jmin, i.Jmax)
	}
	if i.S1 != 68 || i.S2 != 88 {
		t.Errorf("S1/S2 = %d/%d", i.S1, i.S2)
	}
	if i.H1 != "1234567" || i.H2 != "2345678" || i.H3 != "3456789" || i.H4 != "4567890" {
		t.Errorf("H1-H4 = %s/%s/%s/%s", i.H1, i.H2, i.H3, i.H4)
	}
}

func TestParseConf_MultiplePeers(t *testing.T) {
	priv := genB64Key(t, 5)
	pub1 := genB64Key(t, 6)
	pub2 := genB64Key(t, 7)
	text := "[Interface]\nPrivateKey = " + priv + "\n" +
		"[Peer]\nPublicKey = " + pub1 + "\nAllowedIPs = 10.0.0.0/24\n" +
		"[Peer]\nPublicKey = " + pub2 + "\nAllowedIPs = 10.0.1.0/24\n"

	conf, err := ParseConf(text)
	if err != nil {
		t.Fatalf("ParseConf: %v", err)
	}
	if len(conf.Peers) != 2 {
		t.Fatalf("len(Peers) = %d, want 2", len(conf.Peers))
	}
}

func TestParseConf_CommentsAndBlankLines(t *testing.T) {
	priv := genB64Key(t, 8)
	pub := genB64Key(t, 9)
	text := "; заголовок\n" +
		"[Interface]\n" +
		"PrivateKey = " + priv + " # инлайн-комментарий\n" +
		"\n" +
		"[Peer]\n" +
		"PublicKey = " + pub + "\n" +
		"AllowedIPs = 0.0.0.0/0\n"

	conf, err := ParseConf(text)
	if err != nil {
		t.Fatalf("ParseConf: %v", err)
	}
	if conf.Interface.PrivateKey != priv {
		t.Errorf("PrivateKey = %q, want %q (комментарий не отрезался)", conf.Interface.PrivateKey, priv)
	}
}

func TestParseConf_UnknownFieldsIgnored(t *testing.T) {
	priv := genB64Key(t, 10)
	pub := genB64Key(t, 11)
	text := "[Interface]\nPrivateKey = " + priv + "\nTable = off\nPostUp = iptables -A\n" +
		"[Peer]\nPublicKey = " + pub + "\nAllowedIPs = 0.0.0.0/0\n"

	if _, err := ParseConf(text); err != nil {
		t.Fatalf("ParseConf: %v", err)
	}
}

func TestParseConf_MissingInterface(t *testing.T) {
	pub := genB64Key(t, 12)
	text := "[Peer]\nPublicKey = " + pub + "\nAllowedIPs = 0.0.0.0/0\n"
	if _, err := ParseConf(text); err == nil {
		t.Fatal("ожидалась ошибка: нет [Interface]")
	}
}

func TestParseConf_MissingPeer(t *testing.T) {
	priv := genB64Key(t, 13)
	text := "[Interface]\nPrivateKey = " + priv + "\n"
	if _, err := ParseConf(text); err == nil {
		t.Fatal("ожидалась ошибка: нет [Peer]")
	}
}

func TestParseConf_InvalidKey(t *testing.T) {
	text := "[Interface]\nPrivateKey = not-a-valid-key\n[Peer]\nPublicKey = alsonotvalid\nAllowedIPs = 0.0.0.0/0\n"
	if _, err := ParseConf(text); err == nil {
		t.Fatal("ожидалась ошибка: невалидный ключ")
	}
}

func TestInterfaceConf_BuildUAPI(t *testing.T) {
	priv := genB64Key(t, 14)
	pub := genB64Key(t, 15)
	iface := InterfaceConf{PrivateKey: priv, ListenPort: 9000, Jc: 4}
	peers := []PeerConf{{PublicKey: pub, AllowedIPs: []string{"0.0.0.0/0"}, Endpoint: "127.0.0.1:9001", PersistentKeepalive: 25}}

	uapi, err := iface.BuildUAPI(peers)
	if err != nil {
		t.Fatalf("BuildUAPI: %v", err)
	}
	for _, want := range []string{"listen_port=9000", "jc=4", "endpoint=127.0.0.1:9001", "allowed_ip=0.0.0.0/0", "persistent_keepalive_interval=25"} {
		if !strings.Contains(uapi, want) {
			t.Errorf("UAPI не содержит %q:\n%s", want, uapi)
		}
	}
}

func TestInterfaceConf_BuildUAPI_EmptyAllowedIPs(t *testing.T) {
	priv := genB64Key(t, 16)
	pub := genB64Key(t, 17)
	iface := InterfaceConf{PrivateKey: priv}
	peers := []PeerConf{{PublicKey: pub}}
	if _, err := iface.BuildUAPI(peers); err == nil {
		t.Fatal("ожидалась ошибка: пустой AllowedIPs")
	}
}
