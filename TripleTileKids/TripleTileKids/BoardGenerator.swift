import CoreGraphics
import Foundation

/// PRNG determinístico (xorshift) para tornar a geração testável e reproduzível.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed != 0 ? seed : 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

private struct RawTile { let x: CGFloat; let y: CGFloat; let layer: Int }

enum BoardGenerator {

    // MARK: API

    /// Constrói o tabuleiro: posições no FORMATO escolhido (todas em degraus empilhados,
    /// deslocadas meio-tile entre camadas → estilo Mahjong, todos os cards visíveis), e
    /// ícones ESPALHADOS (a criança procura) com solubilidade garantida (barra ≤ 7).
    static func build<R: RandomNumberGenerator>(theme: ThemeKey, trios: Int, shape: ShapeKey = .piramide,
                                                aspect: CGFloat = 1.0, rng: inout R) -> [TileModel] {
        let n = max(1, min(GameConst.maxTrios, trios))
        let total = n * GameConst.trio
        let icons = theme.icons
        let m = max(1, icons.count)

        let raw = (shape == .piramide)
            ? pyramidPositions(total: total, aspect: aspect)
            : shapedPositions(shape: shape, total: total, aspect: aspect)

        // Um ícone (e cor) por TRIO. Tipo t → icons[t % m].
        let nTypes = max(1, raw.count / GameConst.trio)
        let trioIcons: [(String, Int)] = (0..<nTypes).map { (icons[$0 % m], $0 % m) }
        return assignIcons(raw: raw, trioIcons: trioIcons, rng: &rng)
    }

    /// REORGANIZA cards existentes (ao girar/mudar formato sem reiniciar o jogo): recebe o
    /// multiset de ícones que SOBRARAM (board + barra, sempre múltiplo de 3 por ícone),
    /// gera posições novas no formato/aspect e reatribui esses MESMOS ícones, espalhados e
    /// solúveis (barra começa vazia). Preserva o progresso (trios já limpos continuam limpos).
    static func reflow<R: RandomNumberGenerator>(remaining: [(icon: String, colorIdx: Int)],
                                                 shape: ShapeKey, aspect: CGFloat, rng: inout R) -> [TileModel] {
        let count = remaining.count
        guard count >= GameConst.trio, count % GameConst.trio == 0 else { return [] }
        let raw = (shape == .piramide)
            ? pyramidPositions(total: count, aspect: aspect)
            : shapedPositions(shape: shape, total: count, aspect: aspect)

        // um trio por (ícone, cor): agrupa o multiset e gera count/3 trios, embaralhados.
        var byIcon: [String: (color: Int, n: Int)] = [:]
        for t in remaining { byIcon[t.icon, default: (t.colorIdx, 0)].n += 1 }
        var trioIcons: [(String, Int)] = []
        for (icon, v) in byIcon { for _ in 0..<(v.n / GameConst.trio) { trioIcons.append((icon, v.color)) } }
        for i in stride(from: trioIcons.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1)); trioIcons.swapAt(i, j)
        }
        return assignIcons(raw: raw, trioIcons: trioIcons, rng: &rng)
    }

    static func build(theme: ThemeKey, trios: Int, shape: ShapeKey = .piramide, aspect: CGFloat = 1.0) -> [TileModel] {
        var sys = SystemRandomNumberGenerator()
        return build(theme: theme, trios: trios, shape: shape, aspect: aspect, rng: &sys)
    }

    static func reflow(remaining: [(icon: String, colorIdx: Int)], shape: ShapeKey, aspect: CGFloat) -> [TileModel] {
        var sys = SystemRandomNumberGenerator()
        return reflow(remaining: remaining, shape: shape, aspect: aspect, rng: &sys)
    }

    // MARK: Pirâmide retangular tradicional

    private static func pyramidCap(_ w: Int, _ h: Int) -> Int {
        var s = 0, k = 0
        while w - k > 0 && h - k > 0 { s += (w - k) * (h - k); k += 1 }
        return s
    }

    private static func pyramidPositions(total: Int, aspect: CGFloat) -> [RawTile] {
        let s = GameConst.spacing
        let off = GameConst.layerOffset
        let target = Double(max(0.5, aspect))

        var bestW = 1, bestH = 1, bestKey = (Int.max, Int.max, Int.max, Int.max)
        let hi = max(2, Int(Double(total).squareRoot().rounded()) + 2)
        for h in 1...hi {
            for w in h...(3 * h + 1) {
                let cap = pyramidCap(w, h)
                guard cap >= total else { continue }
                let multi = (w * h < total) ? 0 : 1
                let aspErr = Int((abs(Double(w) / Double(h) - target)) * 2)
                let key = (multi, aspErr, cap - total, w * h)
                if key < bestKey { bestKey = key; bestW = w; bestH = h }
            }
        }

        var raw: [RawTile] = []
        var placed = 0, k = 0
        while placed < total, bestW - k > 0, bestH - k > 0 {
            let lw = bestW - k, lh = bestH - k
            let o = CGFloat(k) * off
            outer: for r in 0..<lh {
                for c in 0..<lw {
                    if placed >= total { break outer }
                    raw.append(RawTile(x: CGFloat(c) * s + o, y: CGFloat(r) * s + o, layer: k))
                    placed += 1
                }
            }
            k += 1
        }
        return raw
    }

    // MARK: Formatos (mapa de altura) — círculo, coração, estrela, triângulo, quadrado, losango

    /// `true` se o ponto normalizado (x,y ∈ [-1,1]) está dentro do formato.
    private static func inShape(_ shape: ShapeKey, _ x: Double, _ y: Double) -> Bool {
        switch shape {
        case .circulo:
            return x * x + y * y <= 1.02
        case .losango:
            return abs(x) + abs(y) <= 1.02
        case .triangulo:
            // apex em cima (y negativo no modelo = topo da tela depois do flip)
            let yy = -y                      // base embaixo
            return yy <= 1 && yy >= -1 && abs(x) <= (1 - yy) / 2 + 0.02
        case .quadrado:
            // anel quadrado (vazado no meio)
            let d = max(abs(x), abs(y))
            return d <= 1.02 && d >= 0.5
        case .coracao:
            let yy = -y * 1.15               // ponta p/ baixo
            let v = pow(x * x + yy * yy - 1, 3) - x * x * yy * yy * yy
            return v <= 0.0
        case .estrela:
            return pointInStar(x, y)
        case .piramide:
            return true
        }
    }

    private static func pointInStar(_ x: Double, _ y: Double) -> Bool {
        // 5 pontas: polígono de 10 vértices alternando raio externo/interno.
        var poly: [(Double, Double)] = []
        let outer = 1.0, inner = 0.42
        for i in 0..<10 {
            let ang = Double.pi / 2 + Double(i) * Double.pi / 5   // começa no topo
            let rad = (i % 2 == 0) ? outer : inner
            poly.append((cos(ang) * rad, -sin(ang) * rad))
        }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let (xi, yi) = poly[i], (xj, yj) = poly[j]
            if (yi > y) != (yj > y),
               x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func shapedPositions(shape: ShapeKey, total: Int, aspect: CGFloat) -> [RawTile] {
        let s = GameConst.spacing
        let off = GameConst.layerOffset
        let ar = sqrt(Double(max(0.5, aspect)))

        // EMPILHAR: silhueta compacta (poucas células) com torres altas → poucos cards
        // livres e cards grandes, mas com células o bastante p/ a forma ainda remeter.
        let wantCells = max(8, Int((Double(total) / 4.0).rounded()))

        // Acha o grid cuja máscara tem nº de células mais perto de `wantCells`.
        var cells: [(Int, Int)] = []
        var bestDiff = Int.max
        var gwSel = 3, ghSel = 3
        for base in 3...44 {
            let gw = max(3, Int((Double(base) * ar).rounded()))
            let gh = max(3, Int((Double(base) / ar).rounded()))
            var cs: [(Int, Int)] = []
            for c in 0..<gw {
                for r in 0..<gh {
                    let x = (Double(c) / Double(max(1, gw - 1)) - 0.5) * 2
                    let y = (Double(r) / Double(max(1, gh - 1)) - 0.5) * 2
                    if inShape(shape, x, y) { cs.append((c, r)) }
                }
            }
            let diff = abs(cs.count - wantCells)
            if diff < bestDiff { bestDiff = diff; cells = cs; gwSel = gw; ghSel = gh }
            if cs.count > wantCells * 2 + 4 { break }
        }
        guard !cells.isEmpty else { return pyramidPositions(total: total, aspect: aspect) }

        // Distância normalizada ao centro (p/ viés: centro empilha mais alto = monte).
        let cx = Double(gwSel - 1) / 2, cy = Double(ghSel - 1) / 2
        let dists = cells.map { hypot(Double($0.0) - cx, Double($0.1) - cy) }
        let maxD = max(0.001, dists.max() ?? 1)

        // Toda célula começa com 1 (silhueta cheia); o resto "derrama" com viés forte ao
        // centro → torres altas no meio, baixas na borda.
        var heights: [Int]
        if total >= cells.count {
            heights = [Int](repeating: 1, count: cells.count)
            var remaining = total - cells.count
            while remaining > 0 {
                var best = 0, bestScore = Double.greatestFiniteMagnitude
                for i in cells.indices {
                    let score = Double(heights[i]) + 1.2 * (dists[i] / maxD)
                    if score < bestScore { bestScore = score; best = i }
                }
                heights[best] += 1; remaining -= 1
            }
        } else {
            // poucos cards: preenche as células mais centrais
            heights = [Int](repeating: 0, count: cells.count)
            let order = cells.indices.sorted { dists[$0] < dists[$1] }
            for k in 0..<total { heights[order[k]] = 1 }
        }

        var raw: [RawTile] = []
        for i in cells.indices {
            let (c, r) = cells[i]
            for L in 0..<heights[i] {
                let o = CGFloat(L) * off
                raw.append(RawTile(x: CGFloat(c) * s + o, y: CGFloat(r) * s + o, layer: L))
            }
        }
        return raw
    }

    // MARK: Grafo de cobertura + atribuição espalhada (compartilhado por todos os formatos)

    private static func assignIcons<R: RandomNumberGenerator>(raw: [RawTile], trioIcons: [(String, Int)],
                                                              rng: inout R) -> [TileModel] {
        let count = raw.count
        guard count > 0 else { return [] }
        let thr = GameConst.coverThr

        // quem cobre quem (mesmo teste do bloqueio em jogo)
        var coverers = [Int](repeating: 0, count: count)
        var covees = [[Int]](repeating: [], count: count)
        for j in 0..<count {
            for i in 0..<count where i != j {
                let a = raw[i], b = raw[j]
                if b.layer > a.layer && abs(b.x - a.x) < thr && abs(b.y - a.y) < thr {
                    coverers[i] += 1
                    covees[j].append(i)
                }
            }
        }

        // sequência de remoção ALEATÓRIA (tira um livre ao acaso) — é uma solução válida
        var free = (0..<count).filter { coverers[$0] == 0 }
        var seq: [Int] = []; seq.reserveCapacity(count)
        while !free.isEmpty {
            let pick = Int(rng.next() % UInt64(free.count))
            free.swapAt(pick, free.count - 1)
            let idx = free.removeLast()
            seq.append(idx)
            for c in covees[idx] {
                coverers[c] -= 1
                if coverers[c] == 0 { free.append(c) }
            }
        }

        // atribui TIPOS intercalando até 4 ícones ativos → cópias espalhadas, barra ≤ 7
        let nTypes = max(1, trioIcons.count)
        var typeOfPos = [Int](repeating: 0, count: count)
        var active: [(type: Int, count: Int)] = []
        var nextNew = 0
        func pending() -> Int { active.reduce(0) { $0 + $1.count } }
        func rnd(_ k: Int) -> Int { k <= 1 ? 0 : Int(rng.next() % UInt64(k)) }
        for pos in 0..<count {
            let pend = pending()
            let twos = active.indices.filter { active[$0].count == 2 }
            let canStart = nextNew < nTypes && active.count < 4 && pend <= 5
            var ai = -1
            if pend >= 6, !twos.isEmpty {
                ai = twos[rnd(twos.count)]
            } else if canStart && (active.isEmpty || rnd(100) < 60) {
                active.append((nextNew, 0)); nextNew += 1; ai = active.count - 1
            } else if !active.isEmpty {
                ai = rnd(active.count)
            } else {
                active.append((nextNew, 0)); nextNew += 1; ai = active.count - 1
            }
            active[ai].count += 1
            typeOfPos[pos] = active[ai].type
            if active[ai].count >= GameConst.trio { active.remove(at: ai) }
        }

        return seq.enumerated().map { orderIdx, rawIdx in
            let (icon, colorIdx) = trioIcons[typeOfPos[orderIdx] % nTypes]
            let e = raw[rawIdx]
            return TileModel(id: orderIdx, icon: icon, colorIdx: colorIdx,
                             x: e.x, y: e.y, layer: e.layer)
        }
    }
}
