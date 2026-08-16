import Foundation

/// Token holder for the popover's `NSEvent` global mouse monitor (#168 / leftover of #154).
///
/// Start and stop are paired: a second `start` must not overwrite a live token, or
/// `removeMonitor` never sees it and the observer outlives the popover. Register and
/// remove are injected so tests can prove the leak without installing a real monitor.
struct OutsideClickMonitor {
    private(set) var token: Any?

    mutating func start(register: () -> Any?) {
        guard token == nil else { return }
        token = register()
    }

    mutating func stop(remove: (Any) -> Void) {
        if let token {
            remove(token)
            self.token = nil
        }
    }
}
