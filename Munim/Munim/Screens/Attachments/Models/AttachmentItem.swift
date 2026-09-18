import Foundation

/// Representa um arquivo encontrado nas fontes conectadas ao workspace.
struct AttachmentItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let owner: String
    let location: String
    let team: String
    let type: AttachmentType
    let folder: AttachmentFolder
    let details: AttachmentDetails

    init(
        id: UUID = UUID(),
        name: String,
        owner: String,
        location: String,
        team: String,
        type: AttachmentType,
        folder: AttachmentFolder,
        details: AttachmentDetails? = nil
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.location = location
        self.team = team
        self.type = type
        self.folder = folder
        self.details = details ?? AttachmentDetails(
            participants: "\(owner) e \(team)",
            deadline: "09 de agosto, 2026",
            modality: "Presencial",
            project: team,
            source: location,
            excerpt: "Estamos oficialmente entrando na fase de implementação. A atualização seguirá o planejamento definido pela equipe.",
            notes: "As informações foram consolidadas a partir da conversa e dos documentos relacionados."
        )
    }

    /// Define como o item deve ser apresentado no navegador e qual detalhe abrir.
    var contentKind: AttachmentContentKind {
        type == .information ? .information : .file
    }
}

extension AttachmentItem {
    /// Pesquisa pelos metadados que ajudam a identificar um arquivo, inclusive
    /// quando a busca começa na visualização de pastas.
    func matches(searchQuery: String) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let searchableText = [
            name,
            owner,
            location,
            team,
            type.rawValue,
            folder.rawValue,
            details.participants,
            details.project,
            details.source,
            details.excerpt,
            details.notes
        ]

        return searchableText.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Informações complementares mostradas ao abrir um arquivo.
struct AttachmentDetails: Hashable {
    let participants: String
    let deadline: String
    let modality: String
    let project: String
    let source: String
    let excerpt: String
    let notes: String
}

/// Pastas de primeiro nível disponíveis no navegador de arquivos.
enum AttachmentFolder: String, CaseIterable, Identifiable {
    case meetingMinutes = "Atas de reunião"
    case productAnalysis = "Análise de Produto"
    case contracts = "Contratos"
    case commercial = "Comercial"

    var id: Self { self }

    var title: String {
        switch self {
        case .meetingMinutes: String(localized: "Atas de reunião")
        case .productAnalysis: String(localized: "Análise de Produto")
        case .contracts: String(localized: "Contratos")
        case .commercial: String(localized: "Comercial")
        }
    }
}

enum AttachmentType: String, CaseIterable, Identifiable {
    case document = "Documento"
    case spreadsheet = "Planilha"
    case presentation = "Apresentação"
    case information = "Informações"

    var id: Self { self }

    var title: String {
        switch self {
        case .document: String(localized: "Documento")
        case .spreadsheet: String(localized: "Planilha")
        case .presentation: String(localized: "Apresentação")
        case .information: String(localized: "Informações")
        }
    }
}

/// Diferencia documentos de informações extraídas das fontes conectadas.
enum AttachmentContentKind: Hashable {
    case file
    case information

    var systemImage: String {
        switch self {
        case .file: "doc.fill"
        case .information: "message.fill"
        }
    }
}

enum AttachmentResultScope: String, CaseIterable, Identifiable {
    case data = "Dados"
    case files = "Arquivos"

    var id: Self { self }

    var title: String {
        switch self {
        case .data: String(localized: "Dados")
        case .files: String(localized: "Arquivos")
        }
    }
}
