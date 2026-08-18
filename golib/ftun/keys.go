package ftun

import (
	"encoding/base64"
	"encoding/hex"
	"fmt"
)

// wg/awg .conf хранит ключи в base64 (32 байта); UAPI-протокол amneziawg-go
// принимает их в hex — вся конвертация идёт через этот файл.

func keyToHex(base64Key string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(base64Key)
	if err != nil {
		return "", fmt.Errorf("невалидный base64 ключа: %w", err)
	}
	if len(raw) != 32 {
		return "", fmt.Errorf("длина ключа %d байт, ожидалось 32", len(raw))
	}
	return hex.EncodeToString(raw), nil
}

func validateKey(base64Key string) error {
	_, err := keyToHex(base64Key)
	return err
}
