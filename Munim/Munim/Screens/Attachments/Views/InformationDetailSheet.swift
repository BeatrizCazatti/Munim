import SwiftUI

// --- Definição dos Dados (Baseada nos campos da imagem) ---
struct InformationDetails: Hashable {
    let owner: String
    let creationDate: String
    let link: String
}

struct InformationItem: Identifiable {
    let id = UUID()
    let name: String
    let details: InformationDetails
}

// --- View Refatorada ---
struct InformationDetailSheet: View {
    let information: InformationItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) var theme // Mantendo o uso do tema

    var body: some View {
        VStack(spacing: 0) {
            // Cabeçalho
            HStack {
                Spacer()
                Button("Fechar", systemImage: "xmark", action: { dismiss() })
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            Divider()

            // Conteúdo Principal (Scrollable)
            ScrollView {
                VStack(alignment: .center) {
                    HStack {
                        Image(systemName: "document.fill")
                            .font(.system(size: 100, weight: .medium))
                            .foregroundStyle(theme.accentColor)
                            .frame(width: 200, height: 200)

                        // Título (Nome do Item)
                        VStack (spacing: 20) {
                            Text(information.name)
                                .adaptiveTextStyle(.title)
                                .fontWeight(.semibold)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Metadados (Dono, Criado em, Link)
                            InformationMetadataView(details: information.details)
                            
                            Spacer()
                            
                            // Área de Ações (Rodapé, adaptada como sub-view)
                            InformationActionFooterView(link: information.details.link)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 30)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 640, minHeight: 348)
    }
}

// --- Sub-views Privadas ---

// Bloco de Metadados
private struct InformationMetadataView: View {
    let details: InformationDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { // Espaçamento ligeiramente ajustado
            InformationDetailRow(label: "Dono", value: details.owner, systemImage: "person.2.fill")
            InformationDetailRow(label: "Criado em", value: details.creationDate, systemImage: "calendar")
            
            // Linha do Link (Ícone de pasta, sem label explícito, valor formatado como na imagem)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                 Image(systemName: "folder.fill")
                     .frame(width: 20)
                 // Compensar o espaço do label, como na AttachmentDetailRow
                 Spacer().frame(width: 112)
                 Text(details.link)
                     .foregroundStyle(.primary) // Ou uma cor de link específica
            }
//            .font(.body)
            .adaptiveTextStyle(.body)
        }
    }
}

// Rodapé com Botões de Ação
private struct InformationActionFooterView: View {
    let link: String
    @Environment(\.appTheme) var theme
    
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 12) {
                // Botão "Ver" (Secundário)
                Button(action: {}) {
                    Label("Ver", systemImage: "folder.fill")
                }
                .buttonStyle(.bordered)

                // Botão "Abrir" (Destaque)
                Button(action: {
                    // Ação para abrir o link
                    if let url = URL(string: link) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Abrir", systemImage: "paperclip")
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentColor)
            }
        }
    }
}

// Linha Genérica de Detalhes (Reutilizável, baseada na original)
private struct InformationDetailRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(label))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
        }
//        .font(.body)
        .adaptiveTextStyle(.body)
    }
}

// --- Estrutura de Preview ---
struct InformationDetailSheet_Previews: PreviewProvider {
    static var previews: some View {
        InformationDetailSheet(information: InformationItem(
            name: "Ata de reunião Atendimento\n(07/05/26)",
            details: InformationDetails(
                owner: "Leonardo Drummond",
                creationDate: "10 de maio, 2026",
                link: "[link]"
            )
        ))
    }
}
