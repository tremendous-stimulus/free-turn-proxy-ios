package ftun

import (
	"bytes"
	"testing"
	"time"
)

func TestPipe_WriteReadRoundtrip(t *testing.T) {
	a, b := NewPipe(1280)
	defer a.Close()
	defer b.Close()

	payload := []byte("hello from a")
	if _, err := a.Write([][]byte{payload}, 0); err != nil {
		t.Fatalf("a.Write: %v", err)
	}

	bufs := [][]byte{make([]byte, 1280)}
	sizes := []int{0}
	n, err := b.Read(bufs, sizes, 0)
	if err != nil {
		t.Fatalf("b.Read: %v", err)
	}
	if n != 1 {
		t.Fatalf("n = %d, want 1", n)
	}
	if !bytes.Equal(bufs[0][:sizes[0]], payload) {
		t.Errorf("got %q, want %q", bufs[0][:sizes[0]], payload)
	}
}

func TestPipe_Bidirectional(t *testing.T) {
	a, b := NewPipe(1280)
	defer a.Close()
	defer b.Close()

	if _, err := a.Write([][]byte{[]byte("a->b")}, 0); err != nil {
		t.Fatalf("a.Write: %v", err)
	}
	if _, err := b.Write([][]byte{[]byte("b->a")}, 0); err != nil {
		t.Fatalf("b.Write: %v", err)
	}

	bufs := [][]byte{make([]byte, 1280)}
	sizes := []int{0}

	if _, err := b.Read(bufs, sizes, 0); err != nil {
		t.Fatalf("b.Read: %v", err)
	}
	if string(bufs[0][:sizes[0]]) != "a->b" {
		t.Errorf("b получил %q", bufs[0][:sizes[0]])
	}

	if _, err := a.Read(bufs, sizes, 0); err != nil {
		t.Fatalf("a.Read: %v", err)
	}
	if string(bufs[0][:sizes[0]]) != "b->a" {
		t.Errorf("a получил %q", bufs[0][:sizes[0]])
	}
}

func TestPipe_OffsetRespected(t *testing.T) {
	a, b := NewPipe(1280)
	defer a.Close()
	defer b.Close()

	buf := make([]byte, 8)
	copy(buf[4:], []byte("data"))
	if _, err := a.Write([][]byte{buf}, 4); err != nil {
		t.Fatalf("a.Write: %v", err)
	}

	readBuf := make([]byte, 16)
	bufs := [][]byte{readBuf}
	sizes := []int{0}
	if _, err := b.Read(bufs, sizes, 4); err != nil {
		t.Fatalf("b.Read: %v", err)
	}
	if string(readBuf[4 : 4+sizes[0]]) != "data" {
		t.Errorf("got %q", readBuf[4:4+sizes[0]])
	}
}

func TestPipe_CloseUnblocksRead(t *testing.T) {
	a, b := NewPipe(1280)
	defer b.Close()

	done := make(chan error, 1)
	go func() {
		bufs := [][]byte{make([]byte, 1280)}
		sizes := []int{0}
		_, err := a.Read(bufs, sizes, 0)
		done <- err
	}()

	time.Sleep(20 * time.Millisecond)
	a.Close()

	select {
	case err := <-done:
		if err == nil {
			t.Error("ожидалась ошибка после Close")
		}
	case <-time.After(time.Second):
		t.Fatal("Read не разблокировался после Close")
	}
}

// С роутером между половинами (фаза 5.2) закрытие противоположного конца в
// момент Write не наблюдаемо: пакет уходит в свою исходящую очередь, а дальше
// его просто некому забрать. Ошибку даёт закрытие своего же конца — именно на
// него опирается device.Device, останавливая свои воркеры.
func TestPipe_WriteAfterOwnCloseFails(t *testing.T) {
	a, b := NewPipe(1280)
	defer b.Close()
	a.Close()

	if _, err := a.Write([][]byte{[]byte("x")}, 0); err == nil {
		t.Error("ожидалась ошибка записи в закрытый конец")
	}
}
