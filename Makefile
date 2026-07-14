# Go-исходники тянем из upstream репозитория библиотеки.
# GO_REF фиксирует тег библиотеки — меняй осознанно при обновлении.
# Переопределяемо для локальной разработки:
#   make framework GO_REPO=/path/to/free-turn-proxy GO_REF=main
GO_REPO ?= https://github.com/samosvalishe/free-turn-proxy
GO_REF  ?= v1.8.0
SRC_DIR := .framework-src

.PHONY: framework project open clean all

# 1. Собрать Go-фреймворк (нужен gomobile + task: brew install go-task)
framework:
	rm -rf $(SRC_DIR)
	git clone --depth 1 --branch $(GO_REF) $(GO_REPO) $(SRC_DIR)
	cd $(SRC_DIR) && task build:ios
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
