#if os(Linux)
import CGtk
import Foundation

// GTK is a C API built on GObject's single-inheritance casts. Swift sees every widget as
// `UnsafeMutablePointer<GtkWidget>` and every upcast as a raw-pointer rebind, so without these
// helpers the layout code is more cast than content.

typealias Widget = UnsafeMutablePointer<GtkWidget>

@inline(__always) func asContainer(_ w: Widget) -> UnsafeMutablePointer<GtkContainer> {
    UnsafeMutableRawPointer(w).assumingMemoryBound(to: GtkContainer.self)
}
@inline(__always) func asBox(_ w: Widget) -> UnsafeMutablePointer<GtkBox> {
    UnsafeMutableRawPointer(w).assumingMemoryBound(to: GtkBox.self)
}
@inline(__always) func asLabel(_ w: Widget) -> UnsafeMutablePointer<GtkLabel> {
    UnsafeMutableRawPointer(w).assumingMemoryBound(to: GtkLabel.self)
}
@inline(__always) func asProgressBar(_ w: Widget) -> UnsafeMutablePointer<GtkProgressBar> {
    UnsafeMutableRawPointer(w).assumingMemoryBound(to: GtkProgressBar.self)
}
@inline(__always) func asWindow(_ w: Widget) -> UnsafeMutablePointer<GtkWindow> {
    UnsafeMutableRawPointer(w).assumingMemoryBound(to: GtkWindow.self)
}
@inline(__always) func asImage(_ w: Widget) -> UnsafeMutablePointer<GtkImage> {
    UnsafeMutableRawPointer(w).assumingMemoryBound(to: GtkImage.self)
}
@inline(__always) func asStack(_ w: Widget) -> UnsafeMutablePointer<GtkStack> {
    UnsafeMutableRawPointer(w).assumingMemoryBound(to: GtkStack.self)
}

enum Gtk {
    /// A label carrying Pango markup. Everything styled — bold numbers, coloured percentages — goes
    /// through markup rather than per-widget CSS, because the text is rebuilt on every refresh and
    /// swapping one string is cheaper than reattaching style classes.
    static func label(
        _ markup: String = "", align: GtkAlign = GTK_ALIGN_START, wrap: Bool = false
    ) -> Widget {
        let widget = gtk_label_new(nil)!
        setMarkup(widget, markup)
        gtk_widget_set_halign(widget, align)
        if wrap {
            gtk_label_set_line_wrap(asLabel(widget), 1)
            gtk_label_set_xalign(asLabel(widget), 0)
        }
        return widget
    }

    static func setMarkup(_ widget: Widget, _ markup: String) {
        validate(markup)
        gtk_label_set_markup(asLabel(widget), markup)
    }

    /// Complain loudly about markup Pango cannot parse.
    ///
    /// `gtk_label_set_markup` reports nothing on failure — it just leaves the label **blank**. A
    /// stray attribute (`<span class='t'>`, which Pango has no concept of) therefore erases the text
    /// silently, and the only symptom is a missing name in the UI. `pango_parse_markup` does return
    /// an error, so every markup string is run past it and failures land in the log with the text
    /// that caused them.
    private static func validate(_ markup: String) {
        var error: UnsafeMutablePointer<GError>?
        let ok = pango_parse_markup(markup, -1, 0, nil, nil, nil, &error) != 0
        guard !ok else { return }
        let reason = error.flatMap { String(cString: $0.pointee.message) } ?? "unknown"
        if let error { g_error_free(error) }
        AppLog.write("invalid Pango markup (label will render blank): \(reason) — \(markup)")
        assertionFailure("invalid Pango markup: \(reason) — \(markup)")
    }

    static func box(_ orientation: GtkOrientation, spacing: Int = 0) -> Widget {
        gtk_box_new(orientation, Int32(spacing))!
    }

    static func pack(_ container: Widget, _ child: Widget, expand: Bool = false, padding: Int = 0) {
        gtk_box_pack_start(asBox(container), child, expand ? 1 : 0, expand ? 1 : 0, guint(padding))
    }

    /// A thin horizontal meter. GTK's own progress bar carries a lot of theme padding, so the
    /// height is pinned to keep the limit rows compact like the macOS popover.
    static func meter(fraction: Double, cssClass: String? = nil) -> Widget {
        let bar = gtk_progress_bar_new()!
        gtk_progress_bar_set_fraction(asProgressBar(bar), max(0, min(1, fraction)))
        gtk_widget_set_size_request(bar, -1, 6)
        if let cssClass { addClass(bar, cssClass) }
        return bar
    }

    static func addClass(_ widget: Widget, _ name: String) {
        gtk_style_context_add_class(gtk_widget_get_style_context(widget), name)
    }

    static func removeClass(_ widget: Widget, _ name: String) {
        gtk_style_context_remove_class(gtk_widget_get_style_context(widget), name)
    }

    static func margins(_ widget: Widget, top: Int = 0, bottom: Int = 0, start: Int = 0, end: Int = 0) {
        gtk_widget_set_margin_top(widget, Int32(top))
        gtk_widget_set_margin_bottom(widget, Int32(bottom))
        gtk_widget_set_margin_start(widget, Int32(start))
        gtk_widget_set_margin_end(widget, Int32(end))
    }

    /// Remove and destroy every child — the panels are rebuilt wholesale on refresh.
    static func clear(_ container: Widget) {
        let children = gtk_container_get_children(asContainer(container))
        var node = children
        while let current = node {
            if let child = current.pointee.data {
                gtk_widget_destroy(child.assumingMemoryBound(to: GtkWidget.self))
            }
            node = current.pointee.next
        }
        g_list_free(children)
    }

    /// Pango markup escaping. Pokémon names and provider labels are data, and an unescaped `&`
    /// makes `gtk_label_set_markup` reject the whole string, blanking the row.
    static func escape(_ text: String) -> String {
        guard let escaped = g_markup_escape_text(text, -1) else { return "" }
        defer { g_free(escaped) }
        return String(cString: escaped)
    }
}
#endif   // os(Linux)
