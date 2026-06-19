# Go-исходники биндинга тянем из git, чтобы не зависеть от соседнего чекаута.
# Переопределяемо (в т.ч. на локальный путь/форк во время разработки):
#   make framework GO_REPO=/path/to/free-turn-proxy GO_REF=my-branch
GO_REPO ?= https://github.com/tremendous-stimulus/free-turn-proxy
GO_REF  ?= master
SRC_DIR := .framework-src

.PHONY: framework project open clean all

# 1. Собрать Go-фреймворк (нужен gomobile: go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init)
framework:
	rm -rf $(SRC_DIR)
	git clone --depth 1 --branch $(GO_REF) $(GO_REPO) $(SRC_DIR)
	$(SRC_DIR)/scripts/build-ios.sh "$(PWD)/Frameworks"
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
