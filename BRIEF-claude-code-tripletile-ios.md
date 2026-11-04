# Brief de execução — Triple Tile Kids (iOS Universal, SpriteKit)

Entregue este doc ao Claude Code rodando no Mac (M4 Pro). Ele scaffolda o projeto Xcode, builda no simulador iPhone + iPad, corrige erros de compilação e prepara para deploy no aparelho. O protótipo React (`triple-tile-kids.jsx`) é **referência de design e de lógica já validada** — não portar literal; reescrever em Swift seguindo as decisões abaixo.

---

## 1. O que é

Jogo casual de "triple match" para uma criança de 4 anos. Tabuleiro de tiles empilhados em pilha densa irregular (estilo Mahjong/Triple Tile). Toca num tile do topo → ele vai para a barra de coleta de 7 slots. Junta 3 iguais na barra → saem do jogo. Limpa todos os tiles → vitória. Exercita reconhecimento e raciocínio de planejamento.

Público: 4 anos. Sem texto, sem leitura, sem timer, sem perder. Tudo por ícone, cor, som e celebração.

---

## 2. Plataforma

- **iOS Universal**: um target, iPhone + iPad. Marcar ambos no Deployment Info.
- Deployment target: iOS 16+ (SpriteKit + SwiftUI maduros).
- Orientação: portrait (e portrait-upside-down liberado no iPad).
- Layout adaptativo: o tabuleiro escala por proporção da tela (`size`-relative), nunca pixels fixos. Mesmo binário renderiza bem em iPhone SE até iPad Pro 12.9".
- Arquitetura: **SwiftUI como casca** (App, navegação, menu de config) + **SpriteKit (`SKScene`) para o jogo** via `SpriteView`. Menu de configurações pode ser SwiftUI overlay por cima da cena.

---

## 3. Engine — regras (já validadas, não reabrir)

### Mecânica central
- **Barra de coleta**: 7 slots. Auto-organiza agrupando iguais lado a lado.
- **Trio**: 3 tiles iguais na barra → removidos do jogo (animação de saída + som).
- **Bloqueio**: um tile só é clicável se nenhum tile de camada superior o sobrepõe. Tiles bloqueados ficam escurecidos (brightness ~0.5) e não respondem ao toque.
- **Barra cheia sem game-over** (decisão consciente para 4 anos): se a barra atinge 8 (passou de 7) sem completar trio, devolver o tile mais antigo da barra de volta ao tabuleiro, na posição original. NUNCA game-over. Expor como flag `allowGameOver = false` para reverter no futuro se quiser o comportamento fiel.
- **Vitória**: todos os tiles limpos → tela de celebração (🎉 + som ascendente) + botão de recomeçar.

### Solubilidade garantida (CRÍTICO — manter a lógica exata)
O tabuleiro DEVE sempre ter solução, mesmo com bloqueio rígido. Técnica (igual Mahjong: gerar a partir da solução, não validar depois):

1. Gerar os **slots posicionais** da pilha (x, y, layer) primeiro, sem ícones.
2. Calcular a **ordem de liberação**: ordenar os slots por `layer` decrescente (topo primeiro), e dentro da mesma layer por `y` crescente (de cima para baixo). Essa é a ordem em que a pilha se abre.
3. Atribuir ícones em **trios consecutivos seguindo a ordem de liberação**: os 3 primeiros slots a liberar recebem o ícone A, os 3 seguintes o ícone B, etc.

Resultado: cada trio fica acessível em sequência conforme a pilha abre; a terceira cópia nunca fica presa embaixo dependendo dela mesma sair. Sempre termina.

> Em SpriteKit vale modelar isso como um **grafo de dependência** (cada tile aponta para os que o cobrem). Atualizar "liberado/bloqueado" reativamente quando um tile sai, em vez de recalcular sobreposição a cada frame. Mais limpo e performático que o `isBlocked` por varredura do protótipo.

### Pilha — formato
Pilha densa e irregular em formato de monte (losango: estreito no topo, largo no meio, estreito embaixo), com jitter de posição (~±14px x, ±10px y) para parecer empilhado à mão. 1–2 camadas de profundidade. No protótipo as linhas por tamanho estão em `SIZES`.

---

## 4. Configurações (menu da engrenagem) — persistir com @AppStorage

### Tamanho da pilha (a criança ajusta a progressão)
| Tamanho | Tipos de ícone | Total de tiles (×3) | Layout (linhas) |
|---|---|---|---|
| 🐣 pequeno | 5 | 15 | [3,4,4,3] + topo [2,2] |
| 🐥 médio | 8 | 24 | [3,5,5,5,3] + topo [3,2] |
| 🐓 grande | 12 | 36 | [3,5,6,6,5,4,3] + topo [3,3,2] |

### Temas (6, selecionáveis)
animais, frutas, alfabeto, números, objetos da casa, objetos do cotidiano. Cada tema = lista de ícones (emoji ou SF Symbols ou assets). Lista completa no protótipo (`THEMES`).

> Em produção iOS, avaliar **assets vetoriais próprios** em vez de emoji: emoji renderiza diferente entre versões de iOS e não dá controle de estilo. SF Symbols cobre alfabeto/números/alguns objetos. Para animais/frutas com identidade visual, considerar um set de ícones flat desenhado (pode vir depois; emoji serve no MVP).

### Persistência
`@AppStorage("theme")` e `@AppStorage("size")` — o app reabre na última config escolhida. Default: tema `animais`, tamanho `medio`.

---

## 5. Feel / acabamento (onde o SpriteKit ganha do DOM)

- **Cascata real**: tiles se sobrepõem como telhas, com oclusão limpa por z-position. Sombra projetada do tile de cima sobre o de baixo.
- **Saída do trio**: animação física — tiles "pulam" para a barra, e ao completar trio saem com escala + fade + leve rotação. SKAction.
- **Haptics**: toque leve (`.light`) ao pegar tile; sucesso (`.success`) ao completar trio; nada ao bloquear (silêncio = feedback de "não pode").
- **Som**: tons curtos (pode gerar via AVAudioEngine ou tocar samples). Match = arpejo ascendente 3 notas; vitória = 5 notas; tap = nota única.
- **Contraste alto, tiles grandes**, bordas claras, cores saturadas. Paleta no protótipo (`THEME_COLORS`).
- Respeitar **Reduce Motion** (acessibilidade): desliga animações de física, mantém o essencial.

---

## 6. Estrutura sugerida de arquivos

```
TripleTileKids/
  TripleTileKidsApp.swift      // @main, SwiftUI App
  ContentView.swift            // casca: SpriteView + overlay de menu
  GameScene.swift              // SKScene: pilha, barra, input, regras
  BoardGenerator.swift         // buildBoard + ordem de liberação (solubilidade)
  Tile.swift                   // modelo: id, icon, colorIdx, layer, x, y, estado
  Theme.swift                  // THEMES + THEME_COLORS + SIZES
  SettingsView.swift           // menu SwiftUI: tamanho + temas, @AppStorage
  Sound.swift / Haptics.swift  // feedback
  Assets.xcassets              // cores, ícones
```

---

## 7. Deploy

- **Universal**: confirmar iPhone + iPad no target. Testar no simulador iPad Pro 11" e iPhone 15 antes do aparelho.
- **Free provisioning**: roda no aparelho por 7 dias sem custo (já dá pra criança usar).
- **Apple Developer pago (confirmado em conta)**: assinatura 1 ano, caminho para TestFlight (instalar sem cabo, distribuir pra família) e App Store se quiser.
- Sideload via cabo no iPad: conectar, selecionar o device no Xcode, Run. Confiar no perfil de desenvolvedor em Ajustes > Geral > VPN e Gerenciamento de Dispositivos.

---

## 8. Ordem de execução recomendada para o Claude Code

1. Scaffold do projeto Xcode Universal (SwiftUI + SpriteKit), build vazio passando.
2. `Theme.swift` + `BoardGenerator.swift` com a lógica de solubilidade. Teste unitário: gerar 100 tabuleiros de cada tamanho e verificar que todos são solúveis por simulação gulosa (sempre existe trio acessível até esvaziar).
3. `GameScene.swift`: render da pilha + bloqueio reativo + barra + trio. Jogável sem polish.
4. Menu `SettingsView` + `@AppStorage`.
5. Polish: haptics, som, cascata, animação de saída, celebração.
6. Build iPad + iPhone, ajuste de layout adaptativo.
7. Deploy no aparelho.

> Travar item 2 com teste antes de avançar. A solubilidade é o coração; se ela falha, o resto é cosmético.
