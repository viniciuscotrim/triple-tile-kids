import SwiftUI

/// Menu da engrenagem: quantidade (slider) + FORMATO da pilha + tema.
/// Rolável (cabe em paisagem, onde a altura é curta).
struct SettingsView: View {
    @Binding var theme: ThemeKey
    @Binding var trios: Int
    @Binding var reorgOnRotate: Bool
    var close: () -> Void
    @EnvironmentObject private var store: Store

    @State private var showScores = false
    @AppStorage(Stat.games) private var statGames = 0
    @AppStorage(Stat.resets) private var statResets = 0
    @AppStorage(Stat.clean) private var statClean = 0
    private var assertividade: Int { statGames > 0 ? Int((Double(statClean) / Double(statGames) * 100).rounded()) : 0 }

    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var totalCards: Int { trios * GameConst.trio }

    var body: some View {
        GeometryReader { g in
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            ScrollView {
                VStack(spacing: 20) {
                    // Quantidade de cards (slider) --------------------------------
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Button { showScores = true } label: {
                                Text("📊").font(.system(size: 26))
                            }
                            .accessibilityLabel("placar")
                            Text("🃏").font(.system(size: 28))
                            Text("\(totalCards)")
                                .font(.system(size: 38, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color(red: 0.63, green: 0.42, blue: 0.83))
                            Text("cards").font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Text("🐣").font(.system(size: 22))
                            Slider(
                                value: Binding(get: { Double(min(trios, store.maxTrios)) },
                                               set: { trios = min(Int($0.rounded()), store.maxTrios) }),
                                in: Double(GameConst.minTrios)...Double(store.maxTrios), step: 1)
                                .tint(Color(red: 0.42, green: 0.80, blue: 0.47))
                            Text("🐘").font(.system(size: 22))
                        }
                        if !store.isDifficultyUnlocked {
                            Button { store.showPaywall = true } label: {
                                Text("🔒 até \(GameConst.maxTrios * GameConst.trio) cards — toque p/ desbloquear")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(red: 1.0, green: 0.541, blue: 0.239))
                            }
                        }
                    }

                    Divider()

                    // Girar reorganiza o tabuleiro (toggle) -----------------------
                    Toggle(isOn: $reorgOnRotate) {
                        HStack(spacing: 10) {
                            Text("🔄").font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Girar reorganiza").font(.system(size: 15, weight: .semibold))
                                Text("embaralha ao virar o aparelho")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(GrayGreenToggle())

                    Divider()

                    // Premium: desbloquear tudo (todos os temas + até 210 cards) ---
                    premiumSection

                    Divider()

                    // Temas (bloqueados mostram 🔒 e abrem a compra) --------------
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(ThemeKey.allCases) { key in
                            let unlocked = store.isThemeUnlocked(key)
                            Button {
                                if unlocked { theme = key } else { store.showPaywall = true }
                            } label: {
                                Text(key.label)
                                    .font(.system(size: 40))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .background(theme == key ? Color(red: 1.0, green: 0.824, blue: 0.247)
                                                             : Color(white: 0.95))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color(red: 1.0, green: 0.541, blue: 0.239),
                                                lineWidth: theme == key ? 4 : 0))
                                    .overlay(alignment: .topTrailing) {
                                        if !unlocked { Text("🔒").font(.system(size: 15)).padding(5) }
                                    }
                                    .opacity(unlocked ? 1 : 0.5)
                            }
                            .accessibilityLabel(key.rawValue)
                        }
                    }
                }
                .padding(22)
            }
            .frame(maxWidth: 440)
            .frame(maxHeight: min(580, g.size.height - 32))
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: .black.opacity(0.3), radius: 25, y: 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showScores { scoresPanel }
        }
        }
    }

    // MARK: Premium

    @ViewBuilder private var premiumSection: some View {
        if store.isPremium {
            HStack(spacing: 8) {
                Text("✨").font(.system(size: 22))
                Text("Tudo desbloqueado").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.80, blue: 0.47))
            }
        } else {
            VStack(spacing: 8) {
                Button { store.showPaywall = true } label: {
                    HStack(spacing: 8) {
                        Text("🔓").font(.system(size: 20))
                        Text("Desbloquear tudo — \(store.priceText)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(red: 1.0, green: 0.541, blue: 0.239),
                                in: RoundedRectangle(cornerRadius: 16))
                }
                Button { Task { await store.restore() } } label: {
                    Text("Restaurar compra")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Placar

    private var scoresPanel: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { showScores = false }
            VStack(spacing: 16) {
                Text("📊 Placar").font(.system(size: 24, weight: .heavy, design: .rounded))
                scoreRow("🎮", "Partidas jogadas", "\(statGames)")
                scoreRow("🔄", "Barras resetadas", "\(statResets)")
                scoreRow("🎯", "Assertividade", "\(assertividade)%")
                Text("partidas concluídas sem resetar a barra")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    statGames = 0; statResets = 0; statClean = 0
                } label: {
                    Text("Zerar contadores")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10).padding(.horizontal, 22)
                        .background(Color(red: 0.90, green: 0.33, blue: 0.30), in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(26)
            .frame(maxWidth: 360)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 12)
            .padding(24)
        }
    }

    private func scoreRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack {
            Text(icon).font(.system(size: 22))
            Text(label).font(.system(size: 16, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.78))
        }
    }
}

/// Toggle com trilho CINZA quando desligado e VERDE quando ligado (visível no fundo branco).
struct GrayGreenToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? Color(red: 0.42, green: 0.80, blue: 0.47)
                                         : Color(white: 0.72))
                .frame(width: 52, height: 31)
                .overlay(
                    Circle().fill(.white).padding(3)
                        .offset(x: configuration.isOn ? 10.5 : -10.5)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1))
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) { configuration.isOn.toggle() }
                }
        }
    }
}
