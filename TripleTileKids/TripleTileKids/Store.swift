import StoreKit
import SwiftUI

/// Monetização do Triple Tile.
/// • Grátis: formato pirâmide, temas Animais + Frutas, dificuldade até 50 trios (150 cards).
/// • Premium (IAP não-consumível, R$9,90): desbloqueia TUDO (todos os temas + até 70 trios)
///   e, na v1.1, remove os anúncios.
/// • Anúncio (v1.1): infra de desbloqueio temporário de 12h já pronta (grantThemeAdUnlock/
///   grantDifficultyAdUnlock) — só falta plugar o rewarded do AppLovin.
@MainActor
final class Store: ObservableObject {
    static let unlockAllID = "com.tripletile.unlockall"
    static let freeThemes: Set<ThemeKey> = [.animais, .frutas]
    static let adUnlockSeconds: Double = 12 * 3600      // desbloqueio por anúncio dura 12h

    @Published private(set) var isPremium = false
    @Published private(set) var product: Product?
    @Published private(set) var purchasing = false
    @Published var showPaywall = false
    /// Bump só pra forçar refresh da UI quando um desbloqueio por anúncio muda (v1.1).
    @Published private(set) var adTick = 0

    private let d = UserDefaults.standard
    private var updatesTask: Task<Void, Never>?

    #if DEBUG
    private let debugPremium = ProcessInfo.processInfo.environment["TT_PREMIUM"] != nil
    #endif

    init() {
        #if DEBUG
        if debugPremium { isPremium = true }
        #endif
        updatesTask = listenForTransactions()
        Task { await load() }
    }
    deinit { updatesTask?.cancel() }

    // MARK: — StoreKit 2

    func load() async {
        await refreshEntitlements()
        if let products = try? await Product.products(for: [Self.unlockAllID]) {
            product = products.first
        }
    }

    private func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.unlockAllID, t.revocationDate == nil {
                owned = true
            }
        }
        #if DEBUG
        isPremium = owned || debugPremium
        #else
        isPremium = owned
        #endif
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update {
                    await t.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    func purchase() async {
        guard let product else { return }
        purchasing = true; defer { purchasing = false }
        guard let result = try? await product.purchase() else { return }
        if case .success(let verification) = result, case .verified(let t) = verification {
            await t.finish()
            await refreshEntitlements()
            showPaywall = false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    var priceText: String { product?.displayPrice ?? "R$\u{00A0}9,90" }

    // MARK: — Consultas de desbloqueio

    func isThemeUnlocked(_ key: ThemeKey) -> Bool {
        if isPremium || Self.freeThemes.contains(key) { return true }
        return d.double(forKey: "adTheme_\(key.rawValue)") > Date().timeIntervalSince1970
    }

    var isDifficultyUnlocked: Bool {
        if isPremium { return true }
        return d.double(forKey: "adUnlockDifficulty") > Date().timeIntervalSince1970
    }

    /// Teto de trios que o jogador pode usar agora (50 livre, 70 desbloqueado).
    var maxTrios: Int { isDifficultyUnlocked ? GameConst.maxTrios : GameConst.freeMaxTrios }

    // MARK: — Desbloqueio por anúncio (12h) — usado na v1.1 pelo callback do rewarded

    func grantThemeAdUnlock(_ key: ThemeKey) {
        d.set(Date().timeIntervalSince1970 + Self.adUnlockSeconds, forKey: "adTheme_\(key.rawValue)")
        adTick += 1
    }
    func grantDifficultyAdUnlock() {
        d.set(Date().timeIntervalSince1970 + Self.adUnlockSeconds, forKey: "adUnlockDifficulty")
        adTick += 1
    }
    /// Tempo restante (s) de um desbloqueio por anúncio, ou 0.
    func adUnlockRemaining(theme key: ThemeKey) -> Double {
        max(0, d.double(forKey: "adTheme_\(key.rawValue)") - Date().timeIntervalSince1970)
    }
}

/// Tela de compra do desbloqueio total (R$9,90).
struct PaywallView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { store.showPaywall = false }
            VStack(spacing: 16) {
                Text("🔓").font(.system(size: 60))
                Text("Desbloquear tudo")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                VStack(alignment: .leading, spacing: 10) {
                    benefit("🎨", "Todos os temas")
                    benefit("🃏", "Até 210 cards (dificuldade máxima)")
                    benefit("♾️", "Para sempre, sem anúncios")
                }
                .padding(.vertical, 4)
                Button { Task { await store.purchase() } } label: {
                    Text(store.purchasing ? "Processando…" : "Comprar — \(store.priceText)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color(red: 0.42, green: 0.80, blue: 0.47),
                                    in: RoundedRectangle(cornerRadius: 18))
                }
                .disabled(store.purchasing || store.product == nil)
                Button { Task { await store.restore() } } label: {
                    Text("Restaurar compra")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                }
                Button { store.showPaywall = false } label: {
                    Text("Agora não").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 380)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 12)
            .padding(24)
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(icon).font(.system(size: 22))
            Text(text).font(.system(size: 15, weight: .medium))
            Spacer()
        }
    }
}
