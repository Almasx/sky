import SwiftUI

/// The saved skies. One JSON file in Application Support, rewritten on every
/// change — a handful of gradients, so there's nothing to optimize.
///
/// First launch seeds the store with the Figma presets, one of each palette
/// (the design's gallery repeats palettes to fill the grid).
@Observable
final class SkyStore {
    private(set) var items: [SkyGradient]

    init() {
        items = Self.load().map(Self.normalizingTitles) ?? SkyGradient.presets
    }

    /// Skies saved before the title format was pinned came out day-first or
    /// with long month names ("9 September"); bring those to "Sep 9". Short
    /// months that already fit the presets ("July 5", "Jun 15") are kept.
    private static func normalizingTitles(_ items: [SkyGradient]) -> [SkyGradient] {
        items.map { item in
            var parts = item.title.split(separator: " ").map(String.init)
            guard parts.count == 2 else { return item }
            if Int(parts[0]) != nil, Int(parts[1]) == nil { parts.swapAt(0, 1) }   // day first → month first
            guard Int(parts[1]) != nil else { return item }
            if parts[0].count > 4 { parts[0] = String(parts[0].prefix(3)) }       // September → Sep
            let title = parts.joined(separator: " ")
            return title == item.title ? item : SkyGradient(id: item.id, title: title, stops: item.stops)
        }
    }

    /// Saves a new sky at the end of the gallery, with the next free id.
    func add(title: String, stops: [SkyStop]) {
        let id = (items.map(\.id).max() ?? -1) + 1
        items.append(SkyGradient(id: id, title: title, stops: stops))
        save()
    }

    /// Replaces a sky's stops in place, keeping its spot in the grid.
    func update(_ id: Int, stops: [SkyStop]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = SkyGradient(id: id, title: items[index].title, stops: stops)
        save()
    }

    /// Replaces the whole gallery — the jiggle-mode commit, where any
    /// reorders and deletions land together.
    func replaceAll(_ newItems: [SkyGradient]) {
        guard newItems != items else { return }
        items = newItems
        save()
    }

    // MARK: - Disk

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("skies.json")
    }

    private static func load() -> [SkyGradient]? {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SkyGradient].self, from: data),
              !items.isEmpty else { return nil }
        return items
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }
}
