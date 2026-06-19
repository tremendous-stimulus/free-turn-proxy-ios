# Free Turn (iOS)

iOS-клиент [free-turn-proxy](https://github.com/tremendous-stimulus/free-turn-proxy): поднимает на устройстве локальный прокси, через который AmneziaWG/WireGuard тоннелируется в TURN-серверы VK под видом медиатрафика видеозвонка. SwiftUI, iOS 16+.

## Установка через SideStore

1. Установи [SideStore](https://sidestore.io) на устройство.
2. В SideStore открой **Sources → +** и вставь ссылку на источник:

   ```
   https://raw.githubusercontent.com/tremendous-stimulus/free-turn-proxy-ios/main/apps.json
   ```

3. Открой источник «Free Turn» и нажми **Install** у приложения.

Каждый новый git-тег вида `1.0.0` автоматически собирает `.ipa`, публикует GitHub Release и обновляет источник — SideStore подтянет обновление.

## Требования

- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [gomobile](https://pkg.go.dev/golang.org/x/mobile/cmd/gomobile) — `go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init`

## Сборка

```sh
make all        # framework + project + open
```

Или по шагам:

```sh
make framework  # собрать Ios.xcframework (клонирует Go-репо и гонит gomobile bind)
make project    # сгенерировать FreeTurnProxy.xcodeproj из project.yml
make open       # открыть проект в Xcode
make clean      # удалить артефакты сборки
```

`make framework` тянет Go-исходники из git, поэтому собирает то, что **запушено**. Источник переопределяется:

```sh
make framework GO_REPO=/путь/к/free-turn-proxy GO_REF=моя-ветка
```

Распространяется сайдлоадом (SideStore): подпись и `DEVELOPMENT_TEAM` заданы в `project.yml`.

## Контрибьют

Pull request'ы приветствуются — багфиксы, улучшения, идеи. Перед PR убедись, что проект собирается (`make all`). Issue с воспроизведением тоже welcome.
