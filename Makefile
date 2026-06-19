REPO := $(shell cd ../free-turn-proxy && pwd)
FRAMEWORK := Frameworks/Mobile.xcframework

.PHONY: framework project open clean

# 1. Собрать Go-фреймворк (нужен gomobile: go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init)
framework:
	$(REPO)/scripts/build-ios.sh "$(PWD)/Frameworks"

# 2. Сгенерировать .xcodeproj (нужен xcodegen: brew install xcodegen)
project:
	xcodegen generate

# 3. Открыть в Xcode
open:
	open FreeTurnProxy.xcodeproj

# Всё сразу
all: framework project open

clean:
	rm -rf Frameworks FreeTurnProxy.xcodeproj
