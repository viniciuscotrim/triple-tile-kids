# Triple Tile Kids — iOS + iPadOS (Universal)

Jogo casual "triple match" para uma criança de 4 anos. Toca num tile do topo da
pilha → vai pra barra de coleta (7 slots) → junta 3 iguais → saem. Limpa tudo →
celebração 🎉. Sem texto, sem timer, sem perder. Construído a partir do brief em
`../BRIEF-claude-code-tripletile-ios.md` e do protótipo `../triple-tile-kids.jsx`.

Arquitetura: **SwiftUI (casca)** + **SpriteKit (`SKScene`)** para o jogo, via `SpriteView`.

## Mapa de arquivos

```
TripleTileKids/
  TripleTileKidsApp.swift   @main
  ContentView.swift         casca: SpriteView + overlays (engrenagem, vitória) + GameHost
  SettingsView.swift        menu da engrenagem (tamanho da pilha + tema), @AppStorage
  GameScene.swift           SKScene: pilha, barra, input/hit-test, regras, animações
  BoardGenerator.swift      buildBoard + ordem de liberação (SOLUBILIDADE garantida)
  Tile.swift                modelo do tile
  Theme.swift               THEMES, SIZES, THEME_COLORS, constantes da engine
  Feedback.swift            som (síntese de tons via AVAudioEngine) + haptics
  Assets.xcassets           AppIcon
TripleTileKidsTests/
  BoardGeneratorTests.swift  prova de solubilidade (100 tabuleiros × 3 tamanhos)
```

## Engine (fiel ao protótipo validado)

- **Quantidade por slider**: a engrenagem tem um slider que escolhe o nº de TRIOS
  (2 a 50) → total de cards = trios × 3 (sempre múltiplo de 3, **garantido por
  construção**). Até 3 × 50 = 150 cards. Persistido em `@AppStorage("trios")`.
- **Distribuição EXATA**: cada ícone entra em múltiplo de 3 (nunca 1 ou 2 sobrando
  p/ completar trio). Tipos atribuídos em trios consecutivos na ordem de liberação.
- **Pilha em camadas (Mahjong)**: dentro de uma camada os tiles não se sobrepõem
  (espaçamento > tile); cada camada superior é mais estreita e centrada → as BORDAS
  da camada de baixo ficam expostas (livres) e o CENTRO fica coberto. Empilhamento
  com elevação visual.
- **Bloqueio estrito**: só é clicável o tile com NENHUM outro card por cima (mesmo
  parcialmente) — `|dx| < 0.85·TILE && |dy| < 0.85·TILE` com algum de camada superior.
  Bloqueados ficam escurecidos (brightness 0.5) e não respondem ao toque.
- **Solubilidade garantida** (CRÍTICO): ordem de liberação (camada desc, depois y, x);
  quem cobre tem camada maior (id menor) → jogar "menor id livre" abre a pilha em ordem,
  trios saem em sequência, barra nunca passa de 3. Verificado: 60/60 solúveis em
  trios ∈ {2,3,5,8,12,20,35,50}, sempre múltiplo de 3 por ícone.
- **Barra cheia sem game-over** (`allowGameOver = false`): se passa de 7, devolve o
  tile mais antigo ao tabuleiro. NUNCA perde.
- **Temas** (6): animais, frutas, alfabeto, números, casa, cotidiano (`@AppStorage("theme")`).
  Se trios > nº de ícones do tema, os ícones se repetem (casam por ícone).
- **Acessibilidade**: respeita Reduce Motion (desliga animações de física).

## Build & Run — SIMULADOR (recomendado p/ validar)

⚠️ `xcodebuild` **crasha** no Xcode 26 com iPhone pareado (`INTERNAL ERROR` em
`DVTDeviceManager`, na inicialização — independe do destino). Por isso o build é
manual via `swiftc` + `actool`. O `.xcodeproj` existe para abrir/editar na GUI do Xcode.

```bash
./build_sim.sh                       # compila + monta o .app (sem assinatura)
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator
xcrun simctl install booted .build_sim/TripleTileKids.app
xcrun simctl launch booted com.tripletile.TripleTileKids
```

Validado nos simuladores **iPhone 17 Pro** e **iPad Pro 11"** (layout adaptativo,
toque, barra, trio, limpeza — loop completo).

## Build & Deploy — iPhone FÍSICO

`./build_device.sh` faz tudo (swiftc → actool → Info.plist → codesign → devicectl
install). **Pré-requisito (uma vez):** um provisioning profile para
`com.tripletile.TripleTileKids` precisa existir. O Xcode 26 CLI não consegue criar
(crash), então gere-o UMA vez pela GUI do Xcode:

1. Abrir `TripleTileKids.xcodeproj` no Xcode.
2. Target TripleTileKids → **Signing & Capabilities** → Team `U3H5DHZP65`,
   marcar "Automatically manage signing". O Xcode registra o App ID e cria o profile.
3. `./build_device.sh` (com o iPhone desbloqueado) — assina e instala.

Identidade: Team `U3H5DHZP65`, cert `Apple Development: viniciusluciano@me.com
(88JX9769Y3)`, device iPhone 17 Pro `A495656F-4801-515B-9900-E7989FCB561A`.

## Config Xcode (espelha AgentForge/ColonyPrototype)

- iOS 17.0+, `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad), portrait
  (+ upside-down no iPad).
- `INFOPLIST_KEY_UILaunchScreen_Generation = YES` (evita letterboxing/barras pretas).
- `SWIFT_VERSION = 5.0` (evita atrito de concorrência estrita do Swift 6 num jogo).
