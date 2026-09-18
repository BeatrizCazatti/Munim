import SwiftUI

/// Folha de leitura com os metadados e a origem de um arquivo selecionado.
struct AttachmentDetailSheet: View {
    let attachment: AttachmentItem
    let onUpdate: (AttachmentItem) -> Void
    
    init(attachment: AttachmentItem, onUpdate: @escaping (AttachmentItem) -> Void) {
            self.attachment = attachment
            self.onUpdate = onUpdate
        }
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
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

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(attachment.name)
                        .font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    AttachmentMetadataView(details: attachment.details)

                    Divider()

                    AttachmentSourceView(details: attachment.details, owner: attachment.owner)
                }
                .padding(28)
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 560, idealHeight: 650)
    }
}

private struct AttachmentMetadataView: View {
    let details: AttachmentDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AttachmentDetailRow(label: "Participantes", value: details.participants, systemImage: "person.2.fill")
            AttachmentDetailRow(label: "Prazo", value: details.deadline, systemImage: "calendar")
            AttachmentDetailRow(label: "Modalidade", value: details.modality, systemImage: "mappin.and.ellipse")
            AttachmentDetailRow(label: "Projeto", value: details.project, systemImage: "briefcase.fill")
        }
    }
}

private struct AttachmentSourceView: View {
    let details: AttachmentDetails
    let owner: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Origem da informação")
                .font(.headline)

            AttachmentDetailRow(label: "Canal", value: details.source, systemImage: "bubble.left.and.bubble.right.fill")
            AttachmentDetailRow(label: "Responsável", value: owner, systemImage: "person.fill")

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "bubble.fill")
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Extrato")
                        .foregroundStyle(.secondary)
                    Text("“\(details.excerpt)”")
                        .italic()
                    Text(details.notes)
                        .italic()
                }
                .font(.body)
            }
        }
    }
}

private struct AttachmentDetailRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .frame(width: 20)
            Text(LocalizedStringKey(label))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.body)
    }
}
