import SwiftUI

private enum FolderPresentation: String, CaseIterable, Identifiable {
    case icons
    case list

    var id: Self { self }

    var label: String {
        switch self {
        case .icons: String(localized: "Ícones")
        case .list: String(localized: "Lista")
        }
    }

    var systemImage: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

/// Navegador de arquivos: começa nas pastas e abre o conteúdo da pasta selecionada.
struct AttachmentsView: View {
    @State private var searchText = ""
    @State private var selectedFolder: AttachmentFolder?
    @State private var selectedAttachmentIDs = Set<AttachmentItem.ID>()
    @State private var selectedAttachment: AttachmentItem?
    @State private var selectedType: AttachmentType?
    @State private var selectedPerson: String?
    @State private var selectedTeam: String?
    @State private var sortOption: SortOption = .newest
    @State private var folderPresentation: FolderPresentation = .icons

    @State private var attachments = MockData.attachments

    private var filteredAttachments: [AttachmentItem] {
        let matchingAttachments = attachments.filter { attachment in
            let matchesFolder = attachment.folder == selectedFolder
            let matchesSearch = attachment.matches(searchQuery: searchText)
            let matchesType = selectedType == nil || attachment.type == selectedType
            let matchesPerson = selectedPerson == nil || attachment.owner == selectedPerson
            let matchesTeam = selectedTeam == nil || attachment.team == selectedTeam

            return matchesFolder && matchesSearch && matchesType && matchesPerson && matchesTeam
        }

        switch sortOption {
        case .newest:
            return matchingAttachments
        case .oldest:
            return Array(matchingAttachments.reversed())
        case .name:
            return matchingAttachments.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .priority:
            return matchingAttachments.sorted { $0.type.rawValue < $1.type.rawValue }
        }
    }

    var body: some View {
        Group {
            if let selectedFolder {
                AttachmentFolderDetailView(
                    folder: selectedFolder,
                    allAttachments: attachments,
                    attachments: filteredAttachments,
                    searchText: $searchText,
                    selection: $selectedAttachmentIDs,
                    selectedAttachment: $selectedAttachment,
                    selectedType: $selectedType,
                    selectedPerson: $selectedPerson,
                    selectedTeam: $selectedTeam,
                    sortOption: $sortOption,
                    onNavigateBack: navigateToRoot
                )
            } else {
                AttachmentFolderGridView(
                    searchText: $searchText,
                    attachments: attachments,
                    presentation: $folderPresentation,
                    onSelect: select
                )
            }
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: selectedFolder == nil ? "Pesquisar pastas e arquivos" : "Pesquisar arquivos"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Token.backgroundPrimary)
        .sheet(item: $selectedAttachment) { attachment in
            switch attachment.contentKind {
            case .file:
                InformationDetailSheet(information: InformationItem(
                    name: attachment.name,
                    details: InformationDetails(
                        owner: attachment.owner,
                        creationDate: attachment.details.deadline, // Ou o campo de data correspondente no seu model
                        link: attachment.details.source
                    )
                ))
            case .information:
                AttachmentDetailSheet(attachment: attachment, onUpdate: { updatedAttachment in
                    update(updatedAttachment)
                })
            }
        }
    }

    private func select(_ folder: AttachmentFolder) {
        selectedFolder = folder
        resetFilters(keepingSearch: true)
    }

    private func navigateToRoot() {
        selectedFolder = nil
        resetFilters()
    }

    private func resetFilters(keepingSearch: Bool = false) {
        if !keepingSearch {
            searchText = ""
        }
        selectedAttachmentIDs.removeAll()
        selectedType = nil
        selectedPerson = nil
        selectedTeam = nil
    }

    private func update(_ attachment: AttachmentItem) {
        guard let index = attachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        attachments[index] = attachment
        selectedAttachment = attachment
    }
}

private struct AttachmentFolderGridView: View {
    @Binding var searchText: String
    let attachments: [AttachmentItem]
    @Binding var presentation: FolderPresentation
    let onSelect: (AttachmentFolder) -> Void

    private var matchingFolders: [AttachmentFolder] {
        AttachmentFolder.allCases.filter { folder in
            folder.rawValue.localizedCaseInsensitiveContains(searchText)
                || attachments.contains { attachment in
                    attachment.folder == folder && attachment.matches(searchQuery: searchText)
                }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 20) {
                        Text("Arquivos e documentos")
                            .fontWeight(.regular)
                            .adaptiveTextStyle(.largeTitle)

                        Spacer(minLength: 24)

                        AttachmentFolderPresentationPicker(selection: $presentation)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Arquivos e documentos")
//                            .font(.largeTitle.weight(.regular))
                            .adaptiveTextStyle(.largeTitle)
                            .fontWeight(.regular)

                        HStack {
                            Spacer()
                            AttachmentFolderPresentationPicker(selection: $presentation)
                        }
                    }
                }

                if matchingFolders.isEmpty {
                    ContentUnavailableView.search
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    if presentation == .icons {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 24)],
                            alignment: .leading,
                            spacing: 28
                        ) {
                            ForEach(matchingFolders) { folder in
                                AttachmentFolderTile(folder: folder) { onSelect(folder) }
                            }
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(matchingFolders) { folder in
                                AttachmentFolderListRow(folder: folder) { onSelect(folder) }

                                if folder != matchingFolders.last {
                                    Divider()
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: 1_600, alignment: .leading)
        }
        .navigationTitle("Arquivos e documentos")
    }
}

private struct AttachmentFolderPresentationPicker: View {
    @Binding var selection: FolderPresentation

    var body: some View {
        Picker("Visualização de pastas", selection: $selection) {
            ForEach(FolderPresentation.allCases) { option in
                Label(option.label, systemImage: option.systemImage)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 112)
        .accessibilityLabel("Visualização de pastas")
    }
}

private struct AttachmentFolderTile: View {
    let folder: AttachmentFolder
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 10) {
                AttachmentFolderIcon(width: 92, height: 70)
                Text(folder.rawValue)
//                    .font(.subheadline)
                    .adaptiveTextStyle(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Abre a pasta \(folder.title)"))
    }
}

private struct AttachmentFolderListRow: View {
    let folder: AttachmentFolder
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                AttachmentFolderIcon(width: 42, height: 32)

                Text(folder.rawValue)
//                    .font(.body.weight(.medium))
                    .adaptiveTextStyle(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
//                    .font(.caption.weight(.semibold))
                    .adaptiveTextStyle(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Abre a pasta \(folder.title)"))
    }
}

/// Exibe o ícone de pasta correspondente ao tema selecionado em todos os
/// contextos do navegador de anexos.
private struct AttachmentFolderIcon: View {
    let width: CGFloat
    let height: CGFloat
    @Environment(\.appTheme) private var theme

    var body: some View {
        theme.attachmentFolderImage
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
    }
}

private struct AttachmentFolderDetailView: View {
    let folder: AttachmentFolder
    let allAttachments: [AttachmentItem]
    let attachments: [AttachmentItem]
    @Binding var searchText: String
    @Binding var selection: Set<AttachmentItem.ID>
    @Binding var selectedAttachment: AttachmentItem?
    @Binding var selectedType: AttachmentType?
    @Binding var selectedPerson: String?
    @Binding var selectedTeam: String?
    @Binding var sortOption: SortOption
    let onNavigateBack: () -> Void

    private var people: [String] {
        Array(Set(folderAttachments.map(\.owner))).sorted()
    }

    private var teams: [String] {
        Array(Set(folderAttachments.map(\.team))).sorted()
    }

    private var folderAttachments: [AttachmentItem] {
        allAttachments.filter { $0.folder == folder }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AttachmentFolderHeader(
                    folder: folder,
                    onNavigateBack: onNavigateBack
                )

                AttachmentFiltersView(
                    selectedType: $selectedType,
                    selectedPerson: $selectedPerson,
                    selectedTeam: $selectedTeam,
                    sortOption: $sortOption,
                    people: people,
                    teams: teams
                )

                AttachmentListView(
                    attachments: attachments,
                    selection: $selection,
                    selectedAttachment: $selectedAttachment
                )
            }
            .padding(40)
            .frame(maxWidth: 1_600, alignment: .leading)
        }
        .navigationTitle(folder.title)
    }
}

private struct AttachmentFolderHeader: View {
    let folder: AttachmentFolder
    let onNavigateBack: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onNavigateBack) {
                Label("Arquivos e documentos", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                AttachmentFolderIcon(width: 42, height: 32)

                Text(folder.rawValue)
//                    .font(.title)
                    .adaptiveTextStyle(.title)
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 24)
        }
    }
}

private struct AttachmentFiltersView: View {
    @Binding var selectedType: AttachmentType?
    @Binding var selectedPerson: String?
    @Binding var selectedTeam: String?
    @Binding var sortOption: SortOption
    let people: [String]
    let teams: [String]

    @State private var isFilterPopoverPresented = false
    @State private var isSortPopoverPresented = false

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            ToolbarIconButton(systemImage: "line.3.horizontal.decrease", accessibilityLabel: "Filtrar arquivos") {
                isFilterPopoverPresented.toggle()
                isSortPopoverPresented = false
            }
            .popover(isPresented: $isFilterPopoverPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                AttachmentFilterPopover(
                    selectedType: $selectedType,
                    selectedPerson: $selectedPerson,
                    selectedTeam: $selectedTeam,
                    people: people,
                    teams: teams
                )
            }

            ToolbarIconButton(systemImage: "arrow.up.arrow.down", accessibilityLabel: "Ordenar arquivos") {
                isSortPopoverPresented.toggle()
                isFilterPopoverPresented = false
            }
            .popover(isPresented: $isSortPopoverPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                SortPopover(selection: $sortOption)
            }
        }
    }
}

private struct AttachmentFilterPopover: View {
    @Binding var selectedType: AttachmentType?
    @Binding var selectedPerson: String?
    @Binding var selectedTeam: String?
    let people: [String]
    let teams: [String]

    @State private var peopleSearchText = ""
    @State private var teamsSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filtrar por")
//                .font(.headline)
                .adaptiveTextStyle(.headline)

            Divider()

            section(title: "Tipo") {
                FlowLayout(spacing: 6) {
                    ForEach(AttachmentType.allCases) { type in
                        singleChoiceChip(title: type.title, isSelected: selectedType == type) {
                            selectedType = selectedType == type ? nil : type
                        }
                    }
                }
            }

            section(title: "Pessoas") {
                FilterSearchField(placeholder: "Pesquisar pessoas", text: $peopleSearchText)
                FlowLayout(spacing: 6) {
                    ForEach(matching(people, query: peopleSearchText), id: \.self) { person in
                        singleChoiceChip(title: person, isSelected: selectedPerson == person) {
                            selectedPerson = selectedPerson == person ? nil : person
                        }
                    }
                }
            }

            section(title: "Equipes") {
                FilterSearchField(placeholder: "Pesquisar equipes e grupos", text: $teamsSearchText)
                FlowLayout(spacing: 6) {
                    ForEach(matching(teams, query: teamsSearchText), id: \.self) { team in
                        singleChoiceChip(title: team, isSelected: selectedTeam == team) {
                            selectedTeam = selectedTeam == team ? nil : team
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 366)
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
//                .font(.subheadline.weight(.medium))
                .adaptiveTextStyle(.subheadline)
                .fontWeight(Font.Weight.medium)
            content()
        }
    }

    private func matching(_ values: [String], query: String) -> [String] {
        values.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    private func singleChoiceChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        FilterChip(title: title, isSelected: isSelected, showsCloseButton: false, action: action)
    }
}

private struct AttachmentListView: View {
    let attachments: [AttachmentItem]
    @Binding var selection: Set<AttachmentItem.ID>
    @Binding var selectedAttachment: AttachmentItem?

    var body: some View {
        if attachments.isEmpty {
            ContentUnavailableView.search
                .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            VStack(spacing: 0) {
                AttachmentColumnHeader()

                ForEach(attachments) { attachment in
                    AttachmentRow(attachment: attachment, isSelected: selection.contains(attachment.id)) {
                        selection = [attachment.id]
                        selectedAttachment = attachment
                    }

                    if attachment.id != attachments.last?.id {
                        Divider()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

}

private struct AttachmentColumnHeader: View {
    var body: some View {
        HStack(spacing: 20) {
            Text("Nome").frame(maxWidth: .infinity, alignment: .leading)
            Text("Dono").frame(width: 210, alignment: .leading)
            Text("Localização").frame(width: 280, alignment: .leading)
        }
//        .font(.subheadline)
        .adaptiveTextStyle(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

private struct AttachmentRow: View {
    let attachment: AttachmentItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Label(attachment.name, systemImage: attachment.contentKind.systemImage)
                    .labelStyle(AttachmentNameLabelStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(attachment.owner).frame(width: 210, alignment: .leading)
                Text(attachment.location)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 280, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(isSelected ? Color.accentColor.opacity(0.10) : .clear)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AttachmentNameLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.icon.foregroundStyle(.primary).frame(width: 24)
            configuration.title
//                .font(.body.weight(.semibold))
                .adaptiveTextStyle(.body)
                .fontWeight(Font.Weight.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
