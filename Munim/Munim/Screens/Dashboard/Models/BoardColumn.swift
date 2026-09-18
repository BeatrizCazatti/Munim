import SwiftUI

// MARK: - Armazenamento persistente de cards aprovados / revisados

final class ReviewedItemsStore {
    static let shared = ReviewedItemsStore()
    private let key = "Munim.ReviewedItemIDs"

    private var reviewedIDs: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: key) ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: key)
        }
    }

    func isReviewed(id: String) -> Bool {
        reviewedIDs.contains(id)
    }

    func markAsReviewed(id: String) {
        var current = reviewedIDs
        current.insert(id)
        reviewedIDs = current
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Guarda localmente os cards arquivados enquanto o backend ainda não expõe
/// um contrato de arquivamento. A chave estável é o UUID do item remoto, para
/// que o estado sobreviva a recarregamentos e novas sessões do aplicativo.
final class ArchivedItemsStore {
    static let shared = ArchivedItemsStore()
    private let key = "Munim.ArchivedItems"

    struct Record: Codable {
        let persistentKey: String
        let storedAt: Date
    }

    private var recordsByKey: [String: Record] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let records = try? JSONDecoder().decode([String: Record].self, from: data) else {
                return [:]
            }
            return records
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func record(for persistentKey: String) -> Record? {
        recordsByKey[persistentKey]
    }

    func archive(_ persistentKey: String, at date: Date = .now) {
        var records = recordsByKey
        records[persistentKey] = Record(persistentKey: persistentKey, storedAt: date)
        recordsByKey = records
    }

    func restore(_ persistentKey: String) {
        var records = recordsByKey
        records.removeValue(forKey: persistentKey)
        recordsByKey = records
    }
}

/// Uma coluna do board (ex.: "Atendimento", "Design"...).
struct BoardColumn: Identifiable, Hashable {
    let id: UUID
    let title: String
    var items: [BoardItem]

    init(id: UUID = UUID(), title: String, items: [BoardItem]) {
        self.id = id
        self.title = title
        self.items = items
    }

    func filtered(by category: DashboardItemCategory?) -> BoardColumn {
        guard let category else { return self }

        return BoardColumn(
            id: id,
            title: title,
            items: items.filter { $0.category == category }
        )
    }

    func filtered(
        by category: DashboardItemCategory?,
        matching searchQuery: String,
        in dateRange: WeekRange? = nil
    ) -> BoardColumn {
        var filteredColumn = filtered(by: category)

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            filteredColumn.items = filteredColumn.items.filter { $0.matches(searchQuery: query) }
        }

        if let dateRange {
            filteredColumn.items = filteredColumn.items.filter { item in
                guard let itemDate = item.rawDate else { return true }
                return dateRange.contains(itemDate)
            }
        }

        return filteredColumn
    }

    @discardableResult
    mutating func markAsReviewed(itemID: BoardItem.ID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              items[index].badgeCount != nil else { return false }
        ReviewedItemsStore.shared.markAsReviewed(id: items[index].persistentKey)
        items[index].markAsReviewed()
        return true
    }

    mutating func update(itemID: BoardItem.ID, with draft: BoardItemDraft) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].apply(draft)
    }

    mutating func remove(itemID: BoardItem.ID) -> (item: BoardItem, index: Int)? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        return (items.remove(at: index), index)
    }

    mutating func restore(_ item: BoardItem, at index: Int) {
        items.insert(item, at: min(index, items.count))
    }

    func unreadItemCount(for category: DashboardItemCategory?, in dateRange: WeekRange? = nil) -> Int {
        items.filter { item in
            guard item.badgeCount != nil else { return false }
            if let category, item.category != category { return false }
            if let dateRange, let itemDate = item.rawDate {
                return dateRange.contains(itemDate)
            }
            return true
        }.count
    }
}

/// Um card individual dentro de uma coluna do board.
struct BoardItem: Identifiable, Hashable {
    let id: UUID
    let persistentKey: String
    var title: String
    /// Número exibido no badge circular no canto superior do card (opcional).
    var badgeCount: Int?
    var assignees: [Assignee]
    /// Data real para filtragem cronológica precisa.
    var rawDate: Date?
    /// Texto livre de data (ex.: "Amanhã - 17h").
    var dateText: String?
    /// Se `true`, destaca a data como "Nova data" (ex.: reagendamento).
    let isRescheduled: Bool
    var location: String?
    /// Usado por cards de "decisão", que mostram um parágrafo em vez de metadados.
    var descriptionText: String?
    var priority: BoardItemPriority
    let category: DashboardItemCategory

    init(
        id: UUID = UUID(),
        persistentKey: String? = nil,
        title: String,
        badgeCount: Int? = nil,
        assignees: [Assignee] = [],
        rawDate: Date? = nil,
        dateText: String? = nil,
        isRescheduled: Bool = false,
        location: String? = nil,
        descriptionText: String? = nil,
        priority: BoardItemPriority = .unset,
        category: DashboardItemCategory
    ) {
        self.id = id
        let key = persistentKey ?? "\(category.rawValue)_\(title)"
        self.persistentKey = key
        self.title = title
        self.badgeCount = badgeCount
        self.assignees = assignees
        self.rawDate = rawDate
        self.dateText = dateText
        self.isRescheduled = isRescheduled
        self.location = location
        self.descriptionText = descriptionText
        self.priority = priority
        self.category = category
    }

    init(draft: BoardItemDraft, category: DashboardItemCategory) {
        self.init(
            title: draft.title,
            badgeCount: 1,
            assignees: draft.assignees,
            rawDate: draft.scheduledAt,
            dateText: draft.scheduledAt.formatted(
                .dateTime
                    .locale(Locale(identifier: "pt_BR"))
                    .day()
                    .month(.abbreviated)
                    .hour()
                    .minute()
            ),
            location: draft.location.emptyAsNil,
            descriptionText: draft.description.emptyAsNil,
            priority: draft.priority,
            category: category
        )
    }

    mutating func markAsReviewed() {
        ReviewedItemsStore.shared.markAsReviewed(id: persistentKey)
        badgeCount = nil
    }

    var isAwaitingReview: Bool {
        badgeCount != nil
    }

    mutating func apply(_ draft: BoardItemDraft) {
        title = draft.title
        descriptionText = draft.description.emptyAsNil
        assignees = draft.assignees
        rawDate = draft.scheduledAt
        dateText = draft.scheduledAt.formatted(
            .dateTime
                .locale(Locale(identifier: "pt_BR"))
                .day()
                .month(.abbreviated)
                .hour()
                .minute()
        )
        location = draft.location.emptyAsNil
        priority = draft.priority
    }
}

extension BoardItem {
    func matches(searchQuery: String) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let searchableText = [title, descriptionText ?? "", dateText ?? "", location ?? ""]
            + assignees.map(\.name)

        return searchableText.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct BoardItemDraft {
    var title: String
    var description: String
    var assignees: [Assignee]
    var assigneeID: UUID?
    var scheduledAt: Date
    var location: String
    var priority: BoardItemPriority

    init() {
        title = ""
        description = ""
        assignees = []
        assigneeID = nil
        scheduledAt = .now
        location = ""
        priority = .unset
    }

    init(item: BoardItem) {
        title = item.title
        description = item.descriptionText ?? ""
        assignees = item.assignees
        assigneeID = nil
        scheduledAt = item.rawDate ?? .now
        location = item.location ?? ""
        priority = item.priority
    }
}

enum BoardItemPriority: String, CaseIterable, Identifiable, Hashable {
    case high
    case medium
    case low
    case unset

    var id: Self { self }

    var title: String {
        switch self {
        case .high: "Alta"
        case .medium: "Média"
        case .low: "Baixa"
        case .unset: "Definir prioridade"
        }
    }
}

private extension String {
    var emptyAsNil: String? {
        isEmpty ? nil : self
    }
}
