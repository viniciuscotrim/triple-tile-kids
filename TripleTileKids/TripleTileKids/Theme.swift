import SwiftUI
import SpriteKit

// MARK: - Constantes da engine (fiéis ao protótipo validado)

enum GameConst {
    /// Tamanho do tile em unidades de modelo (não-pixels). O layout escala isso por proporção de tela.
    static let tile: CGFloat = 64
    /// Espaçamento do grid DENTRO de uma camada (cards encostados, todos 100% visíveis,
    /// sem cobrir uns aos outros na mesma camada).
    static var spacing: CGFloat { tile }
    /// Deslocamento entre camadas = MEIO tile. A camada de cima fica encaixada sobre os
    /// CANTOS de 4 cards de baixo (cobre 1/4 de cada) → pirâmide em degraus, e você vê
    /// todos os cards parcialmente.
    static var layerOffset: CGFloat { tile * 0.5 }
    /// Limiar de cobertura: pega o overlap de 1/4 (offset 0.5·tile) e ignora vizinhos
    /// (≥1.5·tile). Um card de camada superior dentro deste raio em x E y cobre o de baixo.
    static var coverThr: CGFloat { tile * 0.85 }
    /// Elevação visual por camada (sobe na tela) — dá o relevo 3D dos degraus.
    static let elevation: CGFloat = 0.14

    static let barSize = 7
    static let trio = 3

    /// Faixa do slider de dificuldade: nº de TRIOS (tipos). Total de tiles = trios × 3.
    static let minTrios = 2
    static let maxTrios = 70          // teto máximo = 3 × 70 = 210 cards (desbloqueado)
    static let freeMaxTrios = 50      // livre até 50 trios (150 cards); 51–70 é premium/anúncio
    static let defaultTrios = 6
}

// MARK: - Tema (@AppStorage guarda o rawValue String)

enum ThemeKey: String, CaseIterable, Identifiable {
    case animais, frutas, alfabeto, numeros, casa, cotidiano
    case formas, vegetais, praia, bandeiras
    case rostos, princesas, carros, futebol, sereia
    var id: String { rawValue }
    var spec: ThemeSpec { Theme.all[self]! }
    var label: String { spec.label }
    var icons: [String] { spec.icons }
    var isText: Bool { self == .alfabeto || self == .numeros }
}

struct ThemeSpec {
    let label: String
    let icons: [String]
}

/// Formato da pilha (todos em degraus empilhados, estilo Mahjong).
enum ShapeKey: String, CaseIterable, Identifiable {
    case piramide, circulo, coracao, estrela, triangulo, quadrado, losango
    var id: String { rawValue }
    var label: String {
        switch self {
        case .piramide:  return "🔺"
        case .circulo:   return "⭕"
        case .coracao:   return "❤️"
        case .estrela:   return "⭐"
        case .triangulo: return "🔻"
        case .quadrado:  return "⬜"
        case .losango:   return "🔶"
        }
    }
}

// MARK: - Catálogo de temas, tamanhos e cores

enum Theme {
    static let all: [ThemeKey: ThemeSpec] = [
        .animais:   ThemeSpec(label: "🐶", icons: ["🐶","🐱","🐰","🐸","🦁","🐠","🐝","🐢","🐼","🦊","🐧","🐮","🐷","🐔"]),
        .frutas:    ThemeSpec(label: "🍎", icons: ["🍎","🍌","🍓","🍇","🍊","🍉","🍐","🥝","🍒","🥥","🍑","🍍","🥭","🫐"]),
        .alfabeto:  ThemeSpec(label: "🔤", icons: ["A","B","C","D","E","F","G","H","I","J","K","L","M","N"]),
        .numeros:   ThemeSpec(label: "🔢", icons: ["1","2","3","4","5","6","7","8","9","0","+","-","=","×"]),
        .casa:      ThemeSpec(label: "🏠", icons: ["🛏️","🪑","🛋️","🚪","🪟","🚽","🛁","🧴","🕯️","🧹","🔑","🪣","🧺","🛒"]),
        .cotidiano: ThemeSpec(label: "🎒", icons: ["⚽","🎒","✏️","📚","🧸","🚗","👟","☂️","🎈","🎁","🎨","🪁","🎸","⏰"]),
        .formas:    ThemeSpec(label: "🔷", icons: ["🔴","🟠","🟡","🟢","🔵","🟣","🟤","⚫","⭐","❤️","🔺","🔷","⬛","💎"]),
        .vegetais:  ThemeSpec(label: "🥕", icons: ["🥕","🥦","🌽","🥔","🍅","🥒","🧅","🧄","🫑","🍆","🥬","🌶️","🫛","🥗"]),
        .praia:     ThemeSpec(label: "🏖️", icons: ["🏖️","🌊","🏄","🐚","🦀","⛱️","🩴","🕶️","🏊","🐠","🌴","🍹","🪣","🐳"]),
        .bandeiras: ThemeSpec(label: "🏁", icons: ["🇧🇷","🇺🇸","🇯🇵","🇫🇷","🇩🇪","🇮🇹","🇪🇸","🇬🇧","🇨🇦","🇲🇽","🇦🇷","🇵🇹","🇳🇱","🇨🇭"]),
        .rostos:    ThemeSpec(label: "😀", icons: ["😀","😁","😂","🥰","😎","😍","🤩","😜","🥳","😇","🤓","🥺","😴","🤔"]),
        .princesas: ThemeSpec(label: "👸", icons: ["👸","🤴","👑","💎","🏰","🦄","🌹","✨","💖","🪄","🧚","👗","💍","🦢"]),
        .carros:    ThemeSpec(label: "🚗", icons: ["🚗","🚕","🚙","🚌","🏎️","🚓","🚑","🚒","🚐","🛻","🚚","🏍️","🚜","🚛"]),
        .futebol:   ThemeSpec(label: "⚽", icons: ["⚽","🏆","🥅","🧤","👟","🟨","🟥","🚩","🥇","🎽","📣","⏱️","🏟️","🌍"]),
        .sereia:    ThemeSpec(label: "🧜", icons: ["🧜","🐠","🐡","🦈","🐙","🐚","🪸","🐬","🐳","🦀","🦞","🐢","🌊","🐟"]),
    ]

    static let colorsHex = [
        "#FF8A3D","#FFD23F","#FF5DA2","#6BCB77","#FFB627","#4D96FF","#9D4EDD",
        "#52B788","#FF6B6B","#3DB8C9","#F38181","#A06CD5","#3CAEA3","#ED553B",
    ]

    private static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        return (Double((v >> 16) & 0xff) / 255.0,
                Double((v >> 8) & 0xff) / 255.0,
                Double(v & 0xff) / 255.0)
    }

    static func color(_ i: Int) -> Color {
        let c = rgb(colorsHex[i % colorsHex.count])
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    static func skColor(_ i: Int, brightness: Double = 1.0) -> SKColor {
        let c = rgb(colorsHex[i % colorsHex.count])
        return SKColor(red: c.r * brightness, green: c.g * brightness, blue: c.b * brightness, alpha: 1)
    }
}
