#if os(Linux)
import CGtk
import Foundation

/// The popover's stylesheet, installed once for the whole app.
///
/// GTK theming is CSS, and this deliberately does not hardcode a palette: colours come from the
/// user's GTK theme via `@theme_fg_color` and friends, so the window follows their light/dark
/// setting instead of fighting it. Only the accents that carry meaning — the limit colours — are
/// fixed, because "over the warning threshold" has to read the same on every theme.
enum PopoverStyle {
    static func install() {
        let css = """
        .ptb-card {
          background-color: alpha(@theme_fg_color, 0.05);
          border-radius: 10px;
          padding: 12px;
        }
        .ptb-title      { font-weight: bold; font-size: 13px; }
        .ptb-huge       { font-size: 30px; font-weight: bold; }
        .ptb-muted      { color: alpha(@theme_fg_color, 0.55); font-size: 11px; }
        .ptb-section    { font-size: 11px; font-weight: bold; color: alpha(@theme_fg_color, 0.55); }
        .ptb-badge {
          background-color: alpha(@theme_fg_color, 0.12);
          border-radius: 8px;
          padding: 1px 7px;
          font-size: 10px;
          font-weight: bold;
        }
        .ptb-chip {
          background-color: alpha(@theme_fg_color, 0.08);
          border-radius: 12px;
          padding: 3px 10px;
          font-size: 11px;
        }
        /* A celebration should read as an event, not another data card. */
        .ptb-celebration {
          background-color: alpha(@theme_selected_bg_color, 0.30);
          border: 1px solid @theme_selected_bg_color;
        }
        /* Evolution line: the current stage is ringed, later stages are faded back. */
        .ptb-stage-current { border: 2px solid @theme_selected_bg_color; border-radius: 6px; }
        .ptb-stage-future  { opacity: 0.35; }
        .ptb-chip-on {
          background-color: @theme_selected_bg_color;
          color: @theme_selected_fg_color;
        }
        /* Limit meters. Green / amber / red are the same thresholds the menu bar uses, so a glance
           at either surface means the same thing. */
        progressbar.ptb-ok    trough progress { background-color: #35c759; }
        progressbar.ptb-warn  trough progress { background-color: #ff9f0a; }
        progressbar.ptb-crit  trough progress { background-color: #ff453a; }
        progressbar trough { min-height: 6px; border-radius: 3px; }
        progressbar progress { min-height: 6px; border-radius: 3px; }
        """
        guard let provider = gtk_css_provider_new() else { return }
        gtk_css_provider_load_from_data(provider, css, -1, nil)
        if let screen = gdk_screen_get_default() {
            gtk_style_context_add_provider_for_screen(
                screen, OpaquePointer(provider), guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
        }
        g_object_unref(UnsafeMutableRawPointer(provider))
    }
}
#endif   // os(Linux)
