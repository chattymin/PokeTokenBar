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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 620),
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
        .frame(width: 400, height: 620)
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
            session.enterLobby(as: BattlePlayer(name: playerName, team: team))
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
                    if let foe = snapshot.foe.active { status(foe, owner: snapshot.foe.name, exact: false) }
                    Spacer()
                    sprite(snapshot.foe.active, back: false)
                }
                HStack(alignment: .bottom) {
                    sprite(snapshot.me.active, back: true)
                    Spacer()
                    if let mine = snapshot.me.active { status(mine, owner: snapshot.me.name, exact: true) }
                }
                battleLog
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
                        Text(line)
                            .font(line.hasPrefix("==") ? .caption.bold() : .caption)
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
                                Text("\(move.type) · \(move.pp)/\(move.maxpp)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(move.disabled)
                    }
                }
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
