import AppKit
import SwiftUI

/// The LAN battle window: pick a team → find an opponent on the network → fight.
/// A window rather than a popover screen because a battle outlives any single popover opening.
@MainActor
final class BattleWindowController: NSObject, NSWindowDelegate {
    private let store: CompanionStore
    private let session = BattleSession()
    private var window: NSWindow?

    init(store: CompanionStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = store.l.battleTitle
            window.contentViewController = NSHostingController(rootView: BattleView(
                store: store, session: session,
                playerName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName))
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closing the window leaves the lobby or the battle; the opponent sees a disconnect.
    func windowWillClose(_ notification: Notification) {
        session.stop()
        window = nil
    }
}

@MainActor
struct BattleView: View {
    static let teamSize = 3

    let store: CompanionStore
    let session: BattleSession
    let playerName: String
    /// `DexEntry.id`s in battle order; the first one leads.
    @State private var picked: [String] = []
    @State private var preparing = false
    @State private var downloadFailed = false
    @State private var confirmingForfeit = false
    @State private var address = ""
    @State private var draft = ""
    @State private var hoveredMove: Int?
    @State private var showingTypes = false

    private var l: L { store.l }
    private var roster: [DexEntry] {
        store.dexEntriesSorted.filter { $0.profile != nil && !$0.isReleased }
    }

    var body: some View {
        Group {
            switch session.phase {
            case .idle: teamPicker
            case .lobby, .challenging, .incoming: lobby
            case .battle: battle
            }
        }
        .padding(14)
        .frame(width: 400, height: 700)
    }

    // MARK: Team

    private var teamPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(roster.isEmpty ? l.battleNoPokemon : l.battlePickTeam)
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(roster) { entry in
                        rosterCell(entry)
                    }
                }
                .reservesScrollerLane()
            }
            if preparing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battlePreparing).font(.callout).foregroundStyle(.secondary)
                }
            } else if downloadFailed {
                Text(l.battleDownloadFailed).font(.callout).foregroundStyle(.orange)
            }
            Button {
                enterLobby()
            } label: {
                Text(l.battleFindOpponents).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(picked.isEmpty || preparing)
        }
    }

    private func rosterCell(_ entry: DexEntry) -> some View {
        let order = picked.firstIndex(of: entry.id)
        return Button {
            if let order {
                picked.remove(at: order)
            } else if picked.count < Self.teamSize {
                picked.append(entry.id)
            }
        } label: {
            VStack(spacing: 2) {
                SpriteView(speciesID: entry.finalID, size: 56, shiny: entry.isShiny, form: entry.form)
                Text(store.dexEntryName(entry)).font(.caption).lineLimit(1)
                Text("Lv. \(entry.profile?.level ?? 5)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(order == nil ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.2)))
            .overlay(alignment: .topTrailing) {
                if let order {
                    Text("\(order + 1)").font(.caption2.bold()).foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.accentColor))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Profiles are enriched lazily (ability, moves) the first time a species' details load, so make
    /// sure every picked Pokémon has them before its data is frozen into the team. The simulator is
    /// fetched here too (first battle only): whoever gets challenged must be able to host at once.
    private func enterLobby() {
        preparing = true
        downloadFailed = false
        Task {
            do {
                try await BattleEnginePackages.install(into: BattleEnginePackages.defaultDirectory)
            } catch {
                AppLog.write("battle engine download failed: \(error)")
                preparing = false
                downloadFailed = true
                return
            }
            for entry in roster where picked.contains(entry.id) && entry.profile?.moves.isEmpty != false {
                await store.loadPokemonDetails(speciesID: entry.finalID)
            }
            let fresh = roster
            let team = picked.compactMap { id in fresh.first { $0.id == id } }
                .map { BattleTeamMember(entry: $0, name: store.dexEntryName($0)) }
            preparing = false
            guard !team.isEmpty else { return }
            session.enterLobby(as: BattlePlayer(name: playerName, team: team, lang: l.lang.rawValue))
        }
    }

    // MARK: Lobby

    private var lobby: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = session.notice {
                Text(text(for: notice)).font(.callout).foregroundStyle(.orange)
            }
            switch session.phase {
            case let .incoming(name):
                VStack(alignment: .leading, spacing: 8) {
                    Text(l.battleIncoming(name)).font(.headline)
                    HStack {
                        Button(l.battleAccept) { session.accept() }.buttonStyle(.borderedProminent)
                        Button(l.battleDecline) { session.decline() }
                    }
                }
            case let .challenging(name):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleChallenging(name))
                    Spacer()
                    Button(l.cancel) { session.cancelChallenge() }
                }
            default:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleSearching).foregroundStyle(.secondary)
                }
                if session.peers.isEmpty {
                    Text(l.battleSearchingHint).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(session.peers) { peer in
                    HStack {
                        Text(peer.name).lineLimit(1)
                        Spacer()
                        Button(l.battleChallenge) { session.challenge(peer) }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                }
                Divider()
                Text(l.battleAddressHint).font(.caption).foregroundStyle(.secondary)
                if !session.addresses.isEmpty {
                    Text(l.battleYourAddress(session.addresses.joined(separator: ", ")))
                        .font(.caption).textSelection(.enabled)
                }
                if !BattleSession.vpnHosts().isEmpty {
                    HStack(spacing: 8) {
                        Button(l.battleScanVPN) { session.scanVPN() }.disabled(session.scanning)
                        if session.scanning { ProgressView().controlSize(.small) }
                    }
                }
                HStack {
                    TextField(l.battleAddressPlaceholder, text: $address)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { session.challenge(address: address) }
                    Button(l.battleConnect) { session.challenge(address: address) }
                        .disabled(address.isEmpty)
                }
            }
            Spacer()
            Button(l.battleChangeTeam) { session.stop() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(for notice: BattleSession.Notice) -> String {
        switch notice {
        case .declined: return l.battleNoticeDeclined
        case .disconnected: return l.battleNoticeDisconnected
        case .engineFailed: return l.battleNoticeEngineFailed
        case .networkFailed: return l.battleNoticeNetworkFailed
        }
    }

    // MARK: Battle

    @ViewBuilder
    private var battle: some View {
        if let snapshot = session.snapshot {
            VStack(spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            showingTypes.toggle()
                        } label: {
                            Label(l.battleTypes, systemImage: "shield.lefthalf.filled").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showingTypes, arrowEdge: .bottom) { typeChart(snapshot) }
                        if let foe = snapshot.foe.active { status(foe, owner: snapshot.foe.name, exact: false) }
                    }
                    Spacer()
                    sprite(snapshot.foe.active, back: false)
                }
                HStack(alignment: .bottom) {
                    sprite(snapshot.me.active, back: true)
                    Spacer()
                    if let mine = snapshot.me.active { status(mine, owner: snapshot.me.name, exact: true) }
                }
                battleLog
                TextField(l.battleChatPlaceholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        session.say(draft)
                        draft = ""
                    }
                controls(snapshot)
            }
        }
    }

    private func sprite(_ mon: BattleSnapshot.Mon?, back: Bool) -> some View {
        SpriteView(speciesID: mon?.dex, size: 96, animated: true, shiny: mon?.shiny ?? false,
                   form: mon?.form, back: back)
            .opacity(mon?.fainted == false ? 1 : 0.3)
            .frame(width: 110, height: 100)
            // A new species must not keep the previous one's pixels while its sprite loads.
            .id("\(mon?.dex ?? 0)-\(mon?.sprite ?? "")-\(back)")
    }

    private func status(_ mon: BattleSnapshot.Mon, owner: String, exact: Bool) -> some View {
        let fraction = Double(mon.hp) / Double(max(1, mon.maxhp))
        return VStack(alignment: .leading, spacing: 3) {
            Text(owner).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                Text(mon.name).font(.headline).lineLimit(1)
                Text("Lv. \(mon.level)").font(.caption).foregroundStyle(.secondary)
                if mon.fainted || !mon.status.isEmpty {
                    Text(mon.fainted ? "FNT" : mon.status.uppercased())
                        .font(.caption2.bold()).padding(.horizontal, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.25)))
                }
            }
            ProgressView(value: fraction)
                .tint(fraction > 0.5 ? .green : fraction > 0.2 ? .yellow : .red)
            Text(exact ? "\(mon.hp) / \(mon.maxhp)" : "\(mon.hp)%")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(width: 210, alignment: .leading)
    }

    private var battleLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(session.log.enumerated()), id: \.offset) { _, line in
                        Group {
                            if let author = line.author {
                                Text("\(author): ").bold().foregroundStyle(Color.accentColor) + Text(line.text)
                            } else {
                                Text(line.text).fontWeight(line.text.hasPrefix("==") ? .bold : .regular)
                            }
                        }
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(8)
                .reservesScrollerLane()
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            .onChange(of: session.log.count, initial: true) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func controls(_ snapshot: BattleSnapshot) -> some View {
        if snapshot.ended {
            Text(snapshot.winner == "me" ? l.battleWon : snapshot.winner == "foe" ? l.battleLost : l.battleTie)
                .font(.title2.bold())
            Button(l.battleBackToLobby) { session.leaveBattle() }.buttonStyle(.borderedProminent)
        } else {
            if let rejection = session.rejection {
                Text(rejection).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            switch snapshot.request.kind {
            case "move":
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(snapshot.request.moves ?? []) { move in
                        Button {
                            session.choose("move \(move.slot)")
                        } label: {
                            VStack(spacing: 1) {
                                Text(move.name).lineLimit(1)
                                Text("\(l.battleType(move.type)) · \(move.pp)/\(move.maxpp)"
                                     + (move.effect.map { $0 == 1 ? "" : " · \(Self.times($0))" } ?? ""))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(move.disabled)
                        .onHover { inside in
                            if inside { hoveredMove = move.slot } else if hoveredMove == move.slot { hoveredMove = nil }
                        }
                    }
                }
                moveDetails(snapshot.request.moves?.first { $0.slot == hoveredMove })
                switches(snapshot)
            case "switch":
                Text(l.battleChooseNext).font(.callout)
                switches(snapshot)
            default:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l.battleWaiting).foregroundStyle(.secondary)
                }
                .frame(height: 44)
            }
            Button(l.battleForfeit, role: .destructive) { confirmingForfeit = true }
                .buttonStyle(.borderless).font(.caption)
                .confirmationDialog(l.battleForfeitConfirm, isPresented: $confirmingForfeit) {
                    Button(l.battleForfeit, role: .destructive) { session.forfeit() }
                    Button(l.cancel, role: .cancel) {}
                }
        }
    }

    /// The hovered move's numbers and effect. The height is reserved so the buttons never jump.
    private func moveDetails(_ move: BattleSnapshot.Move?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let move {
                Text(Self.facts(move, l)).font(.caption2.bold())
                Text(move.desc ?? "").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .topLeading)
    }

    static func facts(_ move: BattleSnapshot.Move, _ l: L) -> String {
        var facts = [l.battleType(move.type)]
        if let category = move.category { facts.append(l.battleCategory(category)) }
        if let power = move.power, power > 0 { facts.append("\(l.battlePower) \(power)") }
        if let accuracy = move.accuracy, accuracy > 0 { facts.append("\(l.battleAccuracy) \(accuracy)%") }
        if let priority = move.priority, priority != 0 {
            facts.append("\(l.battlePriority) \(priority > 0 ? "+" : "")\(priority)")
        }
        return facts.joined(separator: " · ")
    }

    /// 4 → "×4", 0.5 → "×½".
    static func times(_ multiplier: Double) -> String {
        switch multiplier {
        case 0.5: return "×½"
        case 0.25: return "×¼"
        default: return "×" + String(format: "%g", multiplier)
        }
    }

    /// Both Pokémon on the field: what hits them for how much, and what their own types hit.
    func typeChart(_ snapshot: BattleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([snapshot.me.active, snapshot.foe.active].compactMap { $0 }) { mon in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(mon.name).font(.headline)
                        ForEach(mon.types ?? [], id: \.self) { typeIcon($0) }
                    }
                    matchups(l.battleTakesDamage, mon.defense ?? [:])
                    ForEach((mon.types ?? []).filter { mon.offense?[$0]?.isEmpty == false }, id: \.self) { type in
                        matchups(l.battleDealsDamage(l.battleType(type)), mon.offense?[type] ?? [:], attack: type)
                    }
                }
            }
            Text(l.battleTypesNote).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
    }

    private func matchups(_ title: String, _ multipliers: [String: Double], attack: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let attack { typeIcon(attack) }
                Text(title).font(.caption.bold())
            }
            ForEach(Set(multipliers.values).sorted(by: >), id: \.self) { multiplier in
                HStack(spacing: 3) {
                    Text(Self.times(multiplier)).font(.caption.monospacedDigit().bold())
                        .foregroundStyle(multiplier > 1 ? .primary : .secondary)
                        .frame(width: 24, alignment: .leading)
                    ForEach(multipliers.filter { $0.value == multiplier }.keys.sorted(), id: \.self) { typeIcon($0) }
                }
            }
        }
    }

    /// SF Symbols in the conventional type colours (no game artwork); the name shows on hover.
    private func typeIcon(_ type: String) -> some View {
        let style = Self.typeStyles[type] ?? ("questionmark", 0x888888)
        return Image(systemName: style.symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color(red: Double(style.color >> 16 & 0xFF) / 255,
                                            green: Double(style.color >> 8 & 0xFF) / 255,
                                            blue: Double(style.color & 0xFF) / 255)))
            .help(l.battleType(type))
            .accessibilityLabel(l.battleType(type))
    }

    static let typeStyles: [String: (symbol: String, color: Int)] = [
        "Normal": ("circle.fill", 0xA8A77A), "Fire": ("flame.fill", 0xEE8130), "Water": ("drop.fill", 0x6390F0),
        "Electric": ("bolt.fill", 0xF7D02C), "Grass": ("leaf.fill", 0x7AC74C), "Ice": ("snowflake", 0x96D9D6),
        "Fighting": ("figure.boxing", 0xC22E28), "Poison": ("cross.vial.fill", 0xA33EA1),
        "Ground": ("mountain.2.fill", 0xE2BF65), "Flying": ("bird.fill", 0xA98FF3), "Psychic": ("eye.fill", 0xF95587),
        "Bug": ("ladybug.fill", 0xA6B91A), "Rock": ("hexagon.fill", 0xB6A136), "Ghost": ("eyes.inverse", 0x735797),
        "Dragon": ("lizard.fill", 0x6F35FC), "Dark": ("moon.fill", 0x705746), "Steel": ("gearshape.fill", 0xB7B7CE),
    ]

    @ViewBuilder
    private func switches(_ snapshot: BattleSnapshot) -> some View {
        let slots = snapshot.request.switches ?? []
        if !slots.isEmpty {
            HStack(spacing: 6) {
                Text(l.battleSwitch).font(.caption).foregroundStyle(.secondary)
                ForEach(slots, id: \.self) { slot in
                    if snapshot.me.team.indices.contains(slot - 1) {
                        let mon = snapshot.me.team[slot - 1]
                        Button {
                            session.choose("switch \(slot)")
                        } label: {
                            Text("\(mon.name) \(mon.hp)/\(mon.maxhp)").font(.caption).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
