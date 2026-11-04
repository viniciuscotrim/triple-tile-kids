import CoreGraphics

/// Modelo de um card. Coordenadas (x,y) em espaço de modelo, centradas em 0;
/// y cresce para BAIXO — a cena inverte ao desenhar.
struct TileModel: Identifiable, Codable {
    let id: Int
    let icon: String
    let colorIdx: Int
    let x: CGFloat
    let y: CGFloat
    let layer: Int
    var cleared: Bool = false   // saiu do jogo (trio completo)
    var inBar: Bool = false     // está na barra de coleta

    /// Card "vivo" no tabuleiro: clicável/desenhável.
    var onBoard: Bool { !cleared && !inBar }
}

/// Estado completo de uma partida — para salvar/retomar de onde parou.
struct GameState: Codable {
    var theme: String
    var trios: Int
    var shape: String
    var tiles: [TileModel]
    var barIds: [Int]
    var resetsThisGame: Int
}
