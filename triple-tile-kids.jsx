import { useState, useEffect, useCallback } from "react";

// ── Engine fiel ao Triple Tile ──
// Pilha densa irregular, barra de 7, trio de 3.
// SOLUBILIDADE GARANTIDA: ícones atribuídos em trios na ordem de liberação das camadas,
// então sempre existe um caminho para terminar. Tiles de baixo bloqueados ao clique.
// Tamanho da pilha ajustável no menu (a criança escolhe a dificuldade).

const THEMES = {
  animais: { label: "🐶", icons: ["🐶", "🐱", "🐰", "🐸", "🦁", "🐠", "🐝", "🐢", "🐼", "🦊", "🐧", "🐮", "🐷", "🐔"] },
  frutas: { label: "🍎", icons: ["🍎", "🍌", "🍓", "🍇", "🍊", "🍉", "🍐", "🥝", "🍒", "🥥", "🍑", "🍍", "🥭", "🫐"] },
  alfabeto: { label: "🔤", icons: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N"] },
  numeros: { label: "🔢", icons: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "+", "-", "=", "x"] },
  casa: { label: "🏠", icons: ["🛏️", "🪑", "🛋️", "🚪", "🪟", "🚽", "🛁", "🧴", "🕯️", "🧹", "🔑", "🪣", "🧺", "🛒"] },
  cotidiano: { label: "🎒", icons: ["⚽", "🎒", "✏️", "📚", "🧸", "🚗", "👟", "☂️", "🎈", "🎁", "🎨", "🪁", "🎸", "⏰"] },
};

const THEME_COLORS = [
  "#FF8A3D", "#FFD23F", "#FF5DA2", "#6BCB77", "#FFB627", "#4D96FF", "#9D4EDD",
  "#52B788", "#FF6B6B", "#3DB8C9", "#F38181", "#A06CD5", "#3CAEA3", "#ED553B",
];

const BAR_SIZE = 7;
const TRIO = 3;
const TILE = 64;

// Tamanhos ajustáveis: cada um define quantos TIPOS de ícone (×3 = total de tiles)
// e o formato da pilha (linhas).
const SIZES = {
  pequeno: { label: "🐣", types: 5, rows: [3, 4, 4, 3], topRows: [2, 2] },
  medio: { label: "🐥", types: 8, rows: [3, 5, 5, 5, 3], topRows: [3, 2] },
  grande: { label: "🐓", types: 12, rows: [3, 5, 6, 6, 5, 4, 3], topRows: [3, 3, 2] },
};

function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// Constrói slots da pilha (posições + camada), depois atribui ícones de forma SOLÚVEL.
function buildBoard(themeKey, sizeKey) {
  const size = SIZES[sizeKey];
  const icons = THEMES[themeKey].icons.slice(0, size.types);

  // 1) gerar slots posicionais
  const rowGap = TILE * 0.62;
  const colGap = TILE * 0.78;
  const slots = [];
  size.rows.forEach((count, r) => {
    const rowWidth = (count - 1) * colGap;
    for (let c = 0; c < count; c++) {
      slots.push({
        x: c * colGap - rowWidth / 2 + (Math.random() - 0.5) * 14,
        y: r * rowGap + (Math.random() - 0.5) * 10,
        layer: 0,
      });
    }
  });
  size.topRows.forEach((count, r) => {
    const rowWidth = (count - 1) * colGap;
    for (let c = 0; c < count; c++) {
      slots.push({
        x: c * colGap - rowWidth / 2 + (Math.random() - 0.5) * 12,
        y: (r + 1.4) * rowGap + (Math.random() - 0.5) * 8,
        layer: 1,
      });
    }
  });

  // 2) total de tiles = múltiplo de 3 (cada tipo entra 3×). Ajusta se slots não casam.
  const totalTiles = size.types * TRIO;
  let chosen = shuffle(slots);
  if (chosen.length >= totalTiles) {
    chosen = chosen.slice(0, totalTiles);
  } else {
    // faltam slots → adiciona dispersão extra na camada 0
    while (chosen.length < totalTiles) {
      chosen.push({
        x: (Math.random() - 0.5) * colGap * 4,
        y: Math.random() * rowGap * (size.rows.length),
        layer: 0,
      });
    }
  }

  // 3) ORDEM DE LIBERAÇÃO: um slot é "liberado" antes de outro se nada o cobre.
  // Calculamos quem cobre quem; ordenamos por (camada desc, depois y) — topo sai primeiro.
  // Atribuímos ícones em trios SEGUINDO a ordem de liberação, garantindo que cada
  // trio fique acessível em sequência → jogo sempre solúvel.
  const ordered = [...chosen]
    .map((s, idx) => ({ ...s, idx }))
    .sort((a, b) => {
      if (b.layer !== a.layer) return b.layer - a.layer; // camada de cima primeiro
      return a.y - b.y; // dentro da camada, de cima pra baixo
    });

  // monta a fila de ícones: tipo0,tipo0,tipo0, tipo1,tipo1,tipo1, ...
  const iconQueue = [];
  icons.forEach((icon, idx) => {
    for (let k = 0; k < TRIO; k++) iconQueue.push({ icon, colorIdx: idx });
  });

  // atribui na ordem de liberação
  const tiles = ordered.map((slot, i) => ({
    id: `tile-${i}`,
    icon: iconQueue[i].icon,
    colorIdx: iconQueue[i].colorIdx,
    x: slot.x,
    y: slot.y,
    layer: slot.layer,
    cleared: false,
    inBar: false,
  }));

  return tiles;
}

function isBlocked(tile, tiles) {
  if (tile.cleared || tile.inBar) return false;
  return tiles.some((o) => {
    if (o.cleared || o.inBar || o.id === tile.id) return false;
    if (o.layer <= tile.layer) return false;
    return Math.abs(o.x - tile.x) < TILE * 0.6 && Math.abs(o.y - tile.y) < TILE * 0.6;
  });
}

function useSound() {
  return useCallback((type) => {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      if (type === "match") {
        [523, 784, 1047].forEach((f, i) => osc.frequency.setValueAtTime(f, ctx.currentTime + i * 0.09));
      } else if (type === "win") {
        [523, 659, 784, 1047, 1319].forEach((f, i) => osc.frequency.setValueAtTime(f, ctx.currentTime + i * 0.11));
      } else {
        osc.frequency.setValueAtTime(440, ctx.currentTime);
      }
      gain.gain.setValueAtTime(0.16, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.5);
      osc.start();
      osc.stop(ctx.currentTime + (type === "win" ? 0.7 : 0.4));
    } catch (e) {}
  }, []);
}

export default function App() {
  const [theme, setTheme] = useState("animais");
  const [size, setSize] = useState("medio");
  const [showSettings, setShowSettings] = useState(false);
  const [tiles, setTiles] = useState(() => buildBoard("animais", "medio"));
  const [bar, setBar] = useState([]);
  const [won, setWon] = useState(false);
  const play = useSound();

  const remaining = tiles.filter((t) => !t.cleared).length;

  useEffect(() => {
    if (remaining === 0 && tiles.length > 0 && !won) {
      setWon(true);
      play("win");
    }
  }, [remaining, tiles.length, won, play]);

  function reset(tk, sk) {
    setTiles(buildBoard(tk || theme, sk || size));
    setBar([]);
    setWon(false);
  }

  function selectTheme(tk) {
    setTheme(tk);
    reset(tk, size);
  }
  function selectSize(sk) {
    setSize(sk);
    reset(theme, sk);
  }

  const organize = (arr) => [...arr].sort((a, b) => a.icon.localeCompare(b.icon));

  function tapTile(tile, blocked) {
    if (blocked || tile.cleared || tile.inBar || won) return;
    let newBar = organize([...bar, tile]);
    setTiles((prev) => prev.map((t) => (t.id === tile.id ? { ...t, inBar: true } : t)));

    const counts = {};
    newBar.forEach((t) => (counts[t.icon] = (counts[t.icon] || 0) + 1));
    const trioIcon = Object.keys(counts).find((k) => counts[k] >= TRIO);

    if (trioIcon) {
      play("match");
      const toClear = newBar.filter((t) => t.icon === trioIcon).slice(0, TRIO);
      const clearIds = new Set(toClear.map((t) => t.id));
      newBar = newBar.filter((t) => !clearIds.has(t.id));
      setTimeout(() => {
        setTiles((prev) => prev.map((t) => (clearIds.has(t.id) ? { ...t, cleared: true, inBar: false } : t)));
      }, 200);
    } else {
      play("tap");
      if (newBar.length > BAR_SIZE) {
        const oldest = newBar[0];
        newBar = newBar.slice(1);
        setTiles((prev) => prev.map((t) => (t.id === oldest.id ? { ...t, inBar: false } : t)));
      }
    }
    setBar(newBar);
  }

  const live = tiles.filter((t) => !t.cleared && !t.inBar);
  const xs = live.map((t) => t.x);
  const ys = live.map((t) => t.y);
  const minX = xs.length ? Math.min(...xs) : 0;
  const maxX = xs.length ? Math.max(...xs) : 0;
  const minY = ys.length ? Math.min(...ys) : 0;
  const maxY = ys.length ? Math.max(...ys) : 0;
  const boardW = maxX - minX + TILE;
  const boardH = maxY - minY + TILE;

  return (
    <div style={{
      minHeight: "100vh",
      background: "radial-gradient(circle at 50% 12%, #FFF6E5 0%, #FFD89B 100%)",
      display: "flex", flexDirection: "column", alignItems: "center",
      fontFamily: "system-ui, sans-serif", padding: 12,
      userSelect: "none", WebkitTapHighlightColor: "transparent",
    }}>
      <div style={{ width: "100%", maxWidth: 440, display: "flex", justifyContent: "flex-end" }}>
        <button onClick={() => setShowSettings((s) => !s)} aria-label="configuracoes"
          style={{ fontSize: 34, border: "none", background: "transparent", cursor: "pointer", touchAction: "manipulation" }}>
          ⚙️
        </button>
      </div>

      <div style={{
        display: "grid", gridTemplateColumns: `repeat(${BAR_SIZE}, 1fr)`, gap: 6,
        maxWidth: 440, width: "100%", background: "rgba(255,255,255,0.6)",
        borderRadius: 20, padding: 8, marginBottom: 16,
        boxShadow: "inset 0 2px 8px rgba(0,0,0,0.14)",
      }}>
        {Array.from({ length: BAR_SIZE }).map((_, i) => {
          const t = bar[i];
          return (
            <div key={i} style={{
              aspectRatio: "1", borderRadius: 12,
              background: t ? THEME_COLORS[t.colorIdx] : "rgba(0,0,0,0.06)",
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: "clamp(20px, 6vw, 32px)", fontWeight: 700, color: "#333",
              transition: "background 0.2s, transform 0.2s", transform: t ? "scale(1)" : "scale(0.92)",
            }}>
              {t ? t.icon : ""}
            </div>
          );
        })}
      </div>

      {!won ? (
        <div style={{ position: "relative", width: boardW, height: boardH, maxWidth: "100%", margin: "8px auto" }}>
          {tiles.map((t) => {
            if (t.cleared || t.inBar) return null;
            const blocked = isBlocked(t, tiles);
            return (
              <button key={t.id} onClick={() => tapTile(t, blocked)} aria-label={t.icon}
                style={{
                  position: "absolute",
                  left: t.x - minX, top: t.y - minY,
                  width: TILE, height: TILE,
                  border: "3px solid rgba(255,255,255,0.85)", borderRadius: 14,
                  background: THEME_COLORS[t.colorIdx],
                  filter: blocked ? "brightness(0.5) saturate(0.7)" : "none",
                  boxShadow: blocked ? "0 1px 3px rgba(0,0,0,0.3)" : "0 4px 10px rgba(0,0,0,0.35)",
                  fontSize: "clamp(26px, 8vw, 38px)", fontWeight: 700, color: "#2a2a2a",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  cursor: blocked ? "default" : "pointer",
                  zIndex: t.layer * 100 + Math.round(t.y),
                  touchAction: "manipulation", transition: "filter 0.2s, transform 0.12s",
                }}>
                {t.icon}
              </button>
            );
          })}
        </div>
      ) : (
        <div style={{ textAlign: "center", marginTop: 40 }}>
          <div style={{ fontSize: 110, animation: "bounce 0.6s infinite alternate" }}>🎉</div>
          <button onClick={() => reset()} aria-label="jogar de novo"
            style={{
              marginTop: 20, fontSize: 56, border: "none", borderRadius: 36,
              padding: "10px 36px", background: "#6BCB77",
              boxShadow: "0 7px 0 #4ca85a", cursor: "pointer", touchAction: "manipulation",
            }}>
            🔄
          </button>
        </div>
      )}

      {showSettings && (
        <div style={{
          position: "fixed", inset: 0, background: "rgba(0,0,0,0.45)",
          display: "flex", alignItems: "center", justifyContent: "center",
          zIndex: 100, padding: 20,
        }} onClick={() => setShowSettings(false)}>
          <div onClick={(e) => e.stopPropagation()} style={{
            background: "#fff", borderRadius: 28, padding: 24,
            maxWidth: 380, width: "100%", boxShadow: "0 20px 50px rgba(0,0,0,0.3)",
            display: "flex", flexDirection: "column", gap: 22,
          }}>
            {/* Tamanho da pilha */}
            <div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14 }}>
                {Object.entries(SIZES).map(([key, val]) => (
                  <button key={key} onClick={() => selectSize(key)} aria-label={key}
                    style={{
                      aspectRatio: "1.3", border: "none", borderRadius: 20,
                      background: size === key ? "#A06CD5" : "#F2F2F2",
                      boxShadow: size === key ? "0 0 0 4px #6BCB77" : "0 3px 8px rgba(0,0,0,0.12)",
                      fontSize: 40, cursor: "pointer", touchAction: "manipulation",
                    }}>
                    {val.label}
                  </button>
                ))}
              </div>
            </div>
            {/* Temas */}
            <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14 }}>
              {Object.entries(THEMES).map(([key, val]) => (
                <button key={key} onClick={() => selectTheme(key)} aria-label={key}
                  style={{
                    aspectRatio: "1", border: "none", borderRadius: 20,
                    background: theme === key ? "#FFD23F" : "#F2F2F2",
                    boxShadow: theme === key ? "0 0 0 4px #FF8A3D" : "0 3px 8px rgba(0,0,0,0.12)",
                    fontSize: 44, cursor: "pointer", touchAction: "manipulation",
                  }}>
                  {val.label}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      <style>{`
        @keyframes bounce { from { transform: translateY(0) } to { transform: translateY(-22px) } }
        @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }
        button:focus-visible { outline: 4px solid #4D96FF; outline-offset: 3px; }
      `}</style>
    </div>
  );
}
