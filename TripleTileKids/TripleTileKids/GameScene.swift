import SpriteKit
import UIKit

// MARK: - Nó visual de um tile (telha arredondada + sombra + ícone)

final class TileNode: SKNode {
    private let shadow = SKShapeNode()
    private let bg = SKShapeNode()
    private let label = SKLabelNode()
    private(set) var colorIdx = 0
    private(set) var side: CGFloat = 0
    private(set) var blocked = false

    func build(side: CGFloat, colorIdx: Int, icon: String, isText: Bool) {
        self.side = side
        self.colorIdx = colorIdx
        removeAllChildren()

        let rect = CGRect(x: -side/2, y: -side/2, width: side, height: side)
        let radius = side * 0.22
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        shadow.path = path
        shadow.fillColor = SKColor(white: 0, alpha: 0.32)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -side * 0.07)
        shadow.zPosition = -1
        addChild(shadow)

        bg.path = path
        bg.lineWidth = max(2, side * 0.05)
        addChild(bg)

        label.text = icon
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        // Emoji ignora fontName; texto (letras/números) usa fonte arredondada e bold.
        label.fontName = "ArialRoundedMTBold"
        label.fontSize = isText ? side * 0.56 : side * 0.62
        label.position = CGPoint(x: 0, y: isText ? side * 0.02 : 0)
        addChild(label)

        applyColors()
    }

    func setBlocked(_ b: Bool) {
        guard b != blocked else { return }
        blocked = b
        applyColors()
    }

    private func applyColors() {
        let bright = blocked ? 0.5 : 1.0
        bg.fillColor = Theme.skColor(colorIdx, brightness: bright)
        bg.strokeColor = SKColor(white: 1, alpha: blocked ? 0.45 : 0.85)
        label.alpha = blocked ? 0.65 : 1.0
        shadow.alpha = blocked ? 0.5 : 1.0
    }
}

// MARK: - Cena do jogo

final class GameScene: SKScene {

    /// Vitória — passa se a partida teve algum reset de barra (p/ stats).
    var onWin: ((_ hadReset: Bool) -> Void)?
    /// Barra de 7 preenchida sem combinação (resetou a bandeja).
    var onBarReset: (() -> Void)?
    /// Estado mudou (p/ salvar a progressão + atualizar o indicador de progresso).
    var onStateChanged: (() -> Void)?

    /// Progresso da partida (sobrevive ao reflow ao girar, pois `trios` é o total fixo).
    var totalTrios: Int { trios }
    var clearedTrios: Int { trios - tiles.filter { !$0.cleared }.count / GameConst.trio }

    private var theme: ThemeKey = .animais
    private var trios: Int = GameConst.defaultTrios
    private var shape: ShapeKey = .piramide
    private var maxLayer: Int = 0
    private var resetsThisGame: Int = 0
    /// Ao girar: true = reorganiza os cards p/ a nova orientação (preenche a tela e serve de
    /// "embaralhar"); false = mantém o mesmo tabuleiro, só reescala (criança tem que pensar).
    var reorganizeOnRotate: Bool = true

    private var tiles: [TileModel] = []
    private var bar: [TileModel] = []          // ordenado por ícone (auto-organiza)
    private var tileNodes: [Int: TileNode] = [:]
    private var didWin = false

    // Layout
    private var topInset: CGFloat = 0
    private var bottomInset: CGFloat = 0
    private var leftInset: CGFloat = 0
    private var rightInset: CGFloat = 0
    private let boardLayer = SKNode()
    private let barLayer = SKNode()
    private let barBG = SKShapeNode()
    private var barSlotNodes: [SKShapeNode] = []
    private var barSlotSize: CGFloat = 56
    private var barCenters: [CGPoint] = []

    // Mapeamento modelo→tela calculado em layout
    private var boardScale: CGFloat = 1
    private var boardCenterScreen: CGPoint = .zero
    private var modelCenter: CGPoint = .zero
    private var displayTile: CGFloat = 64

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private var isLandscape: Bool { size.width > size.height }
    private var lastLandscape: Bool? = nil

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = .clear
        addChild(boardLayer)
        addChild(barLayer)
        barBG.zPosition = -1
        barBG.strokeColor = .clear
        barBG.fillColor = SKColor(white: 1, alpha: 0.55)
        barLayer.addChild(barBG)
        buildBarSlots()
        if tiles.isEmpty { newGame(theme: theme, trios: trios, shape: shape) }
        // SwiftUI pode chamar newGame/updateSafeArea ANTES do didMove (slots/camadas
        // ainda não existiam). Refazemos o layout aqui agora que tudo está montado —
        // não dependemos do didChangeSize disparar (flaky entre devices).
        layoutAll()
    }

    // MARK: Configuração externa (vinda do SwiftUI)

    func updateSafeArea(top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) {
        guard top != topInset || bottom != bottomInset
            || left != leftInset || right != rightInset else { return }
        topInset = top
        bottomInset = bottom
        leftInset = left
        rightInset = right
        layoutAll()
    }

    func newGame(theme: ThemeKey, trios: Int, shape: ShapeKey) {
        self.theme = theme
        self.trios = trios
        self.shape = shape
        didWin = false
        bar = []
        resetsThisGame = 0
        // Mais largo em paisagem → os cards reocupam a tela e ficam grandes.
        let aspect: CGFloat = isLandscape ? 1.9 : 1.0
        tiles = BoardGenerator.build(theme: theme, trios: trios, shape: shape, aspect: aspect)
        maxLayer = tiles.map(\.layer).max() ?? 0
        lastLandscape = isLandscape

        // Centro do modelo (para centralizar e escalar)
        let xs = tiles.map(\.x), ys = tiles.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        modelCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)

        rebuildTileNodes()
        layoutAll()
        onStateChanged?()
    }

    /// Ao girar: reorganiza os cards que SOBRARAM (board + barra) num arranjo novo p/ a
    /// nova orientação, SEM reiniciar (trios já limpos continuam limpos). A barra volta vazia
    /// (seus cards voltam ao tabuleiro). Mantém solubilidade e espalhamento.
    private func reflowForOrientation() {
        lastLandscape = isLandscape
        let remaining: [(icon: String, colorIdx: Int)] =
            tiles.filter { !$0.cleared }.map { ($0.icon, $0.colorIdx) }
        guard remaining.count >= GameConst.trio else { return }   // quase ganhou: não mexe
        let aspect: CGFloat = isLandscape ? 1.9 : 1.0
        let newTiles = BoardGenerator.reflow(remaining: remaining, shape: shape, aspect: aspect)
        guard !newTiles.isEmpty else { return }

        bar = []
        tiles = newTiles
        didWin = false
        maxLayer = tiles.map(\.layer).max() ?? 0
        let xs = tiles.map(\.x), ys = tiles.map(\.y)
        modelCenter = CGPoint(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2,
                              y: ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
        rebuildTileNodes()
        layoutBar()
        layoutBoard()
        onStateChanged?()
    }

    // MARK: Persistência (salvar/retomar)

    func snapshot() -> GameState {
        GameState(theme: theme.rawValue, trios: trios, shape: shape.rawValue,
                  tiles: tiles, barIds: bar.map(\.id), resetsThisGame: resetsThisGame)
    }

    /// Restaura uma partida salva. Retorna se está vencida (todos limpos).
    @discardableResult
    func restore(_ s: GameState) -> Bool {
        theme = ThemeKey(rawValue: s.theme) ?? .animais
        trios = s.trios
        shape = ShapeKey(rawValue: s.shape) ?? .piramide
        tiles = s.tiles
        resetsThisGame = s.resetsThisGame
        let byId = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, $0) })
        bar = s.barIds.compactMap { byId[$0] }
        maxLayer = tiles.map(\.layer).max() ?? 0
        let xs = tiles.map(\.x), ys = tiles.map(\.y)
        modelCenter = CGPoint(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2,
                              y: ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
        let won = !tiles.contains { !$0.cleared }
        didWin = won
        lastLandscape = isLandscape
        rebuildTileNodes()
        layoutAll()
        return won
    }

    // MARK: Construção de nós

    private func buildBarSlots() {
        barSlotNodes.forEach { $0.removeFromParent() }
        barSlotNodes = []
        for _ in 0..<GameConst.barSize {
            let slot = SKShapeNode()
            slot.lineWidth = 0
            barLayer.addChild(slot)
            barSlotNodes.append(slot)
        }
    }

    private func rebuildTileNodes() {
        tileNodes.values.forEach { $0.removeFromParent() }
        tileNodes = [:]
        let isText = theme.isText
        for t in tiles where t.onBoard {
            let node = TileNode()
            node.build(side: displayTile, colorIdx: t.colorIdx, icon: t.icon, isText: isText)
            node.zPosition = CGFloat(t.layer) * 1000 + t.y
            boardLayer.addChild(node)
            tileNodes[t.id] = node
        }
    }

    // MARK: Layout adaptativo (escala por proporção de tela)

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutAll()
    }

    private func layoutAll() {
        guard size.width > 0, size.height > 0 else { return }
        // Girou (retrato↔paisagem)? Conforme o toggle: reorganiza (reflow) ou só reescala.
        if let last = lastLandscape, last != isLandscape, !tiles.isEmpty {
            if reorganizeOnRotate {
                reflowForOrientation()
            } else {
                lastLandscape = isLandscape
                layoutBar(); layoutBoard()   // mantém o mesmo tabuleiro, só reescala
            }
            return
        }
        lastLandscape = isLandscape
        layoutBar()
        layoutBoard()
    }

    private func layoutBar() {
        let pad: CGFloat = 14
        let spacing: CGFloat = 6
        let count = CGFloat(GameConst.barSize)
        let bgInset: CGFloat = 8

        if isLandscape {
            // Barra VERTICAL na esquerda → sobra a tela quase toda p/ os cards.
            let usableH = max(60, size.height - topInset - bottomInset - pad * 2)
            let colH = min(usableH, 620)
            barSlotSize = min((colH - (count - 1) * spacing) / count, 60)
            let stackH = count * barSlotSize + (count - 1) * spacing
            let centerX = leftInset + pad + bgInset + barSlotSize / 2
            let topY = size.height - topInset - pad - (usableH - stackH) / 2 - barSlotSize / 2
            barCenters = []
            for (i, slot) in barSlotNodes.enumerated() {
                let center = CGPoint(x: centerX, y: topY - CGFloat(i) * (barSlotSize + spacing))
                barCenters.append(center)
                applySlotPath(slot)
                slot.position = center
            }
            let bgRect = CGRect(x: centerX - barSlotSize / 2 - bgInset,
                                y: (barCenters.last!.y) - barSlotSize / 2 - bgInset,
                                width: barSlotSize + bgInset * 2,
                                height: stackH + bgInset * 2)
            barBG.path = CGPath(roundedRect: bgRect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        } else {
            // Barra HORIZONTAL no topo.
            let usableLeft = leftInset + pad
            let usableW = max(60, size.width - leftInset - rightInset - pad * 2)
            let barW = min(usableW, 520)
            barSlotSize = min((barW - (count - 1) * spacing) / count, 64)
            let rowWidth = count * barSlotSize + (count - 1) * spacing
            let originX = usableLeft + (usableW - rowWidth) / 2
            let startX = originX + barSlotSize / 2
            // deixa um vão no topo p/ o indicador de progresso (SwiftUI)
            let centerY = size.height - topInset - 34 - barSlotSize / 2
            barCenters = []
            for (i, slot) in barSlotNodes.enumerated() {
                let center = CGPoint(x: startX + CGFloat(i) * (barSlotSize + spacing), y: centerY)
                barCenters.append(center)
                applySlotPath(slot)
                slot.position = center
            }
            let bgRect = CGRect(x: originX - bgInset,
                                y: centerY - barSlotSize / 2 - bgInset,
                                width: rowWidth + bgInset * 2,
                                height: barSlotSize + bgInset * 2)
            barBG.path = CGPath(roundedRect: bgRect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        }
        refreshBar(animated: false)
    }

    private func applySlotPath(_ slot: SKShapeNode) {
        let rect = CGRect(x: -barSlotSize/2, y: -barSlotSize/2, width: barSlotSize, height: barSlotSize)
        slot.path = CGPath(roundedRect: rect, cornerWidth: barSlotSize * 0.22, cornerHeight: barSlotSize * 0.22, transform: nil)
    }

    private func layoutBoard() {
        guard !tiles.isEmpty else { return }
        let pad: CGFloat = 14

        // Área do tabuleiro: em paisagem fica à DIREITA da barra vertical; em retrato fica
        // ABAIXO da barra horizontal. Quase a tela toda em ambos.
        let boardMinX, boardMaxX, boardMinY, boardMaxY: CGFloat
        if isLandscape {
            let barRight = (barCenters.first?.x ?? 0) + barSlotSize / 2 + 8
            boardMinX = barRight + 14
            boardMaxX = size.width - rightInset - pad
            boardMinY = bottomInset + pad
            boardMaxY = size.height - topInset - pad
        } else {
            let barBottom = (barCenters.first?.y ?? size.height) - barSlotSize / 2
            boardMinX = leftInset + pad
            boardMaxX = size.width - rightInset - pad
            boardMinY = bottomInset + 16
            boardMaxY = barBottom - 16
        }
        let availW = max(60, boardMaxX - boardMinX)
        let availH = max(60, boardMaxY - boardMinY)

        // Reserva espaço p/ a elevação visual (os degraus sobem na tela).
        let elevModel = GameConst.tile * GameConst.elevation * CGFloat(maxLayer)
        let modelW = (tiles.map(\.x).max()! - tiles.map(\.x).min()!) + GameConst.tile
        let modelH = (tiles.map(\.y).max()! - tiles.map(\.y).min()!) + GameConst.tile + elevModel

        var scale = min(availW / modelW, availH / modelH)
        // Cards MÉDIOS: footprint compacto já deixa os cards grandes; o teto só evita que
        // pilhas minúsculas fiquem absurdas.
        scale = min(scale, (availW / 3.1) / GameConst.tile)
        boardScale = scale
        displayTile = GameConst.tile * scale
        // Centra na área disponível, compensando a elevação (sobe).
        let elevScreen = displayTile * GameConst.elevation * CGFloat(maxLayer)
        boardCenterScreen = CGPoint(x: (boardMinX + boardMaxX) / 2,
                                    y: boardMinY + availH / 2 - elevScreen / 2)

        // Reconstrói nós no novo tamanho de tile e reposiciona.
        let isText = theme.isText
        for t in tiles where t.onBoard {
            let node = tileNodes[t.id] ?? {
                let n = TileNode(); boardLayer.addChild(n); tileNodes[t.id] = n; return n
            }()
            node.build(side: displayTile, colorIdx: t.colorIdx, icon: t.icon, isText: isText)
            node.position = screenPos(for: t)
            node.zPosition = CGFloat(t.layer) * 1000 + t.y
        }
        recomputeBlocked()
    }

    private func screenPos(for t: TileModel) -> CGPoint {
        // Camadas superiores sobem na tela → relevo 3D dos degraus. O deslocamento
        // horizontal dos degraus já vem do meio-tile no modelo (mantém a pirâmide centrada).
        let elev = displayTile * GameConst.elevation * CGFloat(t.layer)
        return CGPoint(
            x: boardCenterScreen.x + (t.x - modelCenter.x) * boardScale,
            y: boardCenterScreen.y - (t.y - modelCenter.y) * boardScale + elev)  // inverte y, +elev = sobe
    }

    // MARK: Bloqueio reativo

    /// Bloqueio estilo Mahjong: só é clicável o tile com NENHUM outro card por cima.
    /// Bloqueado se algum tile vivo de camada superior sobrepõe seu footprint (mesmo
    /// parcialmente) em x E y. Dentro de uma camada os tiles não se sobrepõem.
    private func isBlocked(_ t: TileModel) -> Bool {
        guard t.onBoard else { return false }
        for o in tiles where o.onBoard && o.id != t.id && o.layer > t.layer {
            if abs(o.x - t.x) < GameConst.coverThr && abs(o.y - t.y) < GameConst.coverThr {
                return true
            }
        }
        return false
    }

    private func recomputeBlocked() {
        for t in tiles where t.onBoard {
            tileNodes[t.id]?.setBlocked(isBlocked(t))
        }
    }

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didWin, let touch = touches.first else { return }
        let loc = touch.location(in: boardLayer)
        // Pega o tile vivo, não-bloqueado, com maior zPosition sob o toque.
        var best: TileModel?
        var bestZ: CGFloat = -.greatestFiniteMagnitude
        for t in tiles where t.onBoard && !isBlocked(t) {
            guard let node = tileNodes[t.id] else { continue }
            let half = node.side / 2
            let p = node.position
            if abs(loc.x - p.x) <= half && abs(loc.y - p.y) <= half {
                if node.zPosition > bestZ { bestZ = node.zPosition; best = t }
            }
        }
        if let t = best { tap(t) }
    }

    // MARK: Regras (porte fiel do protótipo)

    private func tap(_ tile: TileModel) {
        guard let idx = tiles.firstIndex(where: { $0.id == tile.id }), tiles[idx].onBoard else { return }

        let completesTrio = bar.filter { $0.icon == tile.icon }.count + 1 >= GameConst.trio

        // Barra CHEIA (7) e este toque NÃO completa trio → reseta a bandeja: devolve TODOS
        // os cards às posições originais e NÃO coleta este. Nunca trava, nunca game-over.
        if !completesTrio && bar.count >= GameConst.barSize {
            SoundPlayer.shared.play(.tap)
            for t in bar {
                if let i = tiles.firstIndex(where: { $0.id == t.id }) {
                    tiles[i].inBar = false
                    returnTileToBoard(tiles[i])
                }
            }
            bar = []
            resetsThisGame += 1
            onBarReset?()
            refreshBar(animated: true)
            recomputeBlocked()
            onStateChanged?()
            return
        }

        // Coleta o card: anima voando p/ a barra e remove do tabuleiro.
        tiles[idx].inBar = true
        flyTileToBar(tile)
        bar.append(tiles[idx])
        bar.sort { $0.icon < $1.icon }

        if completesTrio {
            SoundPlayer.shared.play(.match)
            Haptics.success()
            let toClear = bar.filter { $0.icon == tile.icon }.prefix(GameConst.trio)
            let clearIds = Set(toClear.map(\.id))
            bar.removeAll { clearIds.contains($0.id) }
            for id in clearIds {
                if let i = tiles.firstIndex(where: { $0.id == id }) {
                    tiles[i].cleared = true
                    tiles[i].inBar = false
                }
            }
            refreshBar(animated: true, poppedIcon: nil)
            recomputeBlocked()
            checkWin()
            onStateChanged?()
        } else {
            SoundPlayer.shared.play(.tap)
            Haptics.tap()
            refreshBar(animated: true, poppedIcon: tile.icon)
            recomputeBlocked()
            onStateChanged?()
        }
    }

    private func checkWin() {
        let remaining = tiles.contains { !$0.cleared }
        if !remaining && !didWin {
            didWin = true
            SoundPlayer.shared.play(.win)
            onWin?(resetsThisGame > 0)
        }
    }

    // MARK: Animações

    private func flyTileToBar(_ tile: TileModel) {
        guard let node = tileNodes[tile.id] else { return }
        tileNodes[tile.id] = nil
        if reduceMotion {
            node.removeFromParent()
            return
        }
        // boardLayer e barLayer ficam na origem, então coords de cena == coords de layer.
        // A barra reorganiza, então a mira é o meio da barra (aproximação suficiente).
        let target = barCenters.isEmpty
            ? CGPoint(x: size.width / 2, y: size.height - topInset - 40)
            : barCenters[GameConst.barSize / 2]
        node.zPosition = 5000
        let move = SKAction.move(to: target, duration: 0.22)
        move.timingMode = .easeIn
        let shrink = SKAction.scale(to: max(0.2, barSlotSize / max(1, node.side)), duration: 0.22)
        let fade = SKAction.fadeOut(withDuration: 0.16)
        node.run(.sequence([.group([move, shrink]), fade, .removeFromParent()]))
    }

    private func returnTileToBoard(_ tile: TileModel) {
        let isText = theme.isText
        let node = TileNode()
        node.build(side: displayTile, colorIdx: tile.colorIdx, icon: tile.icon, isText: isText)
        node.position = screenPos(for: tile)
        node.zPosition = CGFloat(tile.layer) * 1000 + tile.y
        boardLayer.addChild(node)
        tileNodes[tile.id] = node
        if !reduceMotion {
            node.setScale(0.2)
            node.run(.scale(to: 1.0, duration: 0.2))
        }
    }

    /// Redesenha o conteúdo dos 7 slots a partir do modelo da barra.
    private func refreshBar(animated: Bool, poppedIcon: String? = nil) {
        guard !barSlotNodes.isEmpty else { return }
        for (i, slot) in barSlotNodes.enumerated() {
            slot.removeAllChildren()
            let filled = i < bar.count
            slot.fillColor = filled ? Theme.skColor(bar[i].colorIdx)
                                     : SKColor(white: 0, alpha: 0.10)
            slot.strokeColor = .clear
            if filled {
                let t = bar[i]
                let isText = theme.isText
                let lbl = SKLabelNode(text: t.icon)
                lbl.verticalAlignmentMode = .center
                lbl.horizontalAlignmentMode = .center
                lbl.fontName = "ArialRoundedMTBold"
                lbl.fontSize = barSlotSize * (isText ? 0.52 : 0.58)
                slot.addChild(lbl)
                if animated && !reduceMotion && poppedIcon == t.icon {
                    slot.setScale(0.6)
                    slot.run(.sequence([.scale(to: 1.12, duration: 0.1), .scale(to: 1.0, duration: 0.08)]))
                }
            } else {
                slot.setScale(1.0)
            }
        }
    }
}
