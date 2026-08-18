#if os(Linux)
import CGtk
import Dispatch
import Foundation

/// Linux entry point — puts usage and the companion Pokémon in the tray (AppIndicator).
/// The popover, floating pet and shop/bag windows arrive in roadmap phases 5–7.
@main
struct PokeTokenBarLinux {
    static func main() {
        // A few one-shot flags so autostart is reachable before the settings window exists
        // (roadmap Phase 7). They call straight into `LoginItem`, so the systemd unit has exactly
        // one definition — a Makefile target writing its own copy would drift from it.
        var openTab: PopoverTab?
        var openWindowAtLaunch = false

        switch CommandLine.arguments.dropFirst().first {
        case "--enable-autostart":  exit(setAutostart(true))
        case "--disable-autostart": exit(setAutostart(false))
        case "--autostart-status":
            print(MainActor.assumeIsolated { LoginItem.isEnabled } ? "enabled" : "disabled")
            exit(0)
        case "--window":
            // Not only a convenience: GNOME ships no tray at all without an extension, so on those
            // desktops this is the only way to reach the window.
            openWindowAtLaunch = true
            openTab = CommandLine.arguments.dropFirst(2).first.flatMap(PopoverTab.init(name:))
        case "--version":
            print(AppVersion.current)
            exit(0)
        case .some(let unknown) where unknown.hasPrefix("-"):
            FileHandle.standardError.write(Data("PokeTokenBar: unknown option \(unknown)\n".utf8))
            exit(2)
        default:
            break   // no arguments: run the tray
        }

        // Keep a subprocess pipe closing early (codex app-server and friends) from killing us —
        // same reason and same position as the macOS AppDelegate.
        signal(SIGPIPE, SIG_IGN)

        // The duplicate-instance guard runs **before** the tray is built. Afterwards, the icon of
        // the instance that yields would flash onto the panel and vanish (macOS puts it ahead of
        // creating the status item for the same reason).
        if SingleInstance.shouldYieldToRunningInstance() {
            AppLog.write("duplicate instance: yielding to the instance already running")
            AppLog.flush()
            exit(0)
        }
        CrashReporter.install(version: AppVersion.current)
        // Must be installed before any store exists: `UsageStore.init` calls
        // `PlatformPowerEvents.observe`, and an observer registered later would never be asked.
        PowerEvents.install()

        guard GtkRuntime.initialize() else {
            // English, not localised: this fires before the companion store (and therefore the
            // language setting) has loaded, and it goes to stderr for someone running the binary
            // from a shell.
            FileHandle.standardError.write(Data(
                "PokeTokenBar: cannot open a display, which the tray requires. Run it inside a GUI session.\n"
                    .utf8))
            exit(1)
        }

        // From here on, MainActor work only runs once the main queue is turning (dispatchMain),
        // so setup is queued too and the loop is handed to dispatchMain last.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { App.shared.start(showingWindow: openWindowAtLaunch, tab: openTab) }
        }
        GtkRuntime.startPumpFromMainQueue()
        dispatchMain()
    }
}

/// Toggle "launch at login" and report the outcome. Returns a process exit code.
private func setAutostart(_ enabled: Bool) -> Int32 {
    MainActor.assumeIsolated {
        do {
            try LoginItem.setEnabled(enabled)
            print("autostart \(enabled ? "enabled" : "disabled")")
            return 0
        } catch {
            FileHandle.standardError.write(Data("PokeTokenBar: \(error)\n".utf8))
            return 1
        }
    }
}

/// One tray item and the polling loop that feeds it.
@MainActor
final class App {
    static let shared = App()

    private let store = UsageStore()
    private let companion = CompanionStore()
    private var tray: TrayIndicator?
    private var popover: PopoverWindow?
    private var settings: SettingsWindow?
    private var pet: FloatingPetWindow?
    /// The sprite key currently on the tray ("<species>-<shiny>") — skip rewrites for the same one.
    private var iconKey: String?

    /// Frames of the current animated sprite, and where in the loop we are. Empty means the
    /// companion has no animated sprite (only Gen-V mons do) and the static icon stands.
    private var animationFrames: [SpriteRenderer.Frame] = []
    private var animationIndex = 0
    /// Bumped whenever the subject changes, so a timer belonging to the previous species stops
    /// instead of cycling frames of a Pokémon that is no longer the companion.
    private var animationGeneration = 0
    /// Paused while the screen is off — see PlatformPowerEvents.
    private var animationPaused = false

    func start(showingWindow: Bool = false, tab: PopoverTab? = nil) {
        let iconDirectory = PlatformPaths.appDirectory("tray")
        // Start from a system-theme icon: sprites are fetched over the network, so on a first run
        // or offline there is none yet. Some panels do not draw a blank for a missing icon name —
        // they hide the item entirely. So begin with a name that certainly exists and swap later.
        // Menu text follows the app's language setting. Hardcoding it would leave the language
        // preference half-working — applying everywhere except the tray. (A fresh install defaults
        // to the system locale: `AppLanguage.systemDefault`.)
        let l = L(companion.language)
        PopoverStyle.install()
        popover = PopoverWindow(store: store, companion: companion, onClose: {})
        let settingsWindow = SettingsWindow(store: store, companion: companion)
        settingsWindow.onLanguageChange = { [weak self] in self?.relabel() }
        settingsWindow.onFloatingPetChange = { [weak self] in self?.syncFloatingPet() }
        settings = settingsWindow
        pet = FloatingPetWindow(store: store, companion: companion) { [weak self] in
            self?.popover?.show()
            guard let self else { return }
            Task { @MainActor in await self.popover?.loadSpritesAndRefresh() }
        }
        let tray = TrayIndicator(
            id: "poketokenbar", iconThemePath: iconDirectory.path, iconName: "applications-games",
            summaryPlaceholder: l.loading)
        self.tray = tray

        tray.addItem(l.openWindow, localized: { $0.openWindow }) { [weak self] in
            guard let self else { return }
            self.popover?.show()
            Task { @MainActor in await self.popover?.loadSpritesAndRefresh() }
        }
        tray.addItem(l.refreshNow, localized: { $0.refreshNow }) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        tray.addItem(l.settings, localized: { $0.settings }) { [weak self] in
            self?.settings?.show()
        }
        tray.addItem(l.showLogFile, localized: { $0.showLogFile }) {
            PlatformOpener.reveal(AppLog.logFileURL)
        }
        tray.appendSeparator()
        tray.addItem(l.quit, localized: { $0.quit }) {
            CrashReporter.markClean()
            AppLog.flush()
            exit(0)
        }

        store.localizationLanguage = companion.language
        store.onRefresh = { [weak self] in self?.onStoreRefreshed() }
        // The store pauses its own polling; the tray animation is ours to pause. Leaving a sprite
        // cycling at 2.5fps against a blanked screen is exactly the idle drain the frame floor exists
        // to avoid.
        PlatformPowerEvents.observe(
            onWake: {},
            onScreenSleep: { [weak self] in self?.animationPaused = true },
            onScreenWake: { [weak self] in self?.animationPaused = false })

        syncFloatingPet()
        if showingWindow {
            popover?.show()
            if let tab { popover?.select(tab) }
        }
        Task { @MainActor in await refresh() }
        schedulePolling()
    }

    /// Show or hide the desktop pet to match the setting, and give it the current sprite.
    private func syncFloatingPet() {
        pet?.setVisible(store.floatingPetEnabled)
        guard store.floatingPetEnabled else { return }
        let key = companion.currentSpeciesID.map { "\($0)-\(companion.currentIsShiny)" } ?? "egg"
        Task { @MainActor in
            let data: Data?
            if let species = companion.currentSpeciesID {
                data = await SpriteStore.shared.data(
                    speciesID: species, animated: false, shiny: companion.currentIsShiny)
            } else {
                data = await SpriteStore.shared.eggData()
            }
            pet?.update(spriteData: data, key: key)
        }
    }

    /// Feed the refreshed usage into the companion, then hand out candy while the limits are fresh.
    ///
    /// **This is what makes the egg hatch.** `UsageStore` only counts tokens; the companion learns
    /// about them solely through `update(...)`. Without this hook the app reports usage perfectly
    /// and the companion never progresses — the hatch counter sits at its starting value forever,
    /// which is exactly how it behaved before this existed.
    private func onStoreRefreshed() {
        updateCompanion()
        companion.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        applyState()
    }

    private func updateCompanion() {
        companion.update(
            todayTokensByProvider: store.todayTokensByProvider,
            todayDate: LocalUsageReader.todayKey(),
            monthTotal: store.monthTotalTokens,
            burnTier: store.burnTier,
            limitWarning: store.isLimitWarning,
            hasUsageData: store.hasUsageData)
    }

    /// Re-apply every label after a language change. The tray menu is built once at startup, so
    /// without this the popover would switch language while the menu stayed on the old one.
    private func relabel() {
        store.localizationLanguage = companion.language
        tray?.relabel(companion.l)
        applyState()
        Task { @MainActor in await popover?.loadSpritesAndRefresh() }
    }

    /// One usage refresh. The polling interval follows `store.refreshInterval` (a user setting).
    private func refresh() async {
        await store.refresh()
        // `store.onRefresh` already fed the companion; hatching is checked afterwards so a refresh
        // that crosses the threshold hatches in the same tick rather than one poll later.
        await companion.hatchIfNeeded()
        applyState()
        await updateIcon()
        syncFloatingPet()
        // Only rebuilds when the window is actually up (see PopoverWindow.refresh).
        await popover?.loadSpritesAndRefresh()
    }

    private func schedulePolling() {
        DispatchQueue.main.asyncAfter(deadline: .now() + store.refreshInterval) {
            Task { @MainActor in
                await self.refresh()
                self.schedulePolling()   // schedule after completion so polls cannot pile up
            }
        }
    }

    private func applyState() {
        // macOS stacks several lines vertically in the menu bar; an SNI label is a single line,
        // so they are joined with " / ".
        tray?.setUsageText(store.menuLines.joined(separator: " / "))
    }

    /// Put the companion sprite on the tray. Does nothing while the subject is unchanged, to
    /// avoid pointless disk writes.
    ///
    /// Before the first hatch there is no species, and the subject is the egg — the same thing the
    /// macOS menu bar shows. Returning early on a nil species instead would leave a fresh install
    /// sitting on the placeholder system icon, which reads as "the app is broken" rather than
    /// "your egg has not hatched yet".
    private func updateIcon() async {
        let key: String
        let data: Data?
        if let speciesID = companion.currentSpeciesID {
            let shiny = companion.currentIsShiny
            key = "\(speciesID)-\(shiny)"
            guard key != iconKey else { return }
            data = await SpriteStore.shared.data(
                speciesID: speciesID, animated: false, shiny: shiny)
        } else {
            key = "egg"
            guard key != iconKey else { return }
            data = await SpriteStore.shared.eggData()
        }
        guard let data else { return }

        // AppIndicator takes a **theme path plus a name**, not an image. Some panels keep using a
        // cached pixmap when the same name is overwritten, so the key goes into the name and every
        // change produces a fresh one.
        let directory = PlatformPaths.appDirectory("tray")
        let name = "companion-\(key)"
        let file = directory.appendingPathComponent("\(name).png")
        guard SpriteRenderer.write(data, to: file) else { return }
        tray?.setIcon(named: name)
        iconKey = key

        // The static icon goes up first so something is showing immediately; the animated sprite is
        // a second download and only exists for Gen-V species.
        animationFrames = []
        animationGeneration += 1
        guard let speciesID = companion.currentSpeciesID,
              PokemonAssets.hasAnimatedSprite(speciesID: speciesID),
              let gif = await SpriteStore.shared.data(
                speciesID: speciesID, animated: true, shiny: companion.currentIsShiny)
        else { return }
        let frames = SpriteRenderer.writeFrames(gif, directory: directory, prefix: name)
        guard frames.count > 1 else { return }
        animationFrames = frames
        animationIndex = 0
        scheduleAnimationTick(generation: animationGeneration)
    }

    /// Advance the tray sprite one frame, then schedule the next.
    ///
    /// A self-rescheduling timer rather than a fixed-interval one, because GIF frames have
    /// individual delays. `generation` makes a stale chain die on its own once the subject changes.
    private func scheduleAnimationTick(generation: Int) {
        guard generation == animationGeneration, animationFrames.count > 1 else { return }
        let frame = animationFrames[animationIndex % animationFrames.count]
        let delay = SpriteAnimationPolicy.frameDelay(
            base: frame.delay, floor: SpriteAnimationPolicy.idleFrameFloor)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.animationGeneration else { return }
                guard !self.animationPaused else {
                    // Keep the chain alive but idle, so it resumes without re-extracting frames.
                    self.scheduleAnimationTick(generation: generation)
                    return
                }
                self.animationIndex += 1
                let next = self.animationFrames[self.animationIndex % self.animationFrames.count]
                self.tray?.setIcon(named: next.name)
                self.scheduleAnimationTick(generation: generation)
            }
        }
    }
}
#endif   // os(Linux)
