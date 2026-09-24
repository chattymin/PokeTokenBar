import SwiftUI

/// Battle tab — team builder. Picks up to six individuals and checks that each one resolves into
/// battle data, so problems surface here instead of at the start of a match.
@MainActor
struct BattleView: View {
    let store: CompanionStore
    var loader = BattleTeamLoader(details: PokeAPIClient.shared, moves: BattleMoveClient.shared)
    var opponents = BattleOpponentFactory(details: PokeAPIClient.shared, moves: BattleMoveClient.shared,
                                          speciesNames: { await PokeAPIClient.shared.speciesNames(id: $0) })

    enum Readiness: Equatable { case preparing, ready(BattleTeam), failed }
    @State private var readiness: Readiness?
    @State private var retryCount = 0
    @State private var startingPractice = false
    @State private var practiceFailed = false

    private static let thumb: CGFloat = 40
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        let l = store.l
        let candidates = store.battleCandidates
        if candidates.isEmpty {
            VStack(spacing: 10) {
                SpriteView(speciesID: nil, size: 72)
                Text(l.battleNoCandidates).font(.callout).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            // Fixed height, like Bag and Collection: the popover must not shrink when reopened.
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    teamSection(l)
                    Divider()
                    Text(l.battleYourPokemon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Self.columns, spacing: 6) {
                        ForEach(candidates) { entry in candidateCell(entry, l) }
                    }
                    Text(l.battleComingSoon)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(height: 520)
            .task(id: "\(store.battleTeamEntries.map(\.id))-\(retryCount)") { await checkReadiness() }
        }
    }

    private func teamSection(_ l: L) -> some View {
        let team = store.battleTeamEntries
        return VStack(alignment: .leading, spacing: 8) {
            Text(l.battleTeamCount(team.count)).font(.callout.weight(.semibold)).monospacedDigit()
            HStack(spacing: 6) {
                ForEach(0..<BattleTeam.maxSize, id: \.self) { slot in
                    if slot < team.count {
                        teamSlot(team[slot], isLead: slot == 0, l)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.thumb + 22)
                    }
                }
            }
            readinessLabel(l)
            Text(team.isEmpty ? l.battleTeamEmpty : store.isBattleTeamFull ? l.battleTeamFull : l.battlePickHint)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func teamSlot(_ entry: DexEntry, isLead: Bool, _ l: L) -> some View {
        Button { store.toggleBattleTeamMember(entry) } label: {
            VStack(spacing: 1) {
                SpriteView(speciesID: entry.finalID, size: Self.thumb, shiny: entry.isShiny, unownForm: entry.unownForm)
                Text(levelText(entry, l)).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.thumb + 22)
            .overlay(alignment: .top) {
                if isLead {
                    Text(l.battleLead.uppercased())
                        .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .padding(.top, 2)
                }
            }
            .background(Color.accentColor.opacity(isLead ? 0.16 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip(entry, l))
        .accessibilityLabel(tooltip(entry, l))
        .accessibilityHint(l.battleRemove)
        .contextMenu {
            if !isLead { Button(l.battleMakeLead) { store.makeBattleLead(entry) } }
            Button(l.battleRemove) { store.toggleBattleTeamMember(entry) }
        }
    }

    private func candidateCell(_ entry: DexEntry, _ l: L) -> some View {
        let slot = store.battleTeamSlot(entry)
        let disabled = slot == nil && store.isBattleTeamFull
        return Button { store.toggleBattleTeamMember(entry) } label: {
            VStack(spacing: 1) {
                SpriteView(speciesID: entry.finalID, size: Self.thumb, shiny: entry.isShiny, unownForm: entry.unownForm)
                Text(levelText(entry, l)).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(slot == nil ? Color.secondary.opacity(0.06) : Color.accentColor.opacity(0.12))
            .overlay(alignment: .topTrailing) {
                if let slot {
                    Text("\(slot + 1)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Color.accentColor, in: Circle())
                        .padding(2)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(slot == nil ? Color.clear : Color.accentColor, lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(tooltip(entry, l))
        .accessibilityLabel(tooltip(entry, l))
        .accessibilityHint(slot == nil ? l.battleAdd : l.battleRemove)
        .accessibilityAddTraits(slot == nil ? [] : .isSelected)
    }

    @ViewBuilder
    private func readinessLabel(_ l: L) -> some View {
        switch readiness {
        case .preparing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(l.battlePreparing).font(.caption2).foregroundStyle(.secondary)
            }
        case .ready(let team):
            HStack(spacing: 6) {
                Label(practiceFailed ? l.battleDataFailed : l.battleReady,
                      systemImage: practiceFailed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(practiceFailed ? .orange : .green)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if startingPractice {
                    ProgressView().controlSize(.mini)
                    Text(l.battleFindingOpponent).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Button(l.battlePractice) { Task { await startPractice(with: team) } }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        case .failed:
            HStack(spacing: 6) {
                Text(l.battleDataFailed).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(l.retry) { retryCount += 1 }.buttonStyle(.borderless).controlSize(.small)
            }
        case nil:
            EmptyView()
        }
    }

    private func levelText(_ entry: DexEntry, _ l: L) -> String {
        entry.profile.map { l.battleLevel($0.level) } ?? ""
    }

    private func tooltip(_ entry: DexEntry, _ l: L) -> String {
        let name = store.dexStoredChainNames(entry)?[entry.finalID] ?? "#\(entry.finalID)"
        var parts = [UnownForm.displayName(name, speciesID: entry.finalID, form: entry.unownForm), levelText(entry, l)]
        if let nature = entry.nature { parts.append(nature.name(store.language)) }
        if entry.isShiny { parts.append(l.dexShinyLabel) }
        return parts.joined(separator: " · ")
    }

    /// Loads species details first so deferred profiles get their moves, then resolves the snapshot.
    private func checkReadiness() async {
        let team = store.battleTeamEntries
        guard !team.isEmpty else { readiness = nil; return }
        readiness = .preparing
        for speciesID in Set(team.map(\.finalID)) { await store.loadPokemonDetails(speciesID: speciesID) }
        do {
            readiness = .ready(try await loader.load(store.battleTeamEntries))
            practiceFailed = false
        } catch {
            if Task.isCancelled { return }
            AppLog.write("battle team snapshot failed: \(error)")
            readiness = .failed
        }
    }

    private func startPractice(with team: BattleTeam) async {
        startingPractice = true
        practiceFailed = false
        defer { startingPractice = false }
        var seeds = BattleRNG(seed: UInt64.random(in: 1...UInt64.max))
        do {
            let opponent = try await opponents.team(matching: team, seed: seeds.next())
            await BattleNamePrefetch.load([team, opponent])
            let session = BattleSession(myTeam: team, opponentTeam: opponent, seed: seeds.next(),
                                        opponent: CPUOpponent(seed: seeds.next()), language: store.language,
                                        names: { PokemonNameDisplayStore.shared.names[$0] })
            BattleWindowController.shared.present(session, title: store.l.battlePractice)
        } catch {
            AppLog.write("practice opponent failed: \(error)")
            practiceFailed = true
        }
    }
}

/// Warms move and type names before the window opens, so battle lines are translated from the first turn.
enum BattleNamePrefetch {
    @MainActor
    static func load(_ teams: [BattleTeam], provider: any PokemonNameProviding = PokemonNameClient.shared,
                     store: PokemonNameDisplayStore = .shared) async {
        let moves = teams.flatMap(\.members).flatMap(\.moves) + [BattleMove.struggle]
        let resources = Set(moves.map { PokemonNameResource(kind: .move, name: $0.name) }
            + moves.filter { $0.type != BattleTypeChart.typeless }.map { PokemonNameResource(kind: .type, name: $0.type) })
        await withTaskGroup(of: Void.self) { group in
            for resource in resources where store.names[resource] == nil {
                group.addTask { _ = await store.load(resource, provider: provider) }
            }
        }
    }
}
