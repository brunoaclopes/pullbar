/// Tracks which item IDs have been loaded or are currently loading,
/// preventing duplicate network requests for the same resource.
struct DetailLoadTracker {
    private var loaded: Set<String> = []
    private var loading: Set<String> = []

    /// Returns `true` when the given ID has not been loaded and is not currently loading.
    func shouldLoad(_ id: String) -> Bool {
        !loaded.contains(id) && !loading.contains(id)
    }

    /// Marks the ID as currently in-flight.
    mutating func beginLoading(_ id: String) {
        loading.insert(id)
    }

    /// Removes the in-flight marker (typically called in a `defer`).
    mutating func endLoading(_ id: String) {
        loading.remove(id)
    }

    /// Records the ID as successfully loaded.
    mutating func markLoaded(_ id: String) {
        loaded.insert(id)
    }
}
