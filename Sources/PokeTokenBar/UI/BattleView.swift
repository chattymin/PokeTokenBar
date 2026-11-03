import SwiftUI

/// Local match state owns value snapshots only; no battle action writes to CompanionStore.
@MainActor
struct BattleView: View {
    let store: CompanionStore
    let onClose: () -> Void
    var scrollAreaHeight: CGFloat = 610
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lan = LANBattleSession()
    @State private var mode = BattleMode.offline
    @State private var hostAddress = ""
    @State private var portText = "43821"
    @State private var firstID = ""
    @State private var secondID = ""
    @State private var changingSide: Int?
    @State private var pendingPokemonID: String?
    @State private var prepared: [BattleCombatant] = []
    @State private var moveAvailability: [String: BattleMoveAvailability] = [:]
    @State private var preparing = false
    @State private var preparationMessage: String?
    @State private var battle: BattleState?
    @State private var battleCandidates: [OwnedBattlePokemon] = []
    @State private var displayedLANRevision = 0
    @State private var firstMoveID: String?
    @State private var events: [String] = []
    @State private var invalidBattle = false
    @State private var retry = 0
    @State private var playback: BattleTurnPlayback?
    @State private var displayedHP: [Int]?
    @State private var displayedStages: [[BattleStat: Int]]?
    @State private var attackingSide: Int?
    @State private var hitSide: Int?
    @State private var impactVisible = false
    @State private var faintedSides: Set<Int> = []
    @State private var attackEffect: BattleAttackEffect?
    @State private var effectProgress: CGFloat = 0
    @State private var hitFeedback: BattleHitFeedback?
    @State private var feedbackRaised = false
    @State private var feedbackVisible = false

    private var l: L { store.l }
    private var roster: [OwnedBattlePokemon] { BattleRoster.candidates(from: store.state, activeNames: store.state.active.flatMap { store.currentLine?.names[$0.currentID] } ?? [:]) }
    private var selectionKey: String { "\(mode)|\(firstID)|\(secondID)|\(retry)" }
    private var isLAN: Bool { mode == .lan }
    private var lanActive: Bool { lan.status != .idle && lan.status != .failed }
    private var isBattleScreen: Bool { battle != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isBattleScreen ? l.battleTitle : (isLAN ? l.battleLAN : l.battleOffline))
                    .font(.headline)
                Spacer()
                if isBattleScreen {
                    Button(l.battleChooseAgain) { lan.disconnect(); resetSelection() }
                        .buttonStyle(.borderless)
                }
                Button(l.close) { lan.disconnect(); onClose() }.buttonStyle(.borderless)
            }
            if isBattleScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let battle {
                            match(battle)
                        }
                    }
                    .reservesScrollerLane()
                }
                .frame(height: scrollAreaHeight)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let changingSide {
                pokemonRosterPicker(side: changingSide)
                    .frame(height: scrollAreaHeight)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(l.battleMode, selection: $mode) {
                            Text(l.battleOffline).tag(BattleMode.offline)
                            Text(l.battleLAN).tag(BattleMode.lan)
                        }.pickerStyle(.segmented)
                        if isLAN { lanStatus }
                        if isLAN {
                            lanSelection
                        } else {
                            selection
                        }
                        Text(l.battleRules)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .reservesScrollerLane()
                }
                .frame(height: scrollAreaHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isBattleScreen)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: changingSide)
        .onAppear {
            if firstID.isEmpty { firstID = roster.first?.id ?? "" }
            if secondID.isEmpty { secondID = roster.dropFirst().first?.id ?? "" }
        }
        .task(id: selectionKey) { await prepareSelection() }
        .onChange(of: mode) { _, _ in
            lan.disconnect()
            resetSelection()
        }
        .onChange(of: lan.revision) { _, _ in receiveLANUpdate() }
        .onChange(of: lan.status) { _, _ in receiveLANUpdate() }
        .onDisappear { lan.disconnect() }
        .task(id: playback?.id) {
            guard let playback else { return }
            await playTurn(playback)
        }
    }


    private var lanStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.battleLANHint).font(.caption).foregroundStyle(.secondary)
            Text(l.battleLANTrust).font(.caption).foregroundStyle(.secondary)
            if lanActive || lan.status == .failed {
                Text(lanStatusText).font(.callout)
                if let message = lan.statusMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                if lan.status == .listening {
                    ForEach(lan.localAddresses, id: \.self) { address in
                        Text("\(address):\(portText)").font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Button(l.battleDisconnect) { lan.disconnect(); resetSelection() }
            }
        }
    }

    private var lanStatusText: String {
        switch lan.status {
        case .idle: return l.battleLAN
        case .listening: return l.battleListening
        case .connecting: return l.battleConnecting
        case .waiting: return l.battleWaiting
        case .playing: return lan.hasSubmittedMove ? l.battleWaitingMove : l.battleConnected
        case .finished: return l.battleConnected
        case .failed: return l.battleConnectionFailed
        }
    }

    private var lanSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if roster.isEmpty {
                Text(l.battleNeedOne).foregroundStyle(.secondary)
            } else {
                candidatePicker(l.battleYourPokemon, selection: $firstID).disabled(lanActive)
                if preparing { ProgressView().controlSize(.small) }
                if let preparationMessage {
                    Text(preparationMessage).font(.caption).foregroundStyle(.orange)
                    Button(l.retry) { retry += 1 }
                }
                if let combatant = prepared.first { combatantPreview(combatant, side: 0) }
                TextField(l.battlePort, text: $portText).disabled(lanActive)
                Button(l.battleHost) { connectLAN(hosting: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(preparing || prepared.count != 1 || lanActive || validPort == nil)
                Divider()
                TextField(l.battleHostAddress, text: $hostAddress).disabled(lanActive)
                Button(l.battleJoin) { connectLAN(hosting: false) }
                    .disabled(preparing || prepared.count != 1 || lanActive || validPort == nil || hostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var validPort: UInt16? {
        guard let port = UInt16(portText), port > 0 else { return nil }
        return port
    }

    private func connectLAN(hosting: Bool) {
        guard let combatant = prepared.first, let port = validPort else { return }
        clearPlayback()
        events = []
        invalidBattle = false
        if hosting { lan.host(combatant: combatant, port: port) }
        else { lan.join(host: hostAddress.trimmingCharacters(in: .whitespacesAndNewlines), port: port, combatant: combatant) }
    }

    private func receiveLANUpdate() {
        guard isLAN else { return }
        guard let next = lan.battle else {
            if lan.status == .failed {
                clearPlayback()
                battle = nil
                firstMoveID = nil
                displayedLANRevision = 0
                events = []
            }
            return
        }
        if let previous = battle {
            if lan.revision > displayedLANRevision {
                clearPlayback()
                displayedHP = previous.fighters.map(\.currentHP)
                displayedStages = previous.fighters.map { fighter in
                    Dictionary(uniqueKeysWithValues: BattleStat.allCases.map { ($0, fighter.stages[$0]) })
                }
                events.append(l.battleTurn(previous.turn))
                playback = BattleTurnPlayback(turn: previous.turn, events: lan.lastTurnEvents, result: next)
                displayedLANRevision = lan.revision
            }
        } else {
            clearPlayback()
            events = []
            displayedLANRevision = lan.revision
            battleCandidates = roster.filter { $0.id == firstID }
        }
        battle = next
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let changingSide {
                pokemonRosterPicker(side: changingSide)
            } else {
                Text(l.battleSelectionHint).font(.callout)
                if roster.count < 2 {
                    Text(l.battleNeedTwo).foregroundStyle(.secondary)
                } else {
                    if firstID == secondID { Text(l.battleDistinct).font(.caption).foregroundStyle(.orange) }
                    if preparing {
                        HStack { ProgressView().controlSize(.small); Text(l.loadingPokemonDetails).font(.caption) }
                    }
                    if let preparationMessage {
                        Text(preparationMessage).font(.caption).foregroundStyle(.orange)
                        Button(l.retry) { retry += 1 }
                    }
                    if prepared.count == 2 {
                        VStack(spacing: 5) {
                            Text("VS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .accessibilityHidden(true)
                            HStack(alignment: .top, spacing: 10) {
                                combatantPreview(prepared[0], side: 0, selection: $firstID)
                                combatantPreview(prepared[1], side: 1, selection: $secondID)
                            }
                        }
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            selectionPlaceholder(side: 0, selection: $firstID)
                            selectionPlaceholder(side: 1, selection: $secondID)
                        }
                    }
                    Button(l.battleStart) { startBattle() }
                        .buttonStyle(.borderedProminent)
                        .disabled(preparing || prepared.count != 2 || firstID == secondID)
                }
            }
            if invalidBattle { Text(l.battleInvalid).font(.caption).foregroundStyle(.orange) }
        }
    }

    private func pokemonRosterPicker(side: Int) -> some View {
        let currentID = side == 0 ? firstID : secondID
        let otherID = side == 0 ? secondID : firstID
        let selectedID = pendingPokemonID ?? currentID
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(l.battleChangePokemon) · \(side == 0 ? l.battleFirst : l.battleSecond)")
                    .font(.headline)
                Spacer(minLength: 6)
                Button(l.cancel) { cancelPokemonChange() }
                    .buttonStyle(.borderless)
                Button(l.battlePickerDone) { confirmPokemonChange(side: side) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedID == otherID)
            }
            Text(l.battlePickerPrompt)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(roster) { candidate in
                        let isSelected = candidate.id == selectedID
                        let isInUse = candidate.id == otherID && !isSelected
                        Button {
                            guard !isInUse else { return }
                            pendingPokemonID = candidate.id
                        } label: {
                            HStack(spacing: 9) {
                                SpriteView(speciesID: candidate.speciesID, size: 50,
                                           animated: false, shiny: candidate.isShiny, form: candidate.form)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.displayName(language: store.language))
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("\(l.level) \(candidate.level) · #\(candidate.id.prefix(6))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Badge(l.rarityLabel(candidate.rarity).uppercased(),
                                              tint: .rarity(candidate.rarity), style: .tinted, size: 7)
                                    }
                                }
                                Spacer(minLength: 5)
                                Text(isSelected ? l.battlePickerSelected
                                     : (isInUse ? l.battlePickerInUse : l.battlePickerChoose))
                                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 9))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isInUse)
                        .accessibilityLabel("\(candidate.displayName(language: store.language)), \(l.level) \(candidate.level), \(isSelected ? l.battlePickerSelected : (isInUse ? l.battlePickerInUse : l.battlePickerChoose))")
                    }
                }
                .reservesScrollerLane()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 11))
    }

    private func cancelPokemonChange() {
        changingSide = nil
        pendingPokemonID = nil
    }

    private func confirmPokemonChange(side: Int) {
        guard let pendingPokemonID else { return }
        if side == 0 { firstID = pendingPokemonID } else { secondID = pendingPokemonID }
        cancelPokemonChange()
    }

    private func candidatePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(roster) { candidate in
                Text("\(candidate.displayName(language: store.language)) · \(l.level) \(candidate.level) · \(candidate.id.prefix(6))")
                    .tag(candidate.id)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func combatantPreview(_ combatant: BattleCombatant, side: Int,
                                  selection: Binding<String>? = nil) -> some View {
        let statValues: [(String, Int)] = Array(zip(["hp", "attack", "defense", "special-attack", "special-defense", "speed"],
                                                   [combatant.stats.hp, combatant.stats.attack,
                                                    combatant.stats.defense, combatant.stats.specialAttack,
                                                    combatant.stats.specialDefense, combatant.stats.speed]))
        let statScaleMaximum = max(1, statValues.map(\.1).max() ?? 1)
        let moves = combatant.moves.map(\.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(side == 0 ? l.battleFirst : l.battleSecond)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if let selection { candidateChangeButton(side: side, selection: selection) }
            }
            HStack(spacing: 8) {
                sprite(side: side, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(combatant.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(l.level) \(combatant.level) · #\(combatant.id.prefix(6))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            TypeBadges(types: combatant.types, language: store.language, size: 7)
                .lineLimit(1)
            Text("\(l.nature): \(natureSummary(for: combatant))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Divider().padding(.vertical, 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(l.actualStats).font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(l.actualStatsScaleMaximum(statScaleMaximum))
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                ForEach(statValues, id: \.0) { name, value in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(l.statLabel(name))
                            Spacer(minLength: 4)
                            Text("\(value)").monospacedDigit().fontWeight(.semibold)
                        }
                        .font(.caption2)
                        ProgressView(value: Double(value), total: Double(statScaleMaximum))
                            .progressViewStyle(.linear)
                            .tint(Color(red: 0.41, green: 0.78, blue: 0.68))
                            .controlSize(.small)
                            .frame(height: 5)
                    }
                }
            }
            Text(moves.map(moveName).joined(separator: " · "))
                .font(.caption2).fixedSize(horizontal: false, vertical: true).lineLimit(3)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 11))
    }

    private func candidateChangeButton(side: Int, selection: Binding<String>) -> some View {
        Button(l.battleChangePokemon) {
            pendingPokemonID = selection.wrappedValue
            changingSide = side
        }
        .font(.caption2)
        .buttonStyle(.borderless)
    }

    private func selectionPlaceholder(side: Int, selection: Binding<String>) -> some View {
        let candidate = roster.first { $0.id == selection.wrappedValue }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 4) {
                Text(side == 0 ? l.battleFirst : l.battleSecond)
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                candidateChangeButton(side: side, selection: selection)
            }
            if let candidate {
                HStack(spacing: 7) {
                    sprite(side: side, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.displayName(language: store.language))
                            .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text("\(l.level) \(candidate.level) · #\(candidate.id.prefix(6))")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                Text(l.battleNeedTwo).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(9).frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 11))
    }

    private func natureSummary(for combatant: BattleCombatant) -> String {
        guard let nature = roster.first(where: { $0.id == combatant.id })?.nature else { return "—" }
        let effects = PokemonStatCalculator.order.compactMap { stat -> String? in
            let modifier = nature.modifier(for: stat)
            guard modifier != 1 else { return nil }
            return "\(l.statLabel(stat)) \(modifier > 1 ? "+10%" : "−10%")"
        }
        return "\(nature.name(store.language)) · \(effects.isEmpty ? "±0%" : effects.joined(separator: ", "))"
    }

    private func match(_ state: BattleState) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                battleArena {
                    HStack(alignment: .center, spacing: 10) {
                        fighterCard(state, side: 0)
                        Text("VS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(9)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
                            .accessibilityHidden(true)
                        fighterCard(state, side: 1)
                    }
                }
                .overlayPreferenceValue(BattleSpriteCenterPreferenceKey.self) { anchors in
                    GeometryReader { geometry in
                        if let attackEffect, !reduceMotion,
                           let start = anchors[attackEffect.side],
                           let end = anchors[attackEffect.targetSide] {
                            BattleAttackEffectView(effect: attackEffect, progress: effectProgress,
                                                   startPoint: geometry[start], endPoint: geometry[end])
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                }

                if state.isFinished && playback == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        if let winner = state.winner {
                            Text(l.battleWinner(state.fighters[winner].combatant.name)).font(.headline)
                        } else {
                            Text(l.battleDraw).font(.headline)
                        }
                        if !isLAN { Button(l.battleRematch) { startBattle() }.buttonStyle(.borderedProminent) }
                    }
                } else {
                    let side = isLAN ? lan.localSide : (firstMoveID == nil ? 0 : 1)
                    battleActionHeading(
                        turn: playback?.turn ?? state.turn,
                        prompt: isLAN && lan.hasSubmittedMove
                            ? l.battleWaitingMove
                            : "\(side == 0 ? l.battleFirst : l.battleSecond) · \(l.battleChooseMove)")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(state.fighters[side].combatant.moves, id: \.id) { move in
                            Button { chooseMove(move.id) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(moveName(move.name)).font(.subheadline.weight(.medium))
                                        Text(moveSummary(move)).font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(2).multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                            .disabled(playback != nil || (isLAN && (lan.hasSubmittedMove || lan.status != .playing)))
                        }
                    }
                }
                if invalidBattle { Text(l.battleInvalid).font(.caption).foregroundStyle(.orange) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            battleLogRail(turn: state.turn)
        }
    }

    private func fighterCard(_ state: BattleState, side: Int) -> some View {
        let fighter = state.fighters[side]
        let hp = displayedHP?[side] ?? fighter.currentHP
        let stages = BattleStat.allCases.compactMap { stat -> String? in
            let value = displayedStages?[side][stat] ?? fighter.stages[stat]
            guard value != 0 else { return nil }
            return "\(l.statLabel(stat.rawValue)) \(value > 0 ? "+" : "")\(value)"
        }
        let alignment: HorizontalAlignment = side == 0 ? .leading : .trailing
        return HStack(spacing: 12) {
            if side == 0 { battleSprite(side: side, size: 116) }
            VStack(alignment: alignment, spacing: 6) {
                Text(side == 0 ? l.battleFirst : l.battleSecond)
                    .font(.caption).foregroundStyle(.secondary)
                Text(fighter.combatant.name).font(.headline).lineLimit(2)
                    .multilineTextAlignment(side == 0 ? .leading : .trailing)
                ProgressView(value: Double(hp), total: Double(fighter.combatant.stats.hp))
                    .tint(hp > fighter.combatant.stats.hp / 4 ? .green : .red)
                Text("HP \(hp)/\(fighter.combatant.stats.hp)").font(.caption).monospacedDigit()
                Text("\(l.battleTypes): \(fighter.combatant.types.map(moveName).joined(separator: "/"))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .multilineTextAlignment(side == 0 ? .leading : .trailing)
                if !stages.isEmpty {
                    Text(stages.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(side == 0 ? .leading : .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: side == 0 ? .leading : .trailing)
            if side == 1 { battleSprite(side: side, size: 116) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: side == 0 ? .leading : .trailing)
    }

    private func battleArena<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.green.opacity(0.08), Color.green.opacity(0.16), Color.green.opacity(0.22)],
                startPoint: .top, endPoint: .bottom)
            Ellipse().fill(Color.green.opacity(0.08)).frame(width: 420, height: 105)
                .offset(x: -230, y: 105)
            Ellipse().fill(Color.green.opacity(0.1)).frame(width: 420, height: 105)
                .offset(x: 230, y: 105)
            content().padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, minHeight: 252)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
    }

    private func battleSprite(side: Int, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.orange.opacity(impactVisible && hitSide == side ? 0.3 : 0))
                .frame(width: size * 1.1, height: size * 1.1)
            sprite(side: side, size: size)
                .offset(x: reduceMotion ? 0 : (attackingSide == side ? (side == 0 ? 22 : -22) : (hitSide == side ? (side == 0 ? -8 : 8) : 0)),
                        y: reduceMotion ? 0 : (faintedSides.contains(side) ? 10 : 0))
                .rotationEffect(.degrees(reduceMotion ? 0 : (attackingSide == side ? (side == 0 ? 8 : -8) : 0)))
                .scaleEffect(!reduceMotion && attackingSide == side ? 1.08 : 1)
                .opacity(faintedSides.contains(side) ? 0.35 : (impactVisible && hitSide == side ? 0.5 : 1))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .top) {
            if let hitFeedback, hitFeedback.side == side {
                Text(hitFeedback.text)
                    .font(.system(.headline, design: .rounded).bold())
                    .lineLimit(1).minimumScaleFactor(0.7).monospacedDigit()
                    .foregroundStyle(hitFeedback.color)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(hitFeedback.color.opacity(0.5)))
                    .offset(y: reduceMotion ? 0 : (feedbackRaised ? -8 : 6))
                    .opacity(feedbackVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityLabel(hitFeedback.accessibilityLabel)
                    .accessibilityHidden(!feedbackVisible)
            }
        }
        .anchorPreference(key: BattleSpriteCenterPreferenceKey.self, value: .center) { [side: $0] }
    }

    private func battleActionHeading(turn: Int, prompt: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(l.battleTurn(turn)).font(.headline)
            Spacer(minLength: 8)
            Text(prompt).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func battleLogRail(turn: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(l.battleLog, systemImage: "text.alignleft")
                .font(.subheadline.weight(.semibold))
            Divider().padding(.vertical, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if events.isEmpty {
                            Text(l.battleTurn(turn))
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                                Text(event)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                if index < events.count - 1 { Divider() }
                            }
                        }
                        Color.clear.frame(height: 1).id("battle-log-bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .reservesScrollerLane()
                }
                .onChange(of: events.count) { _, _ in
                    proxy.scrollTo("battle-log-bottom", anchor: .bottom)
                }
            }
        }
        .padding(12)
        .frame(width: 260, height: scrollAreaHeight, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
    }

    private func sprite(side: Int, size: CGFloat) -> some View {
        let id = isLAN ? (side == lan.localSide ? firstID : "") : (side == 0 ? firstID : secondID)
        let candidates = battle == nil ? roster : battleCandidates
        let candidate = candidates.first { $0.id == id }
        let speciesID = battle?.fighters.indices.contains(side) == true
            ? battle?.fighters[side].combatant.speciesID : candidate?.speciesID
        return SpriteView(speciesID: speciesID, size: size,
                          bob: !reduceMotion && !(battle?.isFinished ?? false),
                          animated: !reduceMotion && !(battle?.isFinished ?? false),
                          shiny: candidate?.isShiny ?? false, form: candidate?.form)
    }

    private func moveSummary(_ move: BattleMove) -> String {
        switch move.effect {
        case .damage: return "\(move.power) · \(move.accuracy)%"
        case .recoil: return "\(move.power) · \(move.accuracy)% · \(l.battleRecoil)"
        case let .stages(target, changes):
            let who = target == .user ? l.battleSelf : l.battleOpponent
            let effects = changes.map { "\(l.statLabel($0.stat.rawValue)) \($0.stages > 0 ? "+" : "")\($0.stages)" }.joined(separator: ", ")
            return "\(who) · \(effects) · \(move.accuracy)%"
        case .heal: return l.battleHealHalf
        }
    }

    private func moveName(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func prepareSelection() async {
        prepared = []
        moveAvailability = [:]
        preparationMessage = nil
        preparing = false
        guard let first = roster.first(where: { $0.id == firstID }) else { return }
        let second = roster.first(where: { $0.id == secondID })
        guard isLAN || (firstID != secondID && second != nil) else { return }
        preparing = true
        defer { if !Task.isCancelled { preparing = false } }
        do {
            let one = try await BattleRoster.prepareWithAvailability(first, language: store.language)
            if isLAN {
                guard !Task.isCancelled else { return }
                moveAvailability = [one.combatant.id: one.moveAvailability]
                prepared = [one.combatant]
            } else if let second {
                let two = try await BattleRoster.prepareWithAvailability(second, language: store.language)
                guard !Task.isCancelled else { return }
                moveAvailability = [one.combatant.id: one.moveAvailability, two.combatant.id: two.moveAvailability]
                prepared = [one.combatant, two.combatant]
            }
        } catch {
            guard !Task.isCancelled else { return }
            preparationMessage = l.battleUnavailable
        }
    }

    private func startBattle() {
        guard prepared.count == 2 else { return }
        clearPlayback()
        do {
            battleCandidates = roster.filter { $0.id == firstID || $0.id == secondID }
            let next = try BattleState(first: prepared[0], second: prepared[1], seed: UInt64.random(in: .min ... .max))
            battle = next
            firstMoveID = nil
            events = []
            invalidBattle = false
        } catch { invalidBattle = true }
    }

    private func chooseMove(_ moveID: String) {
        guard var next = battle, !next.isFinished, playback == nil else { return }
        if isLAN { lan.submit(moveID: moveID); return }
        guard let first = firstMoveID else { firstMoveID = moveID; return }
        do {
            let turn = next.turn
            let initialHP = next.fighters.map(\.currentHP)
            let initialStages = next.fighters.map { fighter in
                Dictionary(uniqueKeysWithValues: BattleStat.allCases.map { ($0, fighter.stages[$0]) })
            }
            let resolved = try next.resolve(firstMoveID: first, secondMoveID: moveID)
            events.append(l.battleTurn(turn))
            displayedHP = initialHP; displayedStages = initialStages
            playback = BattleTurnPlayback(turn: turn, events: resolved, result: next)
            battle = next; firstMoveID = nil
        } catch { invalidBattle = true }
    }

    private func eventText(_ event: BattleEvent, state: BattleState) -> String {
        switch event {
        case let .attack(side, moveID, damage, _):
            let fighter = state.fighters[side].combatant
            let name = fighter.moves.first { $0.id == moveID }?.name ?? moveID
            return l.battleAttack(fighter.name, move: moveName(name), damage: damage)
        case let .miss(side, _): return l.battleMiss(state.fighters[side].combatant.name)
        case let .statChange(side, target, moveID, stat, change, _):
            let move = BattleMoveCatalog.move(named: moveID)?.name ?? moveID
            return "\(state.fighters[side].combatant.name): \(moveName(move)) · \(l.battleStatChanged(state.fighters[target].combatant.name, stat: l.statLabel(stat.rawValue), change: change))"
        case let .heal(side, _, amount): return l.battleHealed(state.fighters[side].combatant.name, amount: amount)
        case let .recoil(side, _, damage): return "\(state.fighters[side].combatant.name) · \(l.battleRecoil) −\(damage) HP"
        case let .failed(side, _): return l.battleMoveFailed(state.fighters[side].combatant.name)
        case let .fainted(side): return l.battleFainted(state.fighters[side].combatant.name)
        case let .won(side): return l.battleWinner(state.fighters[side].combatant.name)
        case .draw: return l.battleDraw
        }
    }

    private func resetSelection() {
        clearPlayback()
        battle = nil
        battleCandidates = []
        firstMoveID = nil
        displayedLANRevision = 0
        events = []
        invalidBattle = false
    }

    private func clearPlayback() {
        playback = nil
        displayedHP = nil
        displayedStages = nil
        attackingSide = nil
        hitSide = nil
        impactVisible = false
        faintedSides = []
        attackEffect = nil
        effectProgress = 0
        hitFeedback = nil
        feedbackRaised = false
        feedbackVisible = false
    }

    /// The engine resolves atomically; presentation follows its ordered events without rerolling it.
    private func playTurn(_ turn: BattleTurnPlayback) async {
        defer {
            // A cancelled old task must never clear the next match's animation state.
            if playback?.id == turn.id {
                playback = nil
                displayedHP = nil
                displayedStages = nil
                attackingSide = nil
                hitSide = nil
                impactVisible = false
                attackEffect = nil
                effectProgress = 0
                hitFeedback = nil
                feedbackRaised = false
                feedbackVisible = false
            }
        }
        do {
            for event in turn.events {
                try Task.checkCancellation()
                switch event {
                case let .attack(side, moveID, damage, effectiveness):
                    try await animateAttack(side: side, moveID: moveID)
                    if damage > 0 {
                        let target = 1 - side
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                            hitSide = target
                            impactVisible = true
                            if var hp = displayedHP {
                                hp[target] = max(0, hp[target] - damage)
                                displayedHP = hp
                            }
                        }
                        try await pause(0.16)
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                            hitSide = nil
                            impactVisible = false
                        }
                    }
                    let target = 1 - side
                    try await showHitFeedback(BattleHitFeedback(
                        side: target,
                        text: effectiveness == 0 ? l.battleNoEffectBadge : (damage > 0 ? "−\(damage)" : "0"),
                        accessibilityLabel: effectiveness == 0
                            ? l.battleNoEffectOn(turn.result.fighters[target].combatant.name)
                            : l.battleDamageTaken(turn.result.fighters[target].combatant.name, damage: damage),
                        isDamage: damage > 0))
                case let .miss(side, moveID):
                    try await animateAttack(side: side, moveID: moveID)
                    try await showHitFeedback(BattleHitFeedback(
                        side: 1 - side, text: l.battleMissBadge,
                        accessibilityLabel: l.battleMiss(turn.result.fighters[side].combatant.name),
                        isDamage: false))
                case let .statChange(side, target, moveID, stat, change, stage):
                    if var stages = displayedStages {
                        stages[target][stat] = stage
                        displayedStages = stages
                    }
                    try await animateBattleEffect(side: side, targetSide: target, moveID: moveID,
                                                  metadata: nil, kind: change > 0 ? .boost : .status)
                    let text = change == 0 ? l.battleNoChangeBadge : "\(l.statLabel(stat.rawValue)) \(change > 0 ? "+" : "")\(change)"
                    try await showHitFeedback(BattleHitFeedback(
                        side: target, text: text,
                        accessibilityLabel: l.battleStatChanged(turn.result.fighters[target].combatant.name, stat: l.statLabel(stat.rawValue), change: change),
                        isDamage: change < 0, isPositive: change > 0))
                case let .heal(side, moveID, amount):
                    try await animateBattleEffect(side: side, targetSide: side, moveID: moveID,
                                                  metadata: nil, kind: .boost)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        if var hp = displayedHP {
                            hp[side] = min(turn.result.fighters[side].combatant.stats.hp, hp[side] + amount)
                            displayedHP = hp
                        }
                    }
                    try await showHitFeedback(BattleHitFeedback(
                        side: side, text: "+\(amount) HP",
                        accessibilityLabel: l.battleHealed(turn.result.fighters[side].combatant.name, amount: amount),
                        isDamage: false, isPositive: true))
                case let .recoil(side, _, damage):
                    if var hp = displayedHP {
                        hp[side] = max(0, hp[side] - damage)
                        displayedHP = hp
                    }
                    try await showHitFeedback(BattleHitFeedback(
                        side: side, text: "−\(damage)",
                        accessibilityLabel: "\(l.battleRecoil): \(l.battleDamageTaken(turn.result.fighters[side].combatant.name, damage: damage))",
                        isDamage: true))
                case let .failed(side, _):
                    try await showHitFeedback(BattleHitFeedback(
                        side: side, text: l.battleNoChangeBadge,
                        accessibilityLabel: l.battleMoveFailed(turn.result.fighters[side].combatant.name), isDamage: false))
                case let .fainted(side):
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        _ = faintedSides.insert(side)
                    }
                case .won, .draw: break
                }
                try Task.checkCancellation()
                events.append(eventText(event, state: turn.result))
                try await pause(0.22)
            }
        } catch is CancellationError {
            // SwiftUI cancels the playback task when selection changes or the battle window closes.
        } catch { invalidBattle = true }
    }

    private func animateAttack(side: Int, moveID: String, metadata: BattleMove? = nil) async throws {
        try await animateBattleEffect(side: side, targetSide: 1 - side, moveID: moveID,
                                      metadata: metadata, kind: .attack)
    }

    private func animateBattleEffect(side: Int, targetSide: Int, moveID: String,
                                     metadata: BattleMove?, kind: BattleAttackEffect.Kind) async throws {
        guard !reduceMotion else { return }
        attackEffect = BattleAttackEffect(side: side, targetSide: targetSide, moveID: moveID,
                                          metadata: metadata, kind: kind)
        effectProgress = 0
        if kind == .attack {
            withAnimation(.easeOut(duration: 0.18)) { attackingSide = side }
        } else {
            attackingSide = nil
        }
        try await pause(0.12)
        withAnimation(.linear(duration: 0.46)) { effectProgress = 1 }
        if kind == .attack {
            withAnimation(.easeInOut(duration: 0.18)) { attackingSide = nil }
        }
        try await pause(0.46)
        attackEffect = nil
        effectProgress = 0
    }

    /// One result badge at a time; retain readable feedback even when motion is reduced.
    private func showHitFeedback(_ feedback: BattleHitFeedback) async throws {
        try Task.checkCancellation()
        hitFeedback = feedback
        feedbackRaised = false
        feedbackVisible = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { feedbackRaised = true }
        try await Task.sleep(for: .milliseconds(650))
        try Task.checkCancellation()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { feedbackVisible = false }
        if !reduceMotion { try await Task.sleep(for: .milliseconds(150)) }
        try Task.checkCancellation()
        hitFeedback = nil
    }

    private func pause(_ seconds: Double) async throws {
        try Task.checkCancellation()
        guard !reduceMotion else { return }
        try await Task.sleep(for: .seconds(seconds))
    }
}

private struct BattleSpriteCenterPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGPoint>] = [:]

    static func reduce(value: inout [Int: Anchor<CGPoint>], nextValue: () -> [Int: Anchor<CGPoint>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct BattleHitFeedback {
    let side: Int
    let text: String
    let accessibilityLabel: String
    let isDamage: Bool
    var isPositive = false
    var color: Color { isDamage ? .red : (isPositive ? .green : .primary) }
}

private struct BattleTurnPlayback: Identifiable {
    let id = UUID()
    let turn: Int
    let events: [BattleEvent]
    let result: BattleState
}

private enum BattleMode: Hashable { case offline, lan }

/// Presentation only: each supported move chooses a visual motif without changing battle rules.
private struct BattleAttackEffect {
    enum Kind: Equatable { case attack, boost, status, shield }
    enum Motif { case impact, slash, vine, stream, wing, horn, punch, kick, rings, gem, tail, claw, seed, rock, clamp, egg, cross, pulse, star, shadow, leaf, bolt, aura, magnet, flame, ice, poison, swarm, steel, earth, ghost }
    let side: Int
    let targetSide: Int
    let kind: Kind
    let motif: Motif
    let color: Color
    let intensity: CGFloat

    init(side: Int, targetSide: Int, moveID: String, metadata: BattleMove?, kind: Kind) {
        self.side = side
        self.targetSide = targetSide
        self.kind = kind
        let move = BattleMoveCatalog.move(named: moveID)
        let type = (metadata?.type ?? move?.type)?.lowercased()
        intensity = CGFloat(metadata?.power ?? move?.power ?? 40) / 80
        switch type {
        case "normal": color = .white
        case "fire": color = .orange
        case "water": color = .cyan
        case "electric": color = .yellow
        case "grass": color = .green
        case "ice": color = .teal
        case "fighting": color = .red
        case "poison": color = .purple
        case "ground", "rock": color = .brown
        case "flying": color = .cyan
        case "psychic", "fairy": color = .pink
        case "bug": color = .mint
        case "ghost": color = .purple
        case "dragon": color = .indigo
        case "dark": color = .gray
        case "steel": color = .gray
        default: color = .white
        }
        switch type {
        case "normal":
            switch moveID {
            case "scratch", "cut": motif = .slash
            case "pound", "mega-punch": motif = .punch
            case "mega-kick": motif = .kick
            case "hyper-voice": motif = .rings
            case "vice-grip": motif = .clamp
            case "egg-bomb": motif = .egg
            case "swift": motif = .star
            default: motif = .impact
            }
        case "fire": motif = .flame
        case "water": motif = moveID == "aqua-tail" ? .tail : .stream
        case "electric": motif = .bolt
        case "grass":
            switch moveID {
            case "vine-whip", "power-whip": motif = .vine
            case "seed-bomb": motif = .seed
            default: motif = .leaf
            }
        case "ice": motif = .ice
        case "fighting": motif = moveID == "aura-sphere" ? .aura : .punch
        case "poison": motif = .poison
        case "ground": motif = .earth
        case "flying": motif = .wing
        case "psychic": motif = .rings
        case "bug":
            switch moveID {
            case "x-scissor": motif = .cross
            case "megahorn": motif = .horn
            default: motif = .swarm
            }
        case "rock": motif = moveID == "power-gem" ? .gem : .rock
        case "ghost": motif = .ghost
        case "dark": motif = .shadow
        case "dragon": motif = moveID == "dragon-claw" ? .claw : .pulse
        case "steel": motif = moveID == "magnet-bomb" ? .magnet : .steel
        case "fairy": motif = .star
        default: motif = .impact
        }
    }
}

/// A finite animation driven by turn playback, with no repeating timer or persistent particles.
@MainActor
private struct BattleAttackEffectView: View, @preconcurrency Animatable {
    let effect: BattleAttackEffect
    var progress: CGFloat
    let startPoint: CGPoint
    let endPoint: CGPoint
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            var renderer = BattleAttackEffectRenderer(context: context)
            renderer.draw(effect: effect, progress: progress, startPoint: startPoint, endPoint: endPoint)
            context = renderer.context
        }
    }
}

private struct BattleAttackEffectRenderer {
    var context: GraphicsContext

    mutating func draw(effect: BattleAttackEffect, progress: CGFloat, startPoint: CGPoint, endPoint: CGPoint) {
        let p = min(1, max(0, progress))
        let start = startPoint
        let end = endPoint
        let direction: CGFloat = end.x >= start.x ? 1 : -1
        func trajectoryPoint(_ fraction: CGFloat, verticalOffset: CGFloat = 0) -> CGPoint {
            CGPoint(x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction + verticalOffset)
        }
        let point = effect.kind == .attack
            ? trajectoryPoint(p)
            : end
        let alpha = Double(min(1, p * 8) * min(1, (1 - p) * 8))
        context.opacity = alpha
        let color = effect.color
        let strength = min(1.5, max(0.65, effect.intensity))

        if effect.kind != .attack {
            switch effect.kind {
            case .boost:
                circle(end, radius: 10 + 23 * p, tint: color.opacity(0.75 * (1 - p)), filled: false)
                circle(end, radius: 7 + 12 * p, tint: color.opacity(0.45 * (1 - p)), filled: false)
                for i in 0..<4 {
                    let angle = CGFloat(i) * .pi / 2 + p * .pi * 0.8
                    let center = CGPoint(x: end.x + cos(angle) * (15 + 13 * p),
                                         y: end.y + sin(angle) * (15 + 13 * p) - 8 * p)
                    polygon(center, radius: 4 * (1 - p * 0.4), sides: 4,
                            rotation: p * .pi, tint: color)
                }
            case .status:
                circle(end, radius: 19 + 7 * p, tint: color.opacity(0.3 * (1 - p)), filled: false)
                for i in 0..<5 {
                    let lag = CGFloat(i) * 0.08
                    let q = max(0, p - lag)
                    let angle = CGFloat(i) * .pi * 0.4 + q * .pi * 2
                    let center = CGPoint(x: end.x + cos(angle) * (8 + 13 * q),
                                         y: end.y + sin(angle) * (8 + 13 * q))
                    circle(center, radius: (4.5 - CGFloat(i) * 0.35) * (1 - q * 0.4),
                           tint: color.opacity(0.85 - Double(i) * 0.08))
                }
            case .shield:
                var shield = Path()
                shield.move(to: CGPoint(x: end.x, y: end.y - 27))
                shield.addLine(to: CGPoint(x: end.x + 21, y: end.y - 17))
                shield.addLine(to: CGPoint(x: end.x + 17, y: end.y + 8))
                shield.addQuadCurve(to: CGPoint(x: end.x, y: end.y + 27),
                                    control: CGPoint(x: end.x + 10, y: end.y + 23))
                shield.addQuadCurve(to: CGPoint(x: end.x - 17, y: end.y + 8),
                                    control: CGPoint(x: end.x - 10, y: end.y + 23))
                shield.addLine(to: CGPoint(x: end.x - 21, y: end.y - 17))
                shield.closeSubpath()
                context.opacity *= 0.25
                context.fill(shield, with: .color(color))
                context.opacity = alpha
                context.stroke(shield, with: .color(color), lineWidth: 3)
                circle(end, radius: 34 + 4 * p, tint: color.opacity(0.45 * (1 - p)), filled: false)
            case .attack:
                break
            }
            return
        }
        switch effect.motif {
        case .flame:
            for i in 0..<4 {
                let lag = CGFloat(i) * 0.07
                let q = max(0, p - lag)
                let center = trajectoryPoint(q, verticalOffset: sin(q * .pi * 4 + CGFloat(i)) * 6)
                polygon(center, radius: (11 - CGFloat(i)) * strength, sides: 3,
                        rotation: -.pi / 2 + q * .pi, tint: color.opacity(1 - Double(i) * 0.14))
                if i == 0 { circle(center, radius: 4 * strength, tint: .yellow) }
            }
        case .ice, .steel:
            for i in 0..<4 {
                let lag = CGFloat(i) * 0.08
                let q = max(0, p - lag)
                let center = trajectoryPoint(q, verticalOffset: sin(q * .pi * 3 + CGFloat(i)) * 14)
                polygon(center, radius: (9 - CGFloat(i)) * strength,
                        sides: effect.motif == .ice ? 4 : 6,
                        rotation: q * .pi * 2, tint: color.opacity(1 - Double(i) * 0.15))
                line([CGPoint(x: center.x - 3, y: center.y), CGPoint(x: center.x + 3, y: center.y)],
                     width: 1.5, tint: .white.opacity(0.8))
            }
        case .poison:
            for i in 0..<5 {
                let lag = CGFloat(i) * 0.07
                let q = max(0, p - lag)
                let center = trajectoryPoint(q, verticalOffset: sin(q * .pi * 4 + CGFloat(i) * 1.4) * 11)
                circle(center, radius: (7 - CGFloat(i) * 0.6) * strength,
                       tint: color.opacity(0.8 - Double(i) * 0.1))
                circle(center, radius: 2, tint: .white.opacity(0.65))
            }
        case .swarm:
            for i in 0..<6 {
                let lag = CGFloat(i) * 0.045
                let q = max(0, p - lag)
                let offset = CGFloat(i - 2) * 5
                let center = trajectoryPoint(q, verticalOffset: sin(q * .pi * 5 + CGFloat(i)) * 12 + offset)
                circle(center, radius: 3.5 * strength, tint: color)
                line([CGPoint(x: center.x - direction * 5, y: center.y - 2),
                      CGPoint(x: center.x + direction * 5, y: center.y + 2)], width: 1.5, tint: .white)
            }
        case .earth:
            for i in 0..<5 {
                let lag = CGFloat(i) * 0.07
                let q = max(0, p - lag)
                let center = trajectoryPoint(q, verticalOffset: sin(q * .pi * 4 + CGFloat(i)) * 13)
                polygon(center, radius: (6 + CGFloat(i % 2) * 2) * strength,
                        sides: 5, rotation: q * .pi * 2, tint: color.opacity(0.9 - Double(i) * 0.12))
            }
            let burst = min(1, p * 1.7)
            circle(end, radius: 10 * burst, tint: color.opacity(0.18), filled: false)
        case .ghost:
            for i in 0..<3 {
                let q = max(0, p - CGFloat(i) * 0.09)
                let center = trajectoryPoint(q, verticalOffset: sin(q * .pi * 3 + CGFloat(i)) * 8)
                circle(center, radius: (12 - CGFloat(i) * 2) * strength,
                       tint: color.opacity(0.22 - Double(i) * 0.04))
                circle(center, radius: (7 - CGFloat(i)) * strength,
                       tint: color.opacity(0.75 - Double(i) * 0.15), filled: false)
            }
        case .stream:
            for i in 0..<5 {
                let lag = CGFloat(i) * 0.055
                let q = max(0, p - lag)
                let center = trajectoryPoint(q, verticalOffset: sin(q * .pi * 5 + CGFloat(i)) * 6)
                circle(center, radius: (8 - CGFloat(i)) * strength, tint: color.opacity(1 - Double(i) * 0.13))
            }
            line([CGPoint(x: point.x - direction * 25 * strength, y: point.y), point], width: 4 * strength, tint: .white.opacity(0.7))
        case .vine, .tail:
            var path = Path(); path.move(to: start)
            path.addQuadCurve(to: point, control: CGPoint(x: (start.x + point.x) / 2,
                                                          y: (start.y + point.y) / 2 - sin(p * .pi) * 48))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: effect.motif == .tail ? 10 : 4 * strength, lineCap: .round))
            circle(point, radius: 4, tint: color)
        case .bolt:
            let span = point.x - start.x
            var vertices: [CGPoint] = []
            for i in 0...8 {
                let x = start.x + span * CGFloat(i) / 8
                let displacement: CGFloat = i == 0 || i == 8 ? 0 : (i.isMultiple(of: 2) ? -12 : 12)
                let baseY = start.y + (point.y - start.y) * CGFloat(i) / 8
                vertices.append(CGPoint(x: x, y: baseY + displacement))
            }
            line(vertices, width: 5, tint: color)
            circle(point, radius: 8, tint: .white)
        case .rings, .pulse:
            for i in 0..<3 {
                let center = CGPoint(x: point.x - direction * CGFloat(i) * 15, y: point.y)
                let radius = CGFloat(10 + i * 5) * (effect.motif == .pulse ? 1.2 : 1)
                circle(center, radius: radius, tint: color.opacity(1 - Double(i) * 0.2), filled: false)
            }
        case .wing:
            for i in 0..<3 {
                let lag = CGFloat(i) * 0.08
                let q = max(0, p - lag)
                let center = trajectoryPoint(q, verticalOffset: CGFloat(i - 1) * 12)
                let span = CGFloat(24 - i * 5) * strength
                line([CGPoint(x: center.x - direction * span, y: center.y + 8),
                      CGPoint(x: center.x, y: center.y - 7),
                      CGPoint(x: center.x + direction * span, y: center.y + 8)],
                     width: 2.5 * strength, tint: color.opacity(1 - Double(i) * 0.18))
            }
        case .aura:
            circle(point, radius: 19, tint: color.opacity(0.25))
            circle(point, radius: 13, tint: color)
            circle(point, radius: 7, tint: .white)
            circle(point, radius: 22 + sin(p * .pi * 4) * 3, tint: color, filled: false)
        case .star:
            for i in 0..<3 {
                let center = CGPoint(x: point.x - direction * CGFloat(i) * 14,
                                     y: point.y + CGFloat(i - 1) * 13)
                var path = Path()
                for vertex in 0..<10 {
                    let angle = CGFloat(vertex) * .pi / 5 - .pi / 2 + p * .pi
                    let radius: CGFloat = vertex % 2 == 0 ? 10 : 4
                    let v = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    if vertex == 0 { path.move(to: v) } else { path.addLine(to: v) }
                }
                path.closeSubpath(); context.fill(path, with: .color(color))
            }
        case .leaf, .seed:
            for i in 0..<4 {
                let center = CGPoint(x: point.x - direction * CGFloat(i) * 8,
                                     y: point.y + sin(p * .pi * 3 + CGFloat(i)) * 16)
                polygon(center, radius: effect.motif == .leaf ? 8 : 5, sides: effect.motif == .leaf ? 4 : 6, rotation: p * .pi * 2, tint: color)
            }
        case .rock, .gem, .magnet, .egg:
            let center = CGPoint(x: point.x, y: point.y - sin(p * .pi) * 28)
            if effect.motif == .egg {
                context.fill(Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 13, width: 18, height: 26)), with: .color(.white))
                circle(CGPoint(x: center.x + 3, y: center.y - 3), radius: 3, tint: .orange)
            } else {
                polygon(center, radius: 13, sides: effect.motif == .gem ? 4 : 6, rotation: p * .pi * 2, tint: color)
                circle(center, radius: 4, tint: .white.opacity(0.6))
            }
        case .slash, .claw, .cross:
            let center = CGPoint(x: end.x, y: end.y)
            let reveal = min(1, p * 1.5)
            for i in 0..<(effect.motif == .claw ? 3 : 2) {
                let shift = CGFloat(i) * 9 - 7
                let reverse: CGFloat = effect.motif == .cross && i == 1 ? -1 : 1
                line([CGPoint(x: center.x - 22 + shift, y: center.y + 23 * reverse), CGPoint(x: center.x - 22 + shift + 44 * reveal, y: center.y + (23 - 46 * reveal) * reverse)], width: 3, tint: color)
            }
        case .horn:
            polygon(point, radius: 15 * strength, sides: 3, rotation: direction > 0 ? 0 : .pi, tint: color)
            line([CGPoint(x: point.x - direction * 28, y: point.y), point], width: 3, tint: color.opacity(0.5))
        case .clamp:
            let gap = 5 + (1 - p) * 18
            for sign: CGFloat in [-1, 1] {
                line([CGPoint(x: end.x - 14, y: end.y + sign * gap),
                      CGPoint(x: end.x, y: end.y + sign * gap / 2),
                      CGPoint(x: end.x + 14, y: end.y + sign * gap)], width: 5, tint: color)
            }
        case .punch, .kick, .shadow, .impact:
            let radius = (effect.motif == .kick ? 16 : 12) * strength
            circle(point, radius: radius + 6, tint: color.opacity(0.2))
            polygon(point, radius: radius, sides: effect.motif == .punch ? 6 : 8, rotation: p * .pi, tint: color)
            for i in 0..<5 {
                let angle = CGFloat(i) * .pi * 2 / 5
                line([CGPoint(x: point.x + cos(angle) * (radius + 4), y: point.y + sin(angle) * (radius + 4)), CGPoint(x: point.x + cos(angle) * (radius + 11), y: point.y + sin(angle) * (radius + 11))], width: 2, tint: color)
            }
        }
    }

    mutating func line(_ points: [CGPoint], width: CGFloat, tint: Color) {
        guard let first = points.first else { return }
        var path = Path(); path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    mutating func circle(_ center: CGPoint, radius: CGFloat, tint: Color, filled: Bool = true) {
        let path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        if filled { context.fill(path, with: .color(tint)) }
        else { context.stroke(path, with: .color(tint), lineWidth: 2) }
    }

    mutating func polygon(_ center: CGPoint, radius: CGFloat, sides: Int, rotation: CGFloat = 0, tint: Color) {
        var path = Path()
        for i in 0..<sides {
            let angle = CGFloat(i) * .pi * 2 / CGFloat(sides) + rotation
            let vertex = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if i == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
        }
        path.closeSubpath(); context.fill(path, with: .color(tint))
    }
}
