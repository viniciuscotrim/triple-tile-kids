import Testing
@testable import TripleTileKids

/// O coração do jogo é a SOLUBILIDADE garantida + distribuição correta (sempre 3 de cada,
/// nunca 1 ou 2 sobrando) sob o bloqueio estilo Mahjong.
struct BoardGeneratorTests {

    /// Bloqueio idêntico ao da cena: tile vivo de camada superior cobrindo o footprint.
    private func blocked(_ t: TileModel, _ tiles: [TileModel]) -> Bool {
        for o in tiles where o.onBoard && o.id != t.id && o.layer > t.layer {
            if abs(o.x - t.x) < GameConst.coverThr && abs(o.y - t.y) < GameConst.coverThr {
                return true
            }
        }
        return false
    }

    /// Simula uma partida resolvível tocando sempre o tile LIVRE de menor id.
    /// Por construção, quem cobre tem camada maior (id menor), então o menor id livre é
    /// sempre o menor id restante → trios saem em sequência, a barra nunca passa de 3.
    private func isSolvable(_ initial: [TileModel]) -> Bool {
        var tiles = initial
        var bar: [Int] = []
        var guardSteps = tiles.count * 4 + 10
        while tiles.contains(where: { !$0.cleared }) {
            guardSteps -= 1
            if guardSteps < 0 { return false }
            guard let pick = tiles.filter({ $0.onBoard && !blocked($0, tiles) }).min(by: { $0.id < $1.id })
            else { return false }
            if let i = tiles.firstIndex(where: { $0.id == pick.id }) { tiles[i].inBar = true; bar.append(pick.id) }
            var counts: [String: [Int]] = [:]
            for id in bar { if let t = tiles.first(where: { $0.id == id }) { counts[t.icon, default: []].append(id) } }
            if let trio = counts.values.first(where: { $0.count >= GameConst.trio }) {
                let clear = Set(trio.prefix(GameConst.trio))
                bar.removeAll { clear.contains($0) }
                for id in clear { if let i = tiles.firstIndex(where: { $0.id == id }) { tiles[i].cleared = true; tiles[i].inBar = false } }
            }
            if bar.count > GameConst.barSize { return false }
        }
        return bar.isEmpty
    }

    @Test(arguments: [2, 3, 5, 8, 12, 20, 35, 50])
    func everyBoardIsSolvableAndComplete(trios: Int) {
        for seed in 1...50 {
            var rng = SeededRNG(seed: UInt64(seed) &* 2654435761 &+ UInt64(trios))
            let board = BoardGenerator.build(theme: .animais, trios: trios, rng: &rng)
            // total = trios × 3
            #expect(board.count == trios * GameConst.trio)
            // cada ícone aparece em múltiplo de 3 (nunca 1 ou 2 sobrando p/ completar trio)
            var counts: [String: Int] = [:]
            board.forEach { counts[$0.icon, default: 0] += 1 }
            #expect(counts.values.allSatisfy { $0 % GameConst.trio == 0 })
            // solúvel sob bloqueio estrito
            #expect(isSolvable(board), "Insolúvel: trios=\(trios) seed=\(seed)")
        }
    }

    /// Há SEMPRE pelo menos um tile livre no início (senão a criança não consegue começar).
    @Test(arguments: [2, 8, 50])
    func boardHasFreeTilesAtStart(trios: Int) {
        let board = BoardGenerator.build(theme: .frutas, trios: trios)
        #expect(board.contains { $0.onBoard && !blocked($0, board) })
    }
}
