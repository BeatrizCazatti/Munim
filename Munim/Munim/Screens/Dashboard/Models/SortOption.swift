import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case name
    case priority

    var id: Self { self }

    var title: String {
        switch self {
        case .newest:
            String(localized: "Mais recente")
        case .oldest:
            String(localized: "Mais antigo")
        case .name:
            String(localized: "Nome")
        case .priority:
            String(localized: "Prioridade")
        }
    }
}
