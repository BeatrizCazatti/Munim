import SwiftUI

/// Folha de leitura com os metadados e a origem de um arquivo selecionado.
struct AttachmentDetailSheet: View {
    let attachment: AttachmentItem
    let onUpdate: (AttachmentItem) -> Void

    @State private var isEditingMetadata = false
    @State private var participants: String
    @State private var deadline: String
    @State private var modality: String
    @State private var project: String
    @State private var isShowingDiscardChangesAlert = false
    
    init(attachment: AttachmentItem, onUpdate: @escaping (AttachmentItem) -> Void) {
        self.attachment = attachment
        self.onUpdate = onUpdate
        _participants = State(initialValue: attachment.details.participants)
        _deadline = State(initialValue: attachment.details.deadline)
        _modality = State(initialValue: attachment.details.modality)
        _project = State(initialValue: attachment.details.project)
    }
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(isEditingMetadata ? "Salvar" : "Editar", systemImage: isEditingMetadata ? "checkmark" : "pencil") {
                    if isEditingMetadata {
                        saveMetadataChanges()
                    } else {
                        isEditingMetadata = true
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Fechar", systemImage: "xmark", action: requestDismiss)
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
//                        .font(.title.weight(.semibold))
                        .adaptiveTextStyle(.title)
                        .fontWeight(Font.Weight.semibold)
                        .fixedSize(horizontal: false, vertical: true)

                    AttachmentMetadataView(
                        participants: $participants,
                        deadline: $deadline,
                        modality: $modality,
                        project: $project,
                        isEditing: isEditingMetadata
                    )

                    Divider()

                    AttachmentSourceView(details: attachment.details, owner: attachment.owner)
                }
                .padding(28)
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 560, idealHeight: 650)
        .alert("Descartar alterações?", isPresented: $isShowingDiscardChangesAlert) {
            Button("Descartar alterações", role: .destructive) {
                dismiss()
            }
            Button("Continuar editando", role: .cancel) {}
        } message: {
            Text("As alterações feitas nos metadados não serão salvas.")
        }
    }

    private func requestDismiss() {
        if isEditingMetadata && hasUnsavedMetadataChanges {
            isShowingDiscardChangesAlert = true
        } else {
            dismiss()
        }
    }

    private var hasUnsavedMetadataChanges: Bool {
        participants != attachment.details.participants
            || deadline != attachment.details.deadline
            || modality != attachment.details.modality
            || project != attachment.details.project
    }

    private func saveMetadataChanges() {
        let updatedDetails = AttachmentDetails(
            participants: participants,
            deadline: deadline,
            modality: modality,
            project: project,
            source: attachment.details.source,
            excerpt: attachment.details.excerpt,
            notes: attachment.details.notes
        )
        let updatedAttachment = AttachmentItem(
            id: attachment.id,
            name: attachment.name,
            owner: attachment.owner,
            location: attachment.location,
            team: attachment.team,
            type: attachment.type,
            folder: attachment.folder,
            details: updatedDetails
        )

        onUpdate(updatedAttachment)
        isEditingMetadata = false
    }
}

private struct AttachmentMetadataView: View {
    @Binding var participants: String
    @Binding var deadline: String
    @Binding var modality: String
    @Binding var project: String
    let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AttachmentDetailRow(label: "Participantes", value: $participants, systemImage: "person.2.fill", isEditing: isEditing)
            AttachmentDetailRow(label: "Prazo", value: $deadline, systemImage: "calendar", isEditing: isEditing)
            AttachmentDetailRow(label: "Modalidade", value: $modality, systemImage: "mappin.and.ellipse", isEditing: isEditing)
            AttachmentDetailRow(label: "Projeto", value: $project, systemImage: "briefcase.fill", isEditing: isEditing)
        }
    }
}

private struct AttachmentSourceView: View {
    let details: AttachmentDetails
    let owner: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Origem da informação")
                .adaptiveTextStyle(.headline)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    Circle()
                        .fill(Color.Token.borderSubtle.opacity(0.8))
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Text(owner)
                                .fontWeight(.medium)
                            Text(details.deadline)
                                .foregroundStyle(.secondary)
                        }
                        .adaptiveTextStyle(.body)

                        Text("“\(details.excerpt)”")
                            .adaptiveTextStyle(.body)
                        Text(details.notes)
                            .adaptiveTextStyle(.body)
                    }
                }
                .padding(28)

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundStyle(Color.Token.interactiveAccent)

                    SourceLocationLabel(source: details.source)
                }
                .adaptiveTextStyle(.body)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .background(Color.Token.backgroundPrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.Token.borderSubtle, lineWidth: 1)
            }
        }
    }
}

private struct SourceLocationLabel: View {
    let source: String

    private var components: [String] {
        source.components(separatedBy: " > ")
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(component)
                    .foregroundStyle(index == 0 ? .secondary : .primary)
            }
        }
    }
}

private struct AttachmentDetailRow: View {
    let label: String
    @Binding var value: String
    let systemImage: String
    let isEditing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .frame(width: 20)
            Text(LocalizedStringKey(label))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            if isEditing {
                TextField(label, text: $value)
            } else {
                Text(value)
                    .fontWeight(.medium)
            }
        }
//        .font(.body)
        .adaptiveTextStyle(.body)
    }
}
