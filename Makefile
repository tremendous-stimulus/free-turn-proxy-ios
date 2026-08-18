# Go-исходники тянем из upstream репозитория библиотеки.
# GO_REF фиксирует тег библиотеки — меняй осознанно при обновлении.
# Переопределяемо для локальной разработки:
#   make framework GO_REPO=/path/to/free-turn-proxy GO_REF=main
GO_REPO ?= https://github.com/samosvalishe/free-turn-proxy
GO_REF  ?= v3.1.0
SRC_DIR := .framework-src

# Прямые зависимости нашей половины (golib/go.mod) в виде module@version —
# ими пинится сборка внутри клона апстрима, см. framework.
FTUN_DEPS := $(shell awk '/^require \(/{f=1;next} /^\)/{f=0} f && $$0 !~ /indirect/ && NF==2 {print $$1 "@" $$2}' golib/go.mod)

.PHONY: framework project open clean all

# 1. Собрать Go-фреймворк: апстрим (mobile) + наш WG-in-WG модуль (golib/ftun,
# план vpn-lexical-rossum.md, фаза 1) — ОДНИМ gomobile bind в ОДИН
# xcframework. Обязательно: два gomobile-биндинга, собранные раздельно,
# зашивают каждый свой встроенный Go-рантайм, и при совместной линковке
# падают с SIGSEGV в рантайм-бутстрапе, как только реально исполняется код из
# обеих половин (см. план, «Фаза 1.5 — блокер», подтверждено минимальным
# репро) — держит их в одном рантайме именно совместная сборка одним
# вызовом gomobile bind, поэтому ftun копируется как sibling-пакет в
# склонированное дерево апстрима, а не собирается отдельно.
# GO_REPO/GO_REF по-прежнему пинят апстрим-сторону; golib/ftun — наш код,
# правки в нём подхватятся при следующей сборке без смены GO_REF.
framework:
	rm -rf $(SRC_DIR)
	git clone --depth 1 --branch $(GO_REF) $(GO_REPO) $(SRC_DIR)
	rm -rf $(SRC_DIR)/ftun
	cp -R golib/ftun $(SRC_DIR)/ftun
	rm -f $(SRC_DIR)/ftun/*_test.go
	# Версии зависимостей ftun приезжают из golib/go.mod. Без этого шага
	# `go mod tidy` в клоне апстрима резолвит gvisor в «самое свежее» на момент
	# сборки — а у него неотегованный API ломается регулярно, то есть релиз мог
	# бы упасть или слинковаться с другим netstack без единой правки в репе.
	cd $(SRC_DIR) && go get $(FTUN_DEPS)
	cd $(SRC_DIR) && go get -tool golang.org/x/mobile/cmd/gobind && go mod tidy
	# `go get -tool` только прописывает gobind в go.mod (tool-директива Go 1.24+),
	# бинарник не собирает — gomobile bind ищет gobind через PATH, поэтому нужен
	# отдельный go install версией, зафиксированной той же tool-директивой.
	cd $(SRC_DIR) && go install golang.org/x/mobile/cmd/gobind
	cd $(SRC_DIR) && gomobile bind -target ios,iossimulator -ldflags "-checklinkname=0" \
		-o dist/Mobile.xcframework ./mobile ./ftun
	rm -rf Frameworks/Mobile.xcframework
	mkdir -p Frameworks
	cp -R $(SRC_DIR)/dist/Mobile.xcframework Frameworks/
	rm -rf $(SRC_DIR)

# 2. Сгенерировать .xcodeproj (нужен xcodegen: brew install xcodegen)
project:
	xcodegen generate

# 3. Открыть в Xcode
open:
	open FreeTurnProxy.xcodeproj

# Всё сразу
all: framework project open

clean:
	rm -rf Frameworks FreeTurnProxy.xcodeproj $(SRC_DIR)
