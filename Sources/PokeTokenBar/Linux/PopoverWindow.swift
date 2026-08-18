#if os(Linux)
import CGtk
import Foundation

/// The main window — the Linux stand-in for the macOS popover.
///
/// It is a real window rather than a popover attached to the tray icon, because Wayland gives an
/// application no way to position a surface next to a panel item it does not own. So it opens
/// centred and stays on top; that is the closest honest equivalent.
///
/// Content is **rebuilt wholesale** on each refresh instead of diffed. The panel is a few dozen
/// labels refreshed every couple of minutes, so rebuilding costs nothing measurable and removes a
/// whole class of bug where a stale widget keeps showing an old number.
@MainActor
final class PopoverWindow {
    private let store: UsageStore
    private let companion: CompanionStore
    private let window: Widget
    private let stack: Widget
    private let pages: [PopoverTab: Widget]
    private var isVisible = false

    /// Which provider's breakdown is expanded. nil = the first one.
    private var selectedProviderID: String?

    /// How many dex entries are drawn. The macOS Collection paginates; this caps the sprite
    /// prefetch so a large dex does not fire hundreds of requests when the window opens.
    private let dexPageSize = 60

    /// Celebration currently on screen, and the sequence it came from. Held rather than read
    /// straight off the store because the store's copy is consumed as soon as it is shown, while
    /// the banner has to survive the rebuilds that tab switches and refreshes cause.
    private var activeCelebration: String?
    private var seenCelebrationSeq = -1

    /// Live animation for the Home sprite: the frames, where we are, and a generation counter that
    /// retires the timer when the subject changes. Pixbufs are owned here and unref'd on replace.
    private var animationFrames: [(pixbuf: OpaquePointer, delay: TimeInterval)] = []
    private var animationIndex = 0
    private var animationGeneration = 0
    private var animationImage: Widget?

    /// Sprite bytes already fetched, keyed by "<species>-<shiny>" — avoids re-downloading on every
    /// rebuild, which would otherwise hit the network once per refresh tick.
    private var spriteCache: [String: Data] = [:]

    init(store: UsageStore, companion: CompanionStore, onClose: @escaping () -> Void) {
        self.store = store
        self.companion = companion

        window = gtk_window_new(GTK_WINDOW_TOPLEVEL)!
        gtk_window_set_title(asWindow(window), "PokeTokenBar")
        gtk_window_set_default_size(asWindow(window), 400, 620)
        gtk_window_set_keep_above(asWindow(window), 1)
        gtk_window_set_position(asWindow(window), GTK_WIN_POS_CENTER)

        let root = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 8)
        Gtk.margins(root, top: 10, bottom: 10, start: 10, end: 10)
        gtk_container_add(asContainer(window), root)

        stack = gtk_stack_new()!
        let switcher = gtk_stack_switcher_new()!
        gtk_stack_switcher_set_stack(
            UnsafeMutableRawPointer(switcher).assumingMemoryBound(to: GtkStackSwitcher.self),
            asStack(stack))
        gtk_widget_set_halign(switcher, GTK_ALIGN_CENTER)
        Gtk.pack(root, switcher)

        var built: [PopoverTab: Widget] = [:]
        let l = companion.l
        for (tab, title) in [(PopoverTab.home, l.home), (.shop, l.shop), (.bag, l.bag),
                             (.collection, l.collection)] {
            let page = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 10)
            let scroller = gtk_scrolled_window_new(nil, nil)!
            gtk_scrolled_window_set_policy(
                UnsafeMutableRawPointer(scroller).assumingMemoryBound(to: GtkScrolledWindow.self),
                GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
            gtk_container_add(asContainer(scroller), page)
            gtk_stack_add_titled(asStack(stack), scroller, tab.identifier, title)
            built[tab] = page
        }
        pages = built
        Gtk.pack(root, stack, expand: true)

        // Closing must hide, not destroy: the tray outlives the window, and destroying it would
        // leave every later `show()` pointing at freed widgets. Returning true stops GTK's default
        // destroy handler.
        let box = GtkCallbackBox { [weak self] in
            self?.hide()
            onClose()
        }
        gtkConnectDeleteEvent(UnsafeMutableRawPointer(window), box: box)
    }

    // MARK: visibility

    var visible: Bool { isVisible }

    func toggle() { isVisible ? hide() : show() }

    /// Switch tabs programmatically. Used by `--window <tab>`; the switcher drives it otherwise.
    func select(_ tab: PopoverTab) {
        gtk_stack_set_visible_child_name(asStack(stack), tab.identifier)
    }

    func show() {
        isVisible = true
        GtkRuntime.hasVisibleWindow = true
        refresh()
        gtk_widget_show_all(window)
        gtk_window_present(asWindow(window))
    }

    func hide() {
        isVisible = false
        GtkRuntime.hasVisibleWindow = false
        gtk_widget_hide(window)
    }

    /// Rebuild whatever is on screen. Cheap enough to call on every poll (see the type doc).
    func refresh() {
        guard isVisible else { return }
        let l = companion.l
        captureCelebrationIfNeeded(l)
        for (tab, page) in pages {
            Gtk.clear(page)
            switch tab {
            case .home:       buildHome(into: page)
            case .shop:       buildShop(into: page, l)
            case .bag:        buildBag(into: page, l)
            case .collection: buildCollection(into: page, l)
            }
        }
        gtk_widget_show_all(window)
    }

    /// Pull the sprites the visible tab needs, then rebuild. Async because the first paint may have
    /// to download them.
    func loadSpritesAndRefresh() async {
        await cacheCompanionSprite()
        for kind in ItemKind.allCases { await cacheItemSprite(kind) }
        for item in companion.lineNodes {
            if case .species(let speciesID) = item.content {
                await cacheSprite(speciesID: speciesID, shiny: companion.currentIsShiny)
            }
        }
        for entry in companion.dexEntriesSorted.prefix(dexPageSize) {
            await cacheSprite(speciesID: entry.finalID, shiny: entry.isShiny)
        }
        refresh()
    }

    private func cacheCompanionSprite() async {
        if let subject = companion.currentSpeciesID {
            await cacheSprite(speciesID: subject, shiny: companion.currentIsShiny)
        } else if spriteCache["egg"] == nil {
            spriteCache["egg"] = await SpriteStore.shared.eggData()
        }
    }

    private func cacheSprite(speciesID: Int, shiny: Bool) async {
        let key = "\(speciesID)-\(shiny)"
        guard spriteCache[key] == nil else { return }
        spriteCache[key] = await SpriteStore.shared.data(
            speciesID: speciesID, animated: false, shiny: shiny)
    }

    private func cacheItemSprite(_ kind: ItemKind) async {
        guard let name = kind.spriteName else { return }   // no sprite upstream: emoji fallback
        let key = "item-\(name)"
        guard spriteCache[key] == nil else { return }
        spriteCache[key] = await SpriteStore.shared.data(itemName: name)
    }

    /// A pixbuf image widget for a cached sprite, or nil if it has not arrived yet.
    private func spriteImage(_ key: String, size: Int) -> Widget? {
        guard let data = spriteCache[key], let pixbuf = SpriteRenderer.render(data, size: size)
        else { return nil }
        let image = gtk_image_new_from_pixbuf(pixbuf)!
        g_object_unref(UnsafeMutableRawPointer(pixbuf))
        return image
    }

    /// An item's sprite, falling back to its emoji — the same fallback the macOS shop uses when
    /// PokéAPI has no artwork (mints are Gen-8 and simply absent).
    private func itemIcon(_ kind: ItemKind, size: Int) -> Widget {
        if let name = kind.spriteName, let image = spriteImage("item-\(name)", size: size) {
            return image
        }
        let label = Gtk.label("<span size='x-large'>\(Gtk.escape(kind.fallbackEmoji))</span>")
        gtk_widget_set_valign(label, GTK_ALIGN_CENTER)
        return label
    }

    /// Take a newly fired celebration for display, exactly once.
    ///
    /// Keyed on `celebrationSeq` rather than on the optional itself, the way the macOS header does
    /// it: consuming the store's copy immediately would otherwise let the same event replay every
    /// time the panel rebuilt.
    private func captureCelebrationIfNeeded(_ l: L) {
        guard let celebration = companion.celebration,
              companion.celebrationSeq != seenCelebrationSeq else { return }
        seenCelebrationSeq = companion.celebrationSeq
        let name = companion.displayName
        switch celebration {
        case .hatch(let shiny):
            activeCelebration = "\(shiny ? l.notifShinyHatchTitle : l.notifHatchTitle)\n\(l.notifHatchBody(name))"
        case .evolve:
            activeCelebration = "\(l.notifEvolveTitle)\n\(l.notifEvolveBody(name))"
        case .dittoReveal(let shiny):
            activeCelebration = shiny ? l.notifShinyDittoRevealTitle : l.notifDittoRevealTitle
        }
        companion.consumeCelebration()

        // Self-clearing: a congratulation still sitting there an hour later reads as stale UI.
        let shown = seenCelebrationSeq
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.seenCelebrationSeq == shown else { return }
                self.activeCelebration = nil
                self.refresh()
            }
        }
    }

    private func celebrationBanner(_ text: String) -> Widget {
        let banner = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 2)
        Gtk.addClass(banner, "ptb-card")
        Gtk.addClass(banner, "ptb-celebration")
        let label = Gtk.label("<b>\(Gtk.escape(text))</b>", align: GTK_ALIGN_CENTER, wrap: true)
        gtk_label_set_justify(asLabel(label), GTK_JUSTIFY_CENTER)
        Gtk.pack(banner, label)
        return banner
    }

    // MARK: companion animation

    /// Animate the Home sprite if this species has a Gen-V animated sprite.
    ///
    /// The popover runs at the sprite's native rate (floor 0), unlike the tray: this surface only
    /// exists while someone is looking at it, so the idle-wakeup argument that caps the tray at
    /// 2.5fps does not apply here (`SpriteAnimationPolicy`).
    private func startAnimation(on image: Widget, key: String) {
        animationGeneration += 1
        releaseAnimationFrames()
        animationImage = image
        animationIndex = 0

        guard let speciesID = companion.currentSpeciesID,
              PokemonAssets.hasAnimatedSprite(speciesID: speciesID) else { return }
        let generation = animationGeneration
        let shiny = companion.currentIsShiny
        Task { @MainActor in
            guard let gif = await SpriteStore.shared.data(
                speciesID: speciesID, animated: true, shiny: shiny),
                  generation == self.animationGeneration else { return }
            let frames = SpriteRenderer.renderFrames(gif, size: 72)
            guard frames.count > 1, generation == self.animationGeneration else {
                for frame in frames { g_object_unref(UnsafeMutableRawPointer(frame.pixbuf)) }
                return
            }
            self.animationFrames = frames
            self.scheduleFrame(generation: generation)
        }
    }

    private func scheduleFrame(generation: Int) {
        guard generation == animationGeneration, animationFrames.count > 1, isVisible else { return }
        let frame = animationFrames[animationIndex % animationFrames.count]
        DispatchQueue.main.asyncAfter(deadline: .now() + max(frame.delay, 0.02)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.animationGeneration, self.isVisible,
                      let image = self.animationImage else { return }
                self.animationIndex += 1
                let next = self.animationFrames[self.animationIndex % self.animationFrames.count]
                gtk_image_set_from_pixbuf(asImage(image), next.pixbuf)
                self.scheduleFrame(generation: generation)
            }
        }
    }

    /// Frames are owned here, so replacing them has to unref the old ones or the pixbufs leak —
    /// a species change every few minutes would otherwise accumulate megabytes over a long session.
    private func releaseAnimationFrames() {
        for frame in animationFrames { g_object_unref(UnsafeMutableRawPointer(frame.pixbuf)) }
        animationFrames = []
    }

    // MARK: Shop

    private func buildShop(into page: Widget, _ l: L) {
        let wallet = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 2)
        Gtk.addClass(wallet, "ptb-card")
        let caption = Gtk.label(Gtk.escape(l.shop))
        Gtk.addClass(caption, "ptb-section")
        Gtk.pack(wallet, caption)
        Gtk.pack(wallet, Gtk.label(
            "<span size='large'><b>\(Gtk.escape(TokenFormatter.compact(companion.availableTokens)))</b></span>"))
        let hint = Gtk.label("<span size='small'>\(Gtk.escape(l.shopHint))</span>", wrap: true)
        Gtk.addClass(hint, "ptb-muted")
        Gtk.pack(wallet, hint)
        Gtk.pack(page, wallet)

        for entry in companion.shopEntries {
            Gtk.pack(page, shopRow(entry, l))
        }
    }

    private func shopRow(_ entry: ShopEntry, _ l: L) -> Widget {
        let row = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 10)
        Gtk.addClass(row, "ptb-card")

        let title: String
        let subtitle: String
        let affordable: Bool
        let alreadyOwned: Bool
        switch entry {
        case .item(let kind):
            Gtk.pack(row, itemIcon(kind, size: 32))
            title = l.itemName(kind)
            subtitle = l.itemDescription(kind)
            affordable = companion.canBuy(kind)
            alreadyOwned = kind.isPassive && companion.itemCount(kind) > 0
        case .egg(let tier):
            let icon = spriteImage("egg", size: 32) ?? Gtk.label("<span size='x-large'>🥚</span>")
            Gtk.pack(row, icon)
            title = l.eggName(tier)
            subtitle = l.shopHint
            affordable = companion.canBuyEgg(tier)
            alreadyOwned = false
        }

        let text = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 2)
        gtk_widget_set_valign(text, GTK_ALIGN_CENTER)
        Gtk.pack(text, Gtk.label("<b>\(Gtk.escape(title))</b>"))
        let desc = Gtk.label("<span size='small'>\(Gtk.escape(subtitle))</span>", wrap: true)
        Gtk.addClass(desc, "ptb-muted")
        Gtk.pack(text, desc)
        let price = Gtk.label(
            "<span size='small'>\(Gtk.escape(l.shopPriceLabel)) \(Gtk.escape(TokenFormatter.compact(entry.price)))</span>")
        Gtk.addClass(price, "ptb-muted")
        Gtk.pack(text, price)
        Gtk.pack(row, text, expand: true)

        if alreadyOwned {
            let owned = Gtk.label("<span size='small'>\(Gtk.escape(l.ownedAlready))</span>")
            gtk_widget_set_valign(owned, GTK_ALIGN_CENTER)
            Gtk.pack(row, owned)
            return row
        }

        let button = gtk_button_new_with_label(l.buy)!
        gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
        // Insufficient balance disables the button rather than hiding it, so the price stays
        // legible as a goal instead of the row silently losing its action.
        gtk_widget_set_sensitive(button, affordable ? 1 : 0)
        gtkConnect(UnsafeMutableRawPointer(button), signal: "clicked",
                   box: GtkCallbackBox { [weak self] in
                       guard let self else { return }
                       switch entry {
                       case .item(let kind): _ = self.companion.buy(kind)
                       case .egg(let tier):  _ = self.companion.buyEgg(tier)
                       }
                       Task { @MainActor in await self.loadSpritesAndRefresh() }
                   })
        Gtk.pack(row, button)
        return row
    }

    // MARK: Bag

    private func buildBag(into page: Widget, _ l: L) {
        let owned = companion.ownedItems
        guard !owned.isEmpty else {
            let empty = Gtk.label("<b>\(Gtk.escape(l.bagEmptyTitle))</b>", align: GTK_ALIGN_CENTER)
            Gtk.margins(empty, top: 24)
            Gtk.pack(page, empty)
            return
        }
        for (kind, count) in owned {
            Gtk.pack(page, bagRow(kind, count, l))
        }
    }

    private func bagRow(_ kind: ItemKind, _ count: Int, _ l: L) -> Widget {
        let row = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 10)
        Gtk.addClass(row, "ptb-card")
        Gtk.pack(row, itemIcon(kind, size: 32))

        let text = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 2)
        gtk_widget_set_valign(text, GTK_ALIGN_CENTER)
        Gtk.pack(text, Gtk.label("<b>\(Gtk.escape(l.itemName(kind)))</b>"))
        let countLabel = Gtk.label("<span size='small'>\(Gtk.escape(l.ownedCount(count)))</span>")
        Gtk.addClass(countLabel, "ptb-muted")
        Gtk.pack(text, countLabel)
        Gtk.pack(row, text, expand: true)

        // Passive items apply just by being owned — there is nothing to press, so no button.
        guard !kind.isPassive else {
            let applied = Gtk.label("<span size='small'>\(Gtk.escape(l.ownedAlready))</span>")
            gtk_widget_set_valign(applied, GTK_ALIGN_CENTER)
            Gtk.pack(row, applied)
            return row
        }

        let button = gtk_button_new_with_label(l.useItem)!
        gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
        // Consumables need something to act on; before the first hatch there is no companion.
        gtk_widget_set_sensitive(button, companion.hasActive ? 1 : 0)
        gtk_widget_set_tooltip_text(button, companion.hasActive ? nil : l.useAfterHatch)
        gtkConnect(UnsafeMutableRawPointer(button), signal: "clicked",
                   box: GtkCallbackBox { [weak self] in
                       guard let self else { return }
                       switch kind {
                       case .rareCandy: _ = self.companion.useRareCandy()
                       case .mint:      _ = self.companion.useMint()
                       case .shinyCharm: break   // passive; handled above
                       }
                       Task { @MainActor in await self.loadSpritesAndRefresh() }
                   })
        Gtk.pack(row, button)
        return row
    }

    // MARK: Collection

    private func buildCollection(into page: Widget, _ l: L) {
        let entries = companion.dexEntriesSorted
        guard !entries.isEmpty else {
            let empty = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 6)
            Gtk.margins(empty, top: 24)
            Gtk.pack(empty, Gtk.label("<b>\(Gtk.escape(l.dexEmptyTitle))</b>", align: GTK_ALIGN_CENTER))
            let hint = Gtk.label("<span size='small'>\(Gtk.escape(l.dexEmptyHint))</span>",
                                 align: GTK_ALIGN_CENTER)
            Gtk.addClass(hint, "ptb-muted")
            Gtk.pack(empty, hint)
            Gtk.pack(page, empty)
            return
        }

        let counts = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        for rarity in [Rarity.common, .uncommon, .rare, .legendary] {
            let count = companion.dexCount(rarity)
            guard count > 0 else { continue }
            let chip = Gtk.label(
                "<span size='small'>\(Gtk.escape(rarity.rawValue)) <b>\(count)</b></span>")
            Gtk.addClass(chip, "ptb-chip")
            Gtk.pack(counts, chip)
        }
        Gtk.pack(page, counts)

        // A flow grid keeps the sprites in rows that reflow with the window, which is closer to the
        // macOS dex than a single long column.
        let grid = gtk_flow_box_new()!
        let flowBox = UnsafeMutableRawPointer(grid).assumingMemoryBound(to: GtkFlowBox.self)
        gtk_flow_box_set_selection_mode(flowBox, GTK_SELECTION_NONE)
        gtk_flow_box_set_max_children_per_line(flowBox, 4)
        gtk_flow_box_set_homogeneous(flowBox, 1)
        for entry in entries.prefix(dexPageSize) {
            gtk_container_add(asContainer(grid), dexCell(entry))
        }
        Gtk.pack(page, grid)

        if entries.count > dexPageSize {
            // Say what is not shown. Silently truncating a collection reads as data loss.
            let more = Gtk.label(
                "<span size='small'>+\(entries.count - dexPageSize)</span>", align: GTK_ALIGN_CENTER)
            Gtk.addClass(more, "ptb-muted")
            Gtk.pack(page, more)
        }
    }

    private func dexCell(_ entry: DexEntry) -> Widget {
        let cell = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 2)
        Gtk.addClass(cell, "ptb-card")
        let key = "\(entry.finalID)-\(entry.isShiny)"
        if let image = spriteImage(key, size: 56) {
            Gtk.pack(cell, image)
        }
        let name = companion.dexStoredChainNames(entry)?[entry.finalID]
            ?? "#\(entry.finalID)"
        var markup = "<span size='small'>\(Gtk.escape(name))</span>"
        if entry.isShiny { markup = "✨ " + markup }
        let label = Gtk.label(markup, align: GTK_ALIGN_CENTER)
        Gtk.pack(cell, label)
        return cell
    }

    // MARK: Home

    private func buildHome(into page: Widget) {
        let l = companion.l
        if let celebration = activeCelebration { Gtk.pack(page, celebrationBanner(celebration)) }
        Gtk.pack(page, companionCard(l))
        Gtk.pack(page, totalsCard(l))
        if let line = evolutionLine() { Gtk.pack(page, line) }
        if !store.snapshots.isEmpty { Gtk.pack(page, providerCard(l)) }
        if let limits = store.limits { Gtk.pack(page, limitsCard(l, limits)) }
        if store.snapshots.isEmpty {
            Gtk.pack(page, Gtk.label("<span size='small'>\(Gtk.escape(l.dexEmptyHint))</span>",
                                     align: GTK_ALIGN_CENTER))
        }
    }

    /// Sprite + name + rarity + progress, matching the macOS home header.
    private func companionCard(_ l: L) -> Widget {
        let card = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 12)
        Gtk.addClass(card, "ptb-card")

        let key = companion.currentSpeciesID.map { "\($0)-\(companion.currentIsShiny)" } ?? "egg"
        if let data = spriteCache[key], let pixbuf = SpriteRenderer.render(data, size: 72) {
            let image = gtk_image_new_from_pixbuf(pixbuf)!
            g_object_unref(UnsafeMutableRawPointer(pixbuf))
            gtk_widget_set_valign(image, GTK_ALIGN_CENTER)
            Gtk.pack(card, image)
            // The static frame goes up first so the row never appears empty, then the animation
            // takes over the same widget if this species has one.
            startAnimation(on: image, key: key)
        }

        let text = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 4)
        gtk_widget_set_valign(text, GTK_ALIGN_CENTER)

        let heading = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        Gtk.pack(heading, Gtk.label("<span size='large'><b>\(Gtk.escape(companion.displayName))</b></span>"))
        if let rarity = companion.rarity {
            let badge = Gtk.label(Gtk.escape(rarity.rawValue.uppercased()))
            Gtk.addClass(badge, "ptb-badge")
            gtk_widget_set_valign(badge, GTK_ALIGN_CENTER)
            Gtk.pack(heading, badge)
        }
        Gtk.pack(text, heading)

        // Egg and hatched companion track different quantities, so the subtitle, the meter and the
        // remaining-amount line all switch together.
        let stage = companion.isEgg ? l.eggIncubating
            : (companion.isFinalStage ? l.finalForm : companion.stageText)
        let stageLabel = Gtk.label("<span size='small'>\(Gtk.escape(stage))</span>")
        Gtk.addClass(stageLabel, "ptb-muted")
        Gtk.pack(text, stageLabel)

        let fraction = companion.isEgg ? companion.eggProgress : companion.progress
        Gtk.pack(text, Gtk.meter(fraction: fraction))

        let remaining = companion.isEgg
            ? l.eggToHatch(TokenFormatter.compact(companion.eggTokensToHatch))
            : l.toGraduation(TokenFormatter.compact(companion.tokensToNext))
        let remainingLabel = Gtk.label("<span size='small'>\(Gtk.escape(remaining))</span>")
        Gtk.addClass(remainingLabel, "ptb-muted")
        Gtk.pack(text, remainingLabel)

        let status = Gtk.label("<span size='small'>\(Gtk.escape(companion.statusLine))</span>", wrap: true)
        Gtk.addClass(status, "ptb-muted")
        Gtk.pack(text, status)

        Gtk.pack(card, text, expand: true)
        return card
    }

    /// The evolution line: what this companion has been, is, and can still become.
    ///
    /// Stages already passed are shown at full strength, the current one is ringed, and future ones
    /// are dimmed — an unresolved branch is a "?" because the line genuinely is not decided yet.
    /// Returns nil for an egg, which has no line to show.
    private func evolutionLine() -> Widget? {
        let items = companion.lineNodes
        guard items.count > 1 else { return nil }
        let row = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        Gtk.addClass(row, "ptb-card")
        gtk_widget_set_halign(row, GTK_ALIGN_CENTER)

        for (index, item) in items.enumerated() {
            if index > 0 {
                let arrow = Gtk.label("<span size='small'>→</span>")
                Gtk.addClass(arrow, "ptb-muted")
                gtk_widget_set_valign(arrow, GTK_ALIGN_CENTER)
                Gtk.pack(row, arrow)
            }
            let cell: Widget
            switch item.content {
            case .species(let speciesID):
                let key = "\(speciesID)-\(companion.currentIsShiny)"
                cell = spriteImage(key, size: 40) ?? Gtk.label("<span size='small'>#\(speciesID)</span>")
            case .mystery:
                cell = Gtk.label("<span size='large'>?</span>")
            }
            switch item.state {
            case .current: Gtk.addClass(cell, "ptb-stage-current")
            case .future:  Gtk.addClass(cell, "ptb-stage-future")
            case .done:    break
            }
            Gtk.pack(row, cell)
        }
        return row
    }

    /// Today's total, with week and month beneath it.
    private func totalsCard(_ l: L) -> Widget {
        let card = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 4)
        Gtk.addClass(card, "ptb-card")

        let caption = Gtk.label(Gtk.escape(l.todayTokens))
        Gtk.addClass(caption, "ptb-section")
        Gtk.pack(card, caption)

        let headline = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        let big = Gtk.label("<b>\(Gtk.escape(TokenFormatter.compact(store.todayTotalTokens)))</b>")
        Gtk.addClass(big, "ptb-huge")
        Gtk.pack(headline, big)

        // The exact figure sits next to the abbreviated one, as on macOS — "319.9M" is for glancing,
        // the grouped number is for anyone reconciling against a bill.
        let exact = Gtk.label("<span size='small'>\(Gtk.escape(TokenFormatter.grouped(store.todayTotalTokens)))</span>")
        Gtk.addClass(exact, "ptb-muted")
        gtk_widget_set_valign(exact, GTK_ALIGN_END)
        Gtk.pack(headline, exact)

        if store.showsCost {
            let cost = Gtk.label("<span size='small'>\(Gtk.escape(TokenFormatter.cost(store.todayCostTotal)))</span>")
            Gtk.addClass(cost, "ptb-muted")
            gtk_widget_set_valign(cost, GTK_ALIGN_END)
            gtk_widget_set_hexpand(cost, 1)
            gtk_widget_set_halign(cost, GTK_ALIGN_END)
            Gtk.pack(headline, cost, expand: true)
        }
        Gtk.pack(card, headline)

        let periods = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 16)
        Gtk.pack(periods, periodLabel(l.thisWeek, store.weekTotalTokens, store.weekCostTotal))
        Gtk.pack(periods, periodLabel(l.thisMonth, store.monthTotalTokens, store.monthCostTotal))
        Gtk.pack(card, periods)
        return card
    }

    private func periodLabel(_ title: String, _ tokens: Int, _ cost: Double) -> Widget {
        var markup = "<span size='small'>\(Gtk.escape(title)) <b>\(Gtk.escape(TokenFormatter.compact(tokens)))</b>"
        if store.showsCost { markup += " \(Gtk.escape(TokenFormatter.cost(cost)))" }
        markup += "</span>"
        let label = Gtk.label(markup)
        Gtk.addClass(label, "ptb-muted")
        return label
    }

    /// Provider chips plus the selected provider's token breakdown.
    private func providerCard(_ l: L) -> Widget {
        let card = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 8)
        Gtk.addClass(card, "ptb-card")

        let chips = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        let selected = selectedProviderID ?? store.snapshots.first?.providerID
        for snapshot in store.snapshots {
            let button = gtk_button_new_with_label(snapshot.displayName)!
            Gtk.addClass(button, "ptb-chip")
            if snapshot.providerID == selected { Gtk.addClass(button, "ptb-chip-on") }
            gtk_button_set_relief(
                UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self),
                GTK_RELIEF_NONE)
            let id = snapshot.providerID
            gtkConnect(UnsafeMutableRawPointer(button), signal: "clicked",
                       box: GtkCallbackBox { [weak self] in
                           self?.selectedProviderID = id
                           self?.refresh()
                       })
            Gtk.pack(chips, button)
        }
        Gtk.pack(card, chips)

        guard let snapshot = store.snapshots.first(where: { $0.providerID == selected }),
              let today = snapshot.today
        else { return card }

        let heading = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        Gtk.pack(heading, Gtk.label("<b>\(Gtk.escape(snapshot.displayName))</b>"))
        let total = Gtk.label("<b>\(Gtk.escape(TokenFormatter.compact(today.totalTokens)))</b>")
        gtk_widget_set_hexpand(total, 1)
        gtk_widget_set_halign(total, GTK_ALIGN_END)
        Gtk.pack(heading, total, expand: true)
        if snapshot.reportsCost {
            Gtk.pack(heading, Gtk.label("<span size='small'>\(Gtk.escape(TokenFormatter.cost(today.totalCost)))</span>"))
        }
        Gtk.pack(card, heading)

        let parts = [
            ("in", today.inputTokens), ("out", today.outputTokens),
            ("cache w", today.cacheCreationTokens), ("cache r", today.cacheReadTokens),
        ]
        let breakdown = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 12)
        for (name, value) in parts {
            let label = Gtk.label(
                "<span size='small'>\(name) <b>\(Gtk.escape(TokenFormatter.compact(value)))</b></span>")
            Gtk.addClass(label, "ptb-muted")
            Gtk.pack(breakdown, label)
        }
        Gtk.pack(card, breakdown)
        return card
    }

    /// The official Claude limit windows with their reset countdowns.
    private func limitsCard(_ l: L, _ limits: LimitStatus) -> Widget {
        let card = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 8)
        Gtk.addClass(card, "ptb-card")
        let caption = Gtk.label(Gtk.escape(l.limitsOfficial))
        Gtk.addClass(caption, "ptb-section")
        Gtk.pack(card, caption)

        let windows: [(String, LimitWindow?)] = [
            (l.fiveHourSession, limits.fiveHour),
            (l.weekly, limits.sevenDay),
            (l.weeklyOpus, limits.sevenDayOpus),
            (l.weeklySonnet, limits.sevenDaySonnet),
        ]
        for (title, window) in windows {
            // A window with no utilisation has not been reported by the API — showing an empty
            // meter would read as "0% used", which is the opposite of "unknown".
            guard let window, let utilization = window.utilization else { continue }
            Gtk.pack(card, limitRow(title, utilization))
        }
        return card
    }

    private func limitRow(_ title: String, _ utilization: Double) -> Widget {
        let row = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 3)
        let heading = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        Gtk.pack(heading, Gtk.label("<span size='small'>\(Gtk.escape(title))</span>"))

        let percent = Gtk.label(
            "<span size='small'><b>\(Gtk.escape(TokenFormatter.percent(utilization)))</b></span>")
        gtk_widget_set_hexpand(percent, 1)
        gtk_widget_set_halign(percent, GTK_ALIGN_END)
        Gtk.pack(heading, percent, expand: true)
        Gtk.pack(row, heading)

        // Same thresholds the menu bar and the limit notifications use, so one glance means one thing.
        let meter = Gtk.meter(fraction: utilization)
        if utilization >= store.critThreshold {
            Gtk.addClass(meter, "ptb-crit")
        } else if utilization >= store.warnThreshold {
            Gtk.addClass(meter, "ptb-warn")
        } else {
            Gtk.addClass(meter, "ptb-ok")
        }
        Gtk.pack(row, meter)
        return row
    }
}

private extension PopoverTab {
    /// Stable identifier for `gtk_stack_add_titled`; the visible title is localised separately.
    var identifier: String {
        switch self {
        case .home: return "home"
        case .shop: return "shop"
        case .bag: return "bag"
        case .collection: return "collection"
        }
    }
}
#endif   // os(Linux)
