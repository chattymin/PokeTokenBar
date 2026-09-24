import SwiftUI

/// Everything the recap prints, read once.
@MainActor
struct RecapContent {
    let language: AppLanguage
    let recap: UsageRecap
    let companionSpeciesID: Int?
    let companionShiny: Bool
    let companionUnownForm: UnownForm?
    let graduates: [(entry: DexEntry, name: String)]
    private let calendar: Calendar
    /// Built once per read: a `DateFormatter` is expensive and the card asks for a label per meter.
    private let dayKeyFormatter: DateFormatter
    private let dayNameFormatter: DateFormatter
    private let monthNameFormatter: DateFormatter

    init(store: UsageStore, companion: CompanionStore, scope: RecapScope, offset: Int,
         now: Date = Date(), calendar: Calendar = RecapPeriod.calendar()) {
        language = companion.language
        self.calendar = calendar
        let period = RecapPeriod(scope: scope, containing: now, calendar: calendar)
            .shifted(by: offset, calendar: calendar)
        recap = UsageRecap.make(ledger: store.dailyLedger, dex: companion.state.dex, period: period,
                                now: now, calendar: calendar)
        // The Pokémon being raised right now, not the pinned representative: the recap is about
        // usage that just happened, so it shows who lived it.
        companionSpeciesID = companion.currentSpeciesID
        companionShiny = companion.currentIsShiny
        companionUnownForm = companion.currentUnownForm
        graduates = recap.graduated.prefix(4).map { entry in
            let name = companion.dexStoredChainNames(entry)?[entry.finalID] ?? "#\(entry.finalID)"
            return (entry, UnownForm.displayName(name, speciesID: entry.finalID, form: entry.unownForm))
        }
        dayKeyFormatter = LocalUsageReader.localDayFormatter(timeZone: calendar.timeZone)
        dayNameFormatter = Self.formatter(language, calendar, template: "EEEE d MMM")
        monthNameFormatter = Self.formatter(language, calendar, template: "MMMM y")
    }

    private static func formatter(_ language: AppLanguage, _ calendar: Calendar, template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.displayLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    var l: L { L(language) }
    var scope: RecapScope { recap.period.scope }

    /// "14–20 Sept 2026", "September 2026" or "2026", from the display locale. It titles the card.
    func periodLabel() -> String {
        switch scope {
        case .week:
            let formatter = DateIntervalFormatter()
            formatter.locale = language.displayLocale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateTemplate = "dMMMy"
            let lastDay = calendar.date(byAdding: .day, value: -1, to: recap.period.end) ?? recap.period.start
            return formatter.string(from: recap.period.start, to: lastDay)
        case .month:
            return monthNameFormatter.string(from: recap.period.start)
        case .year:
            return String(calendar.component(.year, from: recap.period.start))
        }
    }

    /// One short label per meter, from the display locale so there is nothing of ours to translate.
    /// Weekdays take two letters (one collides: mardi/mercredi, Tuesday/Thursday), a month labels
    /// only its weekly marks since 31 numbers do not fit, and a year uses month initials.
    func bucketLabels() -> [String] {
        let symbols = DateFormatter()
        symbols.locale = language.displayLocale
        let weekdays = symbols.shortStandaloneWeekdaySymbols ?? []
        let months = symbols.veryShortStandaloneMonthSymbols ?? []
        return recap.buckets.map { bucket in
            guard let date = dayKeyFormatter.date(from: bucket.key) else { return "" }
            switch scope {
            case .week:
                guard !weekdays.isEmpty else { return "" }
                let weekday = calendar.component(.weekday, from: date)   // 1-based
                return String(weekdays[(weekday - 1) % weekdays.count].prefix(2)).uppercased()
            case .month:
                let day = calendar.component(.day, from: date)
                return [1, 8, 15, 22, 29].contains(day) ? "\(day)" : ""
            case .year:
                guard !months.isEmpty else { return "" }
                let month = calendar.component(.month, from: date)   // 1-based
                return months[(month - 1) % months.count].uppercased()
            }
        }
    }

    func dayLabel(_ key: String) -> String {
        guard let date = dayKeyFormatter.date(from: key) else { return key }
        return dayNameFormatter.string(from: date)
    }

    func accessibilityLabel(_ bucket: UsageRecap.Bucket) -> String {
        let name: String
        if scope == .year, let date = dayKeyFormatter.date(from: bucket.key) {
            name = monthNameFormatter.string(from: date)
        } else {
            name = dayLabel(bucket.key)
        }
        return "\(name), \(bucket.hasData ? TokenFormatter.grouped(bucket.tokens) : l.recapNoData)"
    }

}

/// The recap panel — a Pokédex readout, not a second trainer card: red shell, dark LCD,
/// monospaced digits and segmented meters. Colors are all explicit so the card never shifts
/// with the system appearance.
@MainActor
struct RecapCard: View {
    let content: RecapContent

    private static let size = CGSize(width: PopoverMetrics.contentWidth, height: 226)
    private static let shellTop = Color(red: 0.84, green: 0.21, blue: 0.18)
    private static let shellBottom = Color(red: 0.66, green: 0.12, blue: 0.11)
    private static let screenInk = Color(red: 0.05, green: 0.07, blue: 0.08)
    private static let lcd = Color(red: 0.51, green: 0.98, blue: 0.62)
    private static let amber = Color(red: 1.0, green: 0.73, blue: 0.28)
    /// Segments per meter. Eight reads as a level gauge; more would turn back into a plain bar.
    private static let meterBlocks = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            screen
            graduateStrip
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(
            ZStack {
                LinearGradient(colors: [Self.shellTop, Self.shellBottom],
                               startPoint: .top, endPoint: .bottom)
                // The hinge side of the case, so the panel reads as a device and not as a card.
                HStack(spacing: 0) {
                    Color.black.opacity(0.14).frame(width: 5)
                    Spacer(minLength: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        )
        .environment(\.colorScheme, .light)
        .environment(\.locale, content.language.displayLocale)
    }

    private var header: some View {
        HStack(spacing: 6) {
            lens
            ForEach([Color(red: 0.95, green: 0.35, blue: 0.35),
                     Color(red: 0.98, green: 0.82, blue: 0.35),
                     Color(red: 0.45, green: 0.88, blue: 0.5)], id: \.self) { color in
                Circle()
                    .fill(color)
                    .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 6, height: 6)
            }
            Spacer(minLength: 4)
            Text(content.periodLabel().uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.leading, 2)
    }

    private var lens: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(red: 0.72, green: 0.88, blue: 1.0),
                                          Color(red: 0.15, green: 0.45, blue: 0.85)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 11))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .overlay(
                Circle().fill(.white.opacity(0.75)).frame(width: 4, height: 4)
                    .offset(x: -3, y: -3)
            )
            .frame(width: 16, height: 16)
    }

    private var screen: some View {
        let recap = content.recap
        let l = content.l
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(TokenFormatter.compact(recap.total))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Self.lcd)
                Text(l.recapTokensUnit.uppercased())
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Self.lcd.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                deltaChip
            }
            meters
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    readout(l.recapBestDay, recap.bestDay.map { TokenFormatter.compact($0.tokens) } ?? "--")
                    readout(l.recapBestStreak, l.recapDays(recap.bestStreak))
                }
                VStack(alignment: .leading, spacing: 3) {
                    readout(l.recapActiveDays, "\(recap.activeDays)/\(recap.countedDays)")
                    readout(l.recapGraduates, "\(recap.graduated.count)")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Self.screenInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(RadialGradient(colors: [Self.lcd.opacity(0.07), .clear],
                                             center: UnitPoint(x: 0.15, y: 0.1),
                                             startRadius: 0, endRadius: 180))
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.35), lineWidth: 2))
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var deltaChip: some View {
        // No chip unless the ledger covers the whole compared stretch: a fresh install must not
        // claim a jump over days it never saw.
        if let delta = content.recap.delta {
            let up = delta >= 0
            let color = up ? Self.lcd : Self.amber
            Text("\(up ? "▲" : "▼")\(TokenFormatter.percent(abs(delta) * 100))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 2).strokeBorder(color.opacity(0.6), lineWidth: 1))
        }
    }

    private var meters: some View {
        let recap = content.recap
        let peak = max(1, recap.buckets.map(\.tokens).max() ?? 1)
        let labels = content.bucketLabels()
        let spacing: CGFloat = switch content.scope {
        case .week: 6
        case .month: 1.5
        case .year: 4
        }
        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(recap.buckets.enumerated()), id: \.element.key) { index, bucket in
                VStack(spacing: 3) {
                    meter(bucket, peak: peak)
                    // Zero-width frame: a month's "15" is wider than its column and must not
                    // widen it, or five meters would come out fatter than the rest.
                    Text(labels.indices.contains(index) ? labels[index] : "")
                        .font(.system(size: content.scope == .week ? 8 : 7,
                                      weight: bucket.isCurrent ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(bucket.isCurrent ? Self.lcd : Self.lcd.opacity(0.45))
                        .fixedSize()
                        .frame(width: 0, height: 10)
                }
                .frame(maxWidth: .infinity)
                // The meter is plain rectangles, so VoiceOver would otherwise read the label alone.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(content.accessibilityLabel(bucket))
            }
        }
    }

    private func meter(_ bucket: UsageRecap.Bucket, peak: Int) -> some View {
        // A bucket with usage always lights one segment, so "quiet" and "nothing" stay distinct;
        // an unknown bucket (future, or before the ledger started) dims even its unlit grid.
        let lit = bucket.tokens > 0
            ? max(1, Int((Double(bucket.tokens) / Double(peak) * Double(Self.meterBlocks)).rounded()))
            : 0
        return VStack(spacing: 2) {
            ForEach(0..<Self.meterBlocks, id: \.self) { index in
                Rectangle()
                    .fill(index >= Self.meterBlocks - lit
                          ? (bucket.isCurrent ? Self.lcd : Self.lcd.opacity(0.55))
                          : Self.lcd.opacity(bucket.hasData ? 0.09 : 0.035))
                    .frame(height: 4)
            }
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(Self.lcd.opacity(0.5))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Self.lcd)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var graduateStrip: some View {
        HStack(spacing: 5) {
            SpriteView(speciesID: content.companionSpeciesID, size: 18, animated: false,
                       shiny: content.companionShiny, unownForm: content.companionUnownForm)
            Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 14)
            if content.graduates.isEmpty {
                Text(content.l.recapNoGraduates)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(content.graduates, id: \.entry.id) { graduate in
                    HStack(spacing: 2) {
                        SpriteView(speciesID: graduate.entry.finalID, size: 18, animated: false,
                                   shiny: graduate.entry.isShiny,
                                   unownForm: graduate.entry.unownForm)
                            // A badge on the sprite rather than after the name: four chips share
                            // the row, and a trailing sparkle cut "Charizard" to "Chariza…".
                            .overlay(alignment: .topTrailing) {
                                if graduate.entry.isShiny {
                                    Text("✨").font(.system(size: 7)).offset(x: 3, y: -2)
                                }
                            }
                        Text(graduate.name)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.22)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
    }
}

@MainActor
struct RecapScreen: View {
    let store: UsageStore
    let companion: CompanionStore
    let onBack: () -> Void

    @State private var scope: RecapScope = .week
    /// 0 is the running period, -1 the one before it. Never positive: the future has no usage.
    @State private var offset = 0

    var body: some View {
        let l = companion.l
        let content = RecapContent(store: store, companion: companion, scope: scope, offset: offset)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: {
                    Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)   // Esc, like Settings: both take over the popover
                Spacer(minLength: 4)
                Picker(l.recapOpen, selection: $scope) {
                    ForEach(RecapScope.allCases, id: \.self) { Text(l.recapScopeName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .onChange(of: scope) { offset = 0 }
            }
            // The period itself is printed on the card, so this row only moves through time.
            HStack {
                Button { offset -= 1 } label: {
                    Label(l.recapPrevious, systemImage: "arrowtriangle.left.fill").labelStyle(.titleAndIcon)
                }
                .disabled(!content.recap.canGoBack)
                Spacer()
                Button { offset += 1 } label: {
                    HStack(spacing: 4) {
                        Text(l.recapNext)
                        Image(systemName: "arrowtriangle.right.fill")
                    }
                }
                .accessibilityLabel(l.recapNext)
                .disabled(offset >= 0)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            RecapCard(content: content)
            VStack(alignment: .leading, spacing: 2) {
                if let best = content.recap.bestDay {
                    Text(l.recapBestDayLine(content.dayLabel(best.key), TokenFormatter.grouped(best.tokens)))
                }
                if content.recap.isInProgress, content.recap.delta != nil {
                    Text(l.recapCompareSoFar(scope))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(PopoverMetrics.padding)
        .task { await companion.backfillMissingDexNames() }
    }
}
