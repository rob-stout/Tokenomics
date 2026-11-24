import Foundation

/// Pure rules for syncing the provider tab order with the browser extension.
/// The extension has its own copy of `applyIncomingOrder` (extension/src/provider-order.ts);
/// keep the two in step.
enum ProviderOrderSync {

    /// The order the app actually displays: the saved order, with any provider it
    /// doesn't mention appended in enum order. Empty saved order = enum order.
    static func effectiveOrder(stored: [ProviderId]) -> [ProviderId] {
        var result: [ProviderId] = []
        for id in stored where !result.contains(id) { result.append(id) }
        for id in ProviderId.allCases where !result.contains(id) { result.append(id) }
        return result
    }

    /// Reorders `current` to follow `incoming` for the ids both sides know.
    ///
    /// Rule: take the slots (positions) in `current` held by ids that also appear in
    /// `incoming`, and refill those slots, in slot order, with those ids in `incoming`'s
    /// relative order. Ids missing from `incoming` stay exactly where they are; ids only
    /// in `incoming` are ignored; duplicates in `incoming` count once (first wins).
    /// The result is always a permutation of `current`.
    static func applyIncomingOrder(_ incoming: [String], to current: [String]) -> [String] {
        let currentSet = Set(current)
        var seen = Set<String>()
        let shared = incoming.filter { currentSet.contains($0) && seen.insert($0).inserted }
        let sharedSet = Set(shared)

        var queue = shared.makeIterator()
        return current.map { id in
            sharedSet.contains(id) ? (queue.next() ?? id) : id
        }
    }
}
