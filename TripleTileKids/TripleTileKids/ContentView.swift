import SwiftUI
import SpriteKit

/// Mantém uma instância estável da cena, o estado de vitória, as STATS (placar) e a
/// PERSISTÊNCIA (salva/retoma a partida).
final class GameHost: ObservableObject {
    let scene = GameScene()
    @Published var won = false
    @Published var clearedTrios = 0
    @Published var totalTrios = 0
    private let saveKey = "savedGame"

    init() {
        scene.scaleMode = .resizeFill
        let d = UserDefaults.standard
        scene.onWin = { [weak self] hadReset in
            self?.won = true
            d.set(d.integer(forKey: Stat.games) + 1, forKey: Stat.games)
            if !hadReset { d.set(d.integer(forKey: Stat.clean) + 1, forKey: Stat.clean) }
            self?.save()
        }
        scene.onBarReset = {
            d.set(d.integer(forKey: Stat.resets) + 1, forKey: Stat.resets)
        }
        scene.onStateChanged = { [weak self] in self?.save(); self?.syncProgress() }
    }

    func syncProgress() {
        clearedTrios = scene.clearedTrios
        totalTrios = scene.totalTrios
    }

    func newGame(theme: ThemeKey, trios: Int, shape: ShapeKey) {
        won = false
        scene.newGame(theme: theme, trios: trios, shape: shape)   // dispara onStateChanged → save + progresso
    }

    func save() {
        if let data = try? JSONEncoder().encode(scene.snapshot()) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    /// Retoma a partida salva, se houver. Retorna se conseguiu.
    func restoreSaved() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let s = try? JSONDecoder().decode(GameState.self, from: data),
              !s.tiles.isEmpty else { return false }
        won = scene.restore(s)
        syncProgress()
        return true
    }
}

/// Chaves das stats (placar) no UserDefaults.
enum Stat {
    static let games = "stat_games"     // partidas concluídas
    static let resets = "stat_resets"   // vezes que a barra encheu sem combinação
    static let clean = "stat_clean"     // partidas concluídas SEM nenhum reset
}

struct ContentView: View {
    @AppStorage("theme") private var themeRaw = ThemeKey.animais.rawValue
    @AppStorage("trios") private var trios = GameConst.defaultTrios
    @AppStorage("reorgOnRotate") private var reorgOnRotate = true
    @EnvironmentObject private var store: Store
    @StateObject private var host = GameHost()
    @State private var showSettings = false
    @State private var didStart = false
    @Environment(\.scenePhase) private var scenePhase

    private var theme: ThemeKey { ThemeKey(rawValue: themeRaw) ?? .animais }
    /// Formato fixo: só pirâmide (o seletor de formatos foi removido).
    private var shape: ShapeKey { .piramide }
    /// Dificuldade efetiva respeitando o teto liberado (50 grátis / 70 premium).
    private var effTrios: Int { min(trios, store.maxTrios) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.965, blue: 0.898),
                             Color(red: 1.0, green: 0.847, blue: 0.608)],
                    center: UnitPoint(x: 0.5, y: 0.12),
                    startRadius: 8, endRadius: max(geo.size.width, geo.size.height))
                    .ignoresSafeArea()

                SpriteView(scene: host.scene, options: [.allowsTransparency])
                    .ignoresSafeArea()

                // Indicador de progresso (trios encontrados / total) — topo, centro.
                VStack {
                    Text("🧩 \(host.clearedTrios)/\(host.totalTrios)")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.30, green: 0.30, blue: 0.34))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(.white.opacity(0.82), in: Capsule())
                        .padding(.top, 2)
                    Spacer()
                }

                // Engrenagem: paisagem em cima (oposto à barra à esquerda), retrato embaixo.
                let landscape = geo.size.width > geo.size.height
                VStack {
                    if !landscape { Spacer() }
                    HStack {
                        Spacer()
                        Button { showSettings = true } label: {
                            Text("⚙️").font(.system(size: 34))
                                .padding(8)
                        }
                        .accessibilityLabel("configurações")
                    }
                    if landscape { Spacer() }
                }
                .padding(.horizontal, 8)

                if host.won { winOverlay }
                if showSettings {
                    SettingsView(
                        theme: Binding(get: { theme }, set: { themeRaw = $0.rawValue }),
                        trios: $trios,
                        reorgOnRotate: $reorgOnRotate,
                        close: { showSettings = false })
                }
                if store.showPaywall { PaywallView() }
            }
            .onAppear {
                host.scene.updateSafeArea(top: geo.safeAreaInsets.top, bottom: geo.safeAreaInsets.bottom,
                                          left: geo.safeAreaInsets.leading, right: geo.safeAreaInsets.trailing)
                // Só na 1ª vez: RETOMA o jogo salvo (começa de onde parou); senão, novo jogo.
                // Girar NÃO reinicia (a cena reorganiza via reflow); só mexer nas configs reinicia.
                host.scene.reorganizeOnRotate = reorgOnRotate
                #if DEBUG
                if ProcessInfo.processInfo.environment["TT_SETTINGS"] != nil { showSettings = true }
                #endif
                if !didStart {
                    didStart = true
                    // Defensivo: se o tema salvo estiver bloqueado (ex.: expirou o anúncio), volta pro grátis.
                    if !store.isThemeUnlocked(theme) { themeRaw = ThemeKey.animais.rawValue }
                    if !host.restoreSaved() { host.newGame(theme: theme, trios: effTrios, shape: shape) }
                }
            }
            .onChange(of: reorgOnRotate) { _, v in host.scene.reorganizeOnRotate = v }
            .onChange(of: geo.safeAreaInsets) { _, new in
                host.scene.updateSafeArea(top: new.top, bottom: new.bottom, left: new.leading, right: new.trailing)
            }
            .onChange(of: themeRaw) { _, _ in host.newGame(theme: theme, trios: effTrios, shape: shape) }
            .onChange(of: trios) { _, _ in host.newGame(theme: theme, trios: effTrios, shape: shape) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { host.save() }   // 2º plano/fechando → salva a progressão
            }
        }
    }

    private var winOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("🎉")
                    .font(.system(size: 120))
                    .modifier(BounceEffect())
                Button {
                    host.newGame(theme: theme, trios: effTrios, shape: shape)
                } label: {
                    Text("🔄")
                        .font(.system(size: 56))
                        .padding(.vertical, 12).padding(.horizontal, 40)
                        .background(Color(red: 0.42, green: 0.80, blue: 0.47))
                        .clipShape(RoundedRectangle(cornerRadius: 36))
                        .shadow(color: Color(red: 0.30, green: 0.66, blue: 0.35), radius: 0, x: 0, y: 7)
                }
                .accessibilityLabel("jogar de novo")
            }
        }
    }
}

/// Pulinho do 🎉 (respeita Reduce Motion automaticamente: SwiftUI desativa repeatForever).
private struct BounceEffect: ViewModifier {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .offset(y: up ? -22 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}

#Preview {
    ContentView().environmentObject(Store())
}
