import AppKit
import SwiftUI

/// A regular window, not the popover: a transient popover closes on the first click outside it.
@MainActor
final class BattleWindowController: NSObject, NSWindowDelegate {
    static let shared = BattleWindowController()
    private var window: NSWindow?
    private var session: BattleSession?

    func present(_ session: BattleSession, title: String) {
        window?.close()
        self.session = session
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: BattleScreen.width, height: BattleScreen.height),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: BattleScreen(session: session) { [weak window] in window?.close() })
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Task { await session.start() }
    }

    func windowWillClose(_ notification: Notification) {
        session?.abandon()
        session = nil
        window = nil
    }
}

@MainActor
struct BattleScreen: View {
    static let width: CGFloat = 520
    static let height: CGFloat = 540

    let session: BattleSession
    let onClose: () -> Void
    @State private var showingSwitch = false
    @State private var confirmingForfeit = false

    private var l: L { session.l }

    var body: some View {
        VStack(spacing: 0) {
            arena
            messageBox
            controls
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: session.isPlaying) { _, playing in
            if playing { showingSwitch = false; confirmingForfeit = false }
        }
    }

    // MARK: Arena

    private var arena: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.62, green: 0.82, blue: 0.96), Color(red: 0.78, green: 0.91, blue: 0.72)],
                           startPoint: .top, endPoint: .bottom)
            VStack {
                HStack(alignment: .top) {
                    infoCard(.b)
                    Spacer()
                    combatantSprite(.b, size: 116)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    combatantSprite(.a, size: 132)
                    Spacer()
                    infoCard(.a)
                }
            }
            .padding(16)
        }
        .frame(height: 300)
    }

    private func combatantSprite(_ side: BattleSide, size: CGFloat) -> some View {
        let index = session.display.active[side.rawValue]
        let pokemon = session.state[side].team[index].pokemon
        let isOut = session.display.isOut[side.rawValue]
        return ZStack(alignment: .bottom) {
            Ellipse().fill(Color.black.opacity(0.12)).frame(width: size * 0.9, height: size * 0.22)
            SpriteView(speciesID: pokemon.speciesID, size: size, animated: true, shiny: pokemon.isShiny,
                       unownForm: pokemon.unownForm)
                .scaleEffect(x: side == session.mySide ? -1 : 1, y: 1)
                .id("\(side)-\(index)")
                .opacity(isOut ? 1 : 0)
                .offset(y: isOut ? 0 : size * 0.4)
                .animation(.easeInOut(duration: 0.45), value: isOut)
        }
        .frame(width: size * 1.1, height: size)
    }

    private func infoCard(_ side: BattleSide) -> some View {
        let index = session.display.active[side.rawValue]
        let pokemon = session.state[side].team[index].pokemon
        let hp = session.display.hp[side.rawValue][index]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(session.name(side, index)).font(.callout.weight(.semibold)).lineLimit(1)
                if pokemon.isShiny { Text("✨").font(.caption2).accessibilityLabel(l.dexShinyLabel) }
                Spacer(minLength: 6)
                Text(l.battleLevel(pokemon.level)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HPBar(hp: hp, maxHP: pokemon.stats.hp)
            if side == session.mySide {
                Text("\(hp) / \(pokemon.stats.hp)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            teamPips(side)
        }
        .padding(10)
        .frame(width: 210)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// One dot per team member so both players see how many Pokémon are left.
    private func teamPips(_ side: BattleSide) -> some View {
        HStack(spacing: 3) {
            ForEach(session.state[side].team.indices, id: \.self) { index in
                Circle()
                    .fill(session.display.hp[side.rawValue][index] > 0 ? Color.red.opacity(0.8) : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var messageBox: some View {
        Text(session.message)
            .font(.callout)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color.secondary.opacity(0.1))
            .animation(nil, value: session.message)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if let outcome = session.outcome {
            VStack(spacing: 14) {
                Text(outcome == .won ? l.battleWon : outcome == .lost ? l.battleLost : l.battleDraw)
                    .font(.title2.weight(.bold))
                HStack {
                    Button(l.battleRematch) { Task { await session.rematch() } }
                        .buttonStyle(.borderedProminent)
                    Button(l.battleClose, action: onClose)
                }
            }
        } else if session.awaitingReplacement {
            teamPicker(allowBack: false) { index in Task { await session.replace(with: index) } }
        } else if showingSwitch {
            teamPicker(allowBack: true) { index in
                showingSwitch = false
                Task { await session.choose(.switchTo(index)) }
            }
        } else {
            moveControls
        }
    }

    private var moveControls: some View {
        let current = session.state[session.mySide].current
        let usable = session.usableMoves
        return VStack(spacing: 8) {
            if usable.isEmpty {
                Button { Task { await session.choose(.struggle) } } label: {
                    MoveLabel(name: session.moveName(BattleMove.struggle.name), typeName: session.typeName(BattleMove.struggle.type),
                              move: .struggle, pp: nil)
                }
                .buttonStyle(.plain)
                .disabled(!session.canChoose)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(current.pokemon.moves.indices, id: \.self) { index in
                    let move = current.pokemon.moves[index]
                    Button { Task { await session.choose(.move(index)) } } label: {
                        MoveLabel(name: session.moveName(move.name), typeName: session.typeName(move.type),
                                  move: move, pp: (current.pp[index], move.pp))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canChoose || !usable.contains(index))
                    .opacity(move.isSupportedInBattle ? 1 : 0.45)
                    .help(move.isSupportedInBattle ? "" : l.battleUnsupportedMove)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button(l.battleSwitch) { showingSwitch = true }
                    .disabled(!session.canChoose || session.switchTargets.isEmpty)
                Spacer()
                if confirmingForfeit {
                    Text(l.battleForfeitConfirm).font(.caption).foregroundStyle(.secondary)
                    Button(l.battleForfeit, role: .destructive) { Task { await session.forfeit() } }
                    Button(l.cancel) { confirmingForfeit = false }
                } else {
                    Button(l.battleForfeit) { confirmingForfeit = true }
                        .disabled(session.isPlaying)
                }
            }
            .controlSize(.small)
        }
    }

    private func teamPicker(allowBack: Bool, pick: @escaping (Int) -> Void) -> some View {
        let side = session.state[session.mySide]
        let targets = Set(session.switchTargets)
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(side.team.indices, id: \.self) { index in
                    let member = side.team[index]
                    Button { pick(index) } label: {
                        HStack(spacing: 6) {
                            SpriteView(speciesID: member.pokemon.speciesID, size: 34, shiny: member.pokemon.isShiny,
                                       unownForm: member.pokemon.unownForm)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name(session.mySide, index)).font(.caption.weight(.semibold)).lineLimit(1)
                                HPBar(hp: member.hp, maxHP: member.pokemon.stats.hp).frame(height: 5)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(index == side.active ? 0.18 : 0.08),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!targets.contains(index))
                    .opacity(targets.contains(index) ? 1 : 0.45)
                }
            }
            if allowBack {
                Button(l.battleBack) { showingSwitch = false }.controlSize(.small)
            }
        }
    }
}

@MainActor
private struct MoveLabel: View {
    let name: String
    let typeName: String
    let move: BattleMove
    let pp: (Int, Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.callout.weight(.semibold)).lineLimit(1).foregroundStyle(.white)
            HStack {
                Text(typeName.uppercased())
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                Spacer()
                if let pp {
                    Text("PP \(pp.0)/\(pp.1)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BattleTypeColor.color(move.type), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

@MainActor
private struct HPBar: View {
    let hp: Int
    let maxHP: Int

    var body: some View {
        let fraction = maxHP > 0 ? Double(hp) / Double(maxHP) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(fraction > 0.5 ? Color.green : fraction > 0.2 ? Color.yellow : Color.red)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 7)
        .animation(.easeInOut(duration: 0.5), value: hp)
        .accessibilityElement()
        .accessibilityValue("\(hp) / \(maxHP)")
    }
}

enum BattleTypeColor {
    private static let colors: [String: (Double, Double, Double)] = [
        "normal": (0.62, 0.60, 0.47), "fire": (0.93, 0.50, 0.19), "water": (0.39, 0.56, 0.94),
        "electric": (0.87, 0.72, 0.10), "grass": (0.40, 0.70, 0.27), "ice": (0.40, 0.75, 0.75),
        "fighting": (0.75, 0.19, 0.16), "poison": (0.64, 0.24, 0.63), "ground": (0.80, 0.66, 0.36),
        "flying": (0.60, 0.51, 0.90), "psychic": (0.93, 0.33, 0.49), "bug": (0.60, 0.66, 0.12),
        "rock": (0.71, 0.62, 0.23), "ghost": (0.45, 0.34, 0.59), "dragon": (0.44, 0.21, 0.99),
        "dark": (0.44, 0.34, 0.27), "steel": (0.56, 0.56, 0.68), "fairy": (0.84, 0.52, 0.68),
    ]

    static func color(_ type: String) -> Color {
        guard let (r, g, b) = colors[type] else { return Color(white: 0.45) }
        return Color(red: r, green: g, blue: b)
    }
}
