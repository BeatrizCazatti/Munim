import Foundation

enum FilterSubject: String, CaseIterable, Identifiable {
    case payments = "Pagamentos"
    case goals = "Metas e planos"
    case contracts = "Contratos"
    case deliveries = "Entregas"
    case sales = "Vendas"
    case humanResources = "Recursos Humanos"

    var id: Self { self }

    var title: String {
        switch self {
        case .payments: String(localized: "Pagamentos")
        case .goals: String(localized: "Metas e planos")
        case .contracts: String(localized: "Contratos")
        case .deliveries: String(localized: "Entregas")
        case .sales: String(localized: "Vendas")
        case .humanResources: String(localized: "Recursos Humanos")
        }
    }
}
