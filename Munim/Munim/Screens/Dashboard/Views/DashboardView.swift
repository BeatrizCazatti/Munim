//
//  Dashboard.swift
//  Dashboard semanal — layout tipo Kanban com sidebar recolhível
//
//  Segue as diretrizes da Apple Human Interface Guidelines (HIG) para macOS,
//  incluindo o material "Liquid Glass" introduzido nas atualizações recentes
//  de macOS/visionOS/iOS. Componentizado em Views pequenas e reutilizáveis.
//
//  Requer macOS 26 (Tahoe) ou posterior para as APIs `glassEffect` /
//  `GlassEffectContainer`. Em versões anteriores, os fallbacks usam
//  `.ultraThinMaterial`.
//

import SwiftUI
import Combine

// MARK: - View principal

struct DashboardView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var selectedDestination: SidebarDestination? = .dashboard
    @State private var selectedTab: FilterTab = MockData.filterTabs.first!
    @StateObject private var badgeStore = DashboardBadgeStore()
    @State private var columns: [BoardColumn] = []
    @State private var archivedItems: [StoredBoardItem] = []
    @State private var deletedItems: [StoredBoardItem] = []
    @State private var archivedItem: StoredBoardItem?
    @State private var isArchiveUndoPresented = false
    @State private var persistenceError: String?
    @State private var searchText: String = ""
    @State private var selectedWeek = WeekRange(start: Date())
    @Environment(\.appTheme) private var theme
    @Environment(AuthService.self) private var authService

    // MARK: - Serviço de dados reais da API
    @State private var dashboardService = DashboardService()
    var body: some View {
        ZStack {
            // O gradiente vive no nível do SplitView para preencher
            // a janela inteira — inclusive a coluna da sidebar, que
            // fica translúcida (.ultraThinMaterial) e deixa o gradiente
            // aparecer através dos itens.
            ThemeGradientBackground(theme: theme)
                .ignoresSafeArea()

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: $selectedDestination)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
            } detail: {
                SidebarDetailView(
                    selection: selectedDestination,
                    searchText: $searchText,
                    selectedWeek: $selectedWeek,
                    selectedTab: $selectedTab,
                    badgeStore: badgeStore,
                    columns: columns,
                    archivedItems: archivedItems,
                    deletedItems: deletedItems,
                    people: dashboardService.people,
                    userName: authService.currentPerson?.name.components(separatedBy: " ").first ?? "Fabíola",
                    isRefreshing: dashboardService.isRefreshing,
                    lastUpdated: dashboardService.lastUpdated,
                    markAsReviewed: markAsReviewed,
                    updateItem: updateItem,
                    archiveItem: archiveItem,
                    deleteItem: deleteItem,
                    unarchiveItem: unarchiveItem,
                    restoreDeletedItem: restoreDeletedItem,
                    createItem: createItem,
                    onRefresh: {
                        Task {
                            await dashboardService.refresh()
                        }
                    }
                )
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            purgeExpiredDeletedItems()
            refreshBadgeStore()
            // Iniciar monitoramento ao vivo do backend
            dashboardService.startPolling(intervalSeconds: 30)
            Task {
                await dashboardService.loadDashboard()
                applyArchiveState(to: dashboardService.boardColumns)
            }
        }
        .onDisappear {
            dashboardService.stopPolling()
        }
        .onChange(of: dashboardService.boardColumns) { _, newCols in
            applyArchiveState(to: newCols)
        }
        .onChange(of: selectedWeek) { _, _ in
            refreshBadgeStore()
        }
        .alert("Card arquivado", isPresented: $isArchiveUndoPresented) {
            Button("Desfazer") {
                restoreArchivedItem()
            }
            Button("OK", role: .cancel) {
                archivedItem = nil
            }
        } message: {
            Text("O card foi removido do board.")
        }
        .alert("Não foi possível salvar", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "Tente novamente.")
        }
    }

    private func markAsReviewed(itemID: BoardItem.ID, in columnID: BoardColumn.ID) {
        guard let columnIndex = columns.firstIndex(where: { $0.id == columnID }) else { return }

        var updatedColumn = columns[columnIndex]
        guard updatedColumn.markAsReviewed(itemID: itemID) else { return }
        columns[columnIndex] = updatedColumn
        refreshBadgeStore()
    }

    private func updateItem(itemID: BoardItem.ID, in columnID: BoardColumn.ID, with draft: BoardItemDraft) {
        guard let columnIndex = columns.firstIndex(where: { $0.id == columnID }),
              let itemIndex = columns[columnIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        let originalItem = columns[columnIndex].items[itemIndex]
        columns[columnIndex].update(itemID: itemID, with: draft)
        refreshBadgeStore()
        Task {
            do {
                try await dashboardService.updateItem(itemID: itemID, draft: draft)
            } catch {
                guard let currentColumnIndex = columns.firstIndex(where: { $0.id == columnID }),
                      let currentItemIndex = columns[currentColumnIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
                columns[currentColumnIndex].items[currentItemIndex] = originalItem
                refreshBadgeStore()
                persistenceError = error.localizedDescription
            }
        }
    }

    private func archiveItem(itemID: BoardItem.ID, in columnID: BoardColumn.ID) {
        guard let columnIndex = columns.firstIndex(where: { $0.id == columnID }),
              let removedItem = columns[columnIndex].remove(itemID: itemID) else { return }

        archivedItem = StoredBoardItem(columnID: columnID, teamName: columns[columnIndex].title, item: removedItem.item, index: removedItem.index, storedAt: Date())
        archivedItems.append(archivedItem!)
        ArchivedItemsStore.shared.archive(removedItem.item.persistentKey)
        refreshBadgeStore()
        isArchiveUndoPresented = true
    }

    private func deleteItem(itemID: BoardItem.ID, in columnID: BoardColumn.ID) {
        guard let columnIndex = columns.firstIndex(where: { $0.id == columnID }),
              let removedItem = columns[columnIndex].remove(itemID: itemID) else { return }
        deletedItems.append(StoredBoardItem(columnID: columnID, teamName: columns[columnIndex].title, item: removedItem.item, index: removedItem.index, storedAt: Date()))
        purgeExpiredDeletedItems()
        refreshBadgeStore()
        Task {
            await dashboardService.deleteItem(itemID: itemID)
        }
    }

    private func createItem(draft: BoardItemDraft, in team: String, category: DashboardItemCategory) {
        guard let columnIndex = columns.firstIndex(where: { $0.title == team }) else { return }
        columns[columnIndex].items.append(BoardItem(draft: draft, category: category))
        refreshBadgeStore()
        Task {
            await dashboardService.createItem(draft: draft, teamName: team, category: category)
        }
    }

    private func restoreArchivedItem() {
        guard let archivedItem else { return }
        unarchiveItem(archivedItem)
    }

    private func unarchiveItem(_ storedItem: StoredBoardItem) {
        guard restoreToBoard(storedItem) else { return }
        ArchivedItemsStore.shared.restore(storedItem.item.persistentKey)
        archivedItems.removeAll { $0.id == storedItem.id }
        if archivedItem?.id == storedItem.id {
            archivedItem = nil
        }
        refreshBadgeStore()
    }

    private func restoreDeletedItem(_ storedItem: StoredBoardItem) {
        guard restoreToBoard(storedItem) else { return }
        deletedItems.removeAll { $0.id == storedItem.id }
        refreshBadgeStore()
    }

    private func restoreToBoard(_ storedItem: StoredBoardItem) -> Bool {
        guard let columnIndex = columns.firstIndex(where: { $0.id == storedItem.columnID }) else {
            return false
        }

        columns[columnIndex].restore(storedItem.item, at: storedItem.index)
        return true
    }

    private func refreshBadgeStore() {
        badgeStore.refresh(
            columns: columns,
            archivedItems: archivedItems,
            deletedItems: deletedItems,
            dateRange: selectedWeek
        )
    }

    private func purgeExpiredDeletedItems() {
        let expirationDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        deletedItems.removeAll { $0.storedAt < expirationDate }
    }

    /// Aplica os arquivamentos persistidos sobre o snapshot recém-chegado da API.
    /// Sem isso, o polling recriaria os cards arquivados a cada atualização.
    private func applyArchiveState(to incomingColumns: [BoardColumn]) {
        var visibleColumns = incomingColumns
        var restoredArchivedItems: [StoredBoardItem] = []

        for columnIndex in visibleColumns.indices {
            let column = visibleColumns[columnIndex]
            let archivedIndices = column.items.indices.filter {
                ArchivedItemsStore.shared.record(for: column.items[$0].persistentKey) != nil
            }

            for itemIndex in archivedIndices.reversed() {
                let item = visibleColumns[columnIndex].items.remove(at: itemIndex)
                guard let record = ArchivedItemsStore.shared.record(for: item.persistentKey) else { continue }
                restoredArchivedItems.append(
                    StoredBoardItem(
                        columnID: column.id,
                        teamName: column.title,
                        item: item,
                        index: itemIndex,
                        storedAt: record.storedAt
                    )
                )
            }
        }

        columns = visibleColumns
        archivedItems = restoredArchivedItems.sorted { $0.storedAt > $1.storedAt }
        refreshBadgeStore()
    }
}

/// Fonte observável dos badges das abas. A notificação explícita evita que
/// mudanças internas em um item de `columns` fiquem invisíveis para o SwiftUI.
final class DashboardBadgeStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    @Published private(set) var tabs = MockData.filterTabs

    func refresh(
        columns: [BoardColumn],
        archivedItems: [StoredBoardItem],
        deletedItems: [StoredBoardItem],
        dateRange: WeekRange? = nil
    ) {
        let updatedTabs = MockData.filterTabs.map { tab in
            var updatedTab = tab
            switch tab.destination {
            case let .active(category):
                updatedTab.count = columns.reduce(0) { $0 + $1.unreadItemCount(for: category, in: dateRange) }
            case .archived:
                updatedTab.count = archivedItems.count
            case .deleted:
                updatedTab.count = deletedItems.count
            }
            return updatedTab
        }

        tabs = updatedTabs
    }
}

struct StoredBoardItem: Identifiable {
    let columnID: BoardColumn.ID
    let teamName: String
    let item: BoardItem
    let index: Int
    let storedAt: Date

    var id: BoardItem.ID { item.id }
}

// MARK: - Destino da navegação

private struct SidebarDetailView: View {
    let selection: SidebarDestination?
    @Binding var searchText: String
    @Binding var selectedWeek: WeekRange
    @Binding var selectedTab: FilterTab
    let badgeStore: DashboardBadgeStore
    let columns: [BoardColumn]
    let archivedItems: [StoredBoardItem]
    let deletedItems: [StoredBoardItem]
    let people: [PersonDTO]
    let userName: String
    let isRefreshing: Bool
    let lastUpdated: Date?
    let markAsReviewed: (BoardItem.ID, BoardColumn.ID) -> Void
    let updateItem: (BoardItem.ID, BoardColumn.ID, BoardItemDraft) -> Void
    let archiveItem: (BoardItem.ID, BoardColumn.ID) -> Void
    let deleteItem: (BoardItem.ID, BoardColumn.ID) -> Void
    let unarchiveItem: (StoredBoardItem) -> Void
    let restoreDeletedItem: (StoredBoardItem) -> Void
    let createItem: (BoardItemDraft, String, DashboardItemCategory) -> Void
    let onRefresh: () -> Void

    @ViewBuilder
    var body: some View {
        switch selection {
        case .dashboard:
            DashboardContentView(
                searchText: $searchText,
                selectedWeek: $selectedWeek,
                selectedTab: $selectedTab,
                badgeStore: badgeStore,
                columns: columns,
                archivedItems: archivedItems,
                deletedItems: deletedItems,
                people: people,
                userName: userName,
                isRefreshing: isRefreshing,
                lastUpdated: lastUpdated,
                markAsReviewed: markAsReviewed,
                updateItem: updateItem,
                archiveItem: archiveItem,
                deleteItem: deleteItem,
                unarchiveItem: unarchiveItem,
                restoreDeletedItem: restoreDeletedItem,
                createItem: createItem,
                onRefresh: onRefresh
            )
        case .archived:
            SidebarStoredItemsDetailView(
                title: "Arquivados",
                searchText: $searchText,
                storedItems: archivedItems,
                actionTitle: "Desarquivar",
                actionSystemImage: "tray.and.arrow.up",
                action: unarchiveItem
            )
        case .deleted:
            SidebarStoredItemsDetailView(
                title: "Excluídos",
                searchText: $searchText,
                storedItems: deletedItems,
                actionTitle: "Restaurar",
                actionSystemImage: "arrow.uturn.backward",
                action: restoreDeletedItem
            )
        case .attachments:
            AttachmentsView()
        case nil:
            ContentUnavailableView(
                "Selecione uma opção",
                systemImage: "sidebar.left"
            )
        }
    }
}

private struct SidebarStoredItemsDetailView: View {
    let title: String
    @Binding var searchText: String
    let storedItems: [StoredBoardItem]
    let actionTitle: String
    let actionSystemImage: String
    let action: (StoredBoardItem) -> Void

    private var visibleItems: [StoredBoardItem] {
        storedItems.filter { $0.item.matches(searchQuery: searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
//                    .font(.largeTitle.weight(.regular))
                    .adaptiveTextStyle(.largeTitle)
                    .fontWeight(Font.Weight.regular)
                    .foregroundStyle(Color.Token.textBrand)

                StoredItemsBoardView(
                    items: visibleItems,
                    title: title,
                    actionTitle: actionTitle,
                    actionSystemImage: actionSystemImage,
                    action: action
                )
            }
            .padding(24)
        }
        .background(Color.Token.backgroundPrimary)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Buscar cards")
    }
}

// MARK: - Conteúdo principal do dashboard

struct DashboardContentView: View {
    @Binding var searchText: String
    @Binding var selectedWeek: WeekRange
    @Binding var selectedTab: FilterTab
    @ObservedObject var badgeStore: DashboardBadgeStore
    let columns: [BoardColumn]
    let archivedItems: [StoredBoardItem]
    let deletedItems: [StoredBoardItem]
    let people: [PersonDTO]
    let userName: String
    let isRefreshing: Bool
    let lastUpdated: Date?
    let markAsReviewed: (BoardItem.ID, BoardColumn.ID) -> Void
    let updateItem: (BoardItem.ID, BoardColumn.ID, BoardItemDraft) -> Void
    let archiveItem: (BoardItem.ID, BoardColumn.ID) -> Void
    let deleteItem: (BoardItem.ID, BoardColumn.ID) -> Void
    let unarchiveItem: (StoredBoardItem) -> Void
    let restoreDeletedItem: (StoredBoardItem) -> Void
    let createItem: (BoardItemDraft, String, DashboardItemCategory) -> Void
    let onRefresh: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Cabeçalho com saudação e navegador de semana
                    HStack(alignment: .center) {
                        GreetingHeaderView(name: userName)
                        Spacer()
                        WeekNavigatorView(selection: $selectedWeek)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        FilterTabsView(badgeStore: badgeStore, selection: $selectedTab)

                        DashboardToolbarPrimaryButton(title: "Novo item", systemImage: "plus") {
                            isNewItemPresented = true
                        }

                        Spacer(minLength: 16)

                        DashboardRefreshStatusView(
                            isRefreshing: isRefreshing,
                            lastUpdated: lastUpdated,
                            onRefresh: onRefresh
                        )
                    }

                    dashboardBoard
                }
                .padding(24)
                .frame(
                    maxWidth: .infinity,
                    minHeight: max(0, proxy.size.height - 20),
                    alignment: .topLeading
                )
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 20,
                        style: .continuous
                    )
                    .fill(Color.Token.backgroundPrimary)
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                DashboardToolbarControls(teamNames: columns.map(\.title), searchText: $searchText)
            }
        }
        .sheet(isPresented: $isNewItemPresented) {
            NewBoardItemSheet(teamNames: columns.map(\.title)) { draft, team, category in
                createItem(draft, team, category)
            }
        }
    }

    @State private var isNewItemPresented = false

    @ViewBuilder
    private var dashboardBoard: some View {
        switch selectedTab.destination {
        case let .active(category):
            BoardView(
                columns: columns,
                filter: category,
                searchText: searchText,
                selectedWeek: selectedWeek,
                people: people,
                markAsReviewed: markAsReviewed,
                updateItem: updateItem,
                archiveItem: archiveItem,
                deleteItem: deleteItem
            )
        case .archived:
            StoredItemsBoardView(
                items: archivedItems.filter { $0.item.matches(searchQuery: searchText) },
                title: "Arquivado em",
                actionTitle: "Desarquivar",
                actionSystemImage: "tray.and.arrow.up",
                action: unarchiveItem
            )
        case .deleted:
            StoredItemsBoardView(
                items: deletedItems.filter { $0.item.matches(searchQuery: searchText) },
                title: "Excluído em",
                actionTitle: "Restaurar",
                actionSystemImage: "arrow.uturn.backward",
                action: restoreDeletedItem
            )
        }
    }

}

// MARK: - Cabeçalho de saudação

struct GreetingHeaderView: View {
    let name: String

    var body: some View {
        (
            Text("Olá, " + name + "!")
//                .font(.title.weight(.regular))
                .adaptiveTextStyle(.title)
                .fontWeight(.regular)
        )
        .foregroundStyle(Color.Token.textBrand)
    }
}

// MARK: - Navegador de semana

struct WeekNavigatorView: View {
    @Binding var selection: WeekRange
    @State private var showCalendar = false
    @Environment(\.appTheme) private var theme

    private let calendar = Calendar.dashboard

    var body: some View {
        HStack(spacing: 12) {
            Button {
                moveWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(theme.accentColor)
            }
            .buttonStyle(.plain)

            Button {
                showCalendar.toggle()
            } label: {
                Text(selectedWeekText)
//                .font(.title3.weight(.medium))
                .adaptiveTextStyle(.title3)
                .fontWeight(Font.Weight.medium)
                .foregroundStyle(theme.accentColor)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCalendar, arrowEdge: .top) {
                WeekRangePicker(selection: $selection)
            }

            Button {
                moveWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.accentColor)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.Token.interactiveAccent)
    }
    private var selectedWeekText: String {
        let start = selection.start.formatted(.dateTime.locale(Locale(identifier: "pt_BR")).day().month(.abbreviated))
        let end = selection.end.formatted(.dateTime.locale(Locale(identifier: "pt_BR")).day().month(.abbreviated).year())
        return "\(start) - \(end)"
    }

    private func moveWeek(by value: Int) {
        guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: value, to: selection.start) else {
            return
        }

        selection = WeekRange(start: nextWeek, calendar: calendar)
    }
}


// MARK: - Controles do dashboard (Cápsula única unificada)

private struct DashboardToolbarControls: View {
    let teamNames: [String]
    @Binding var searchText: String

    @State private var isSortPopoverPresented = false
    @State private var isFilterPopoverPresented = false
    @State private var isSearchExpanded = false
    @State private var isHistoryPopoverPresented = false
    @State private var sortOption: SortOption = .oldest
    @State private var selectedPeople: Set<String> = ["Leonardo Drummond", "Eduarda Vieira"]
    @State private var selectedSubjects: Set<String> = ["Pagamentos", "Entregas"]
    @State private var selectedTeams: Set<String> = ["Atendimento"]
    @FocusState private var isSearchFocused: Bool
    @ObservedObject private var recentSearchesStore = RecentSearchesStore.shared

    var body: some View {
        HStack(spacing: 0) {
            // 1. Filtrar
            DashboardToolbarIconButton(systemImage: "line.3.horizontal.decrease", accessibilityLabel: "Filtrar") {
                isFilterPopoverPresented.toggle()
                isSortPopoverPresented = false
                isHistoryPopoverPresented = false
            }
            .popover(
                isPresented: $isFilterPopoverPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                FilterPopover(
                    selectedPeople: $selectedPeople,
                    selectedSubjects: $selectedSubjects,
                    selectedTeams: $selectedTeams,
                    teams: teamNames
                )
            }

            Divider()
                .frame(height: 18)

            // 2. Ordenar
            DashboardToolbarIconButton(systemImage: "arrow.up.arrow.down", accessibilityLabel: "Ordenar") {
                isSortPopoverPresented.toggle()
                isFilterPopoverPresented = false
                isHistoryPopoverPresented = false
            }
            .popover(
                isPresented: $isSortPopoverPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                SortPopover(selection: $sortOption)
            }

            Divider()
                .frame(height: 18)

            // 3. Buscar (Lupa compacta que expande dentro da mesma cápsula)
            if isSearchExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
//                        .font(.caption.weight(.semibold))
                        .adaptiveTextStyle(.caption)
                        .fontWeight(Font.Weight.semibold)
                        .foregroundStyle(Color.Token.interactiveAccent)
                        .padding(.leading, 8)

                    TextField("Buscar cards…", text: $searchText)
                        .textFieldStyle(.plain)
//                        .font(.callout)
                        .adaptiveTextStyle(.callout)
                        .foregroundStyle(Color.Token.textPrimary)
                        .focused($isSearchFocused)
                        .frame(minWidth: 160, idealWidth: 200)
                        .onSubmit {
                            RecentSearchesStore.shared.addSearch(searchText)
                            isHistoryPopoverPresented = false
                        }
                        .onChange(of: isSearchFocused) { _, focused in
                            if focused && !recentSearchesStore.recentSearches.isEmpty {
                                isHistoryPopoverPresented = true
                            }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
//                                .font(.caption)
                                .adaptiveTextStyle(.caption)
                                .foregroundStyle(Color.Token.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            isSearchExpanded = false
                            isSearchFocused = false
                            isHistoryPopoverPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark")
//                            .font(.caption2.weight(.bold))
                            .adaptiveTextStyle(.caption2)
                            .fontWeight(.bold)
                            .fontWeight(Font.Weight.bold)
                            .foregroundStyle(Color.Token.textSecondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar busca")
                    .padding(.trailing, 4)
                }
                .popover(
                    isPresented: Binding(
                        get: { isSearchExpanded && isHistoryPopoverPresented && !recentSearchesStore.recentSearches.isEmpty },
                        set: { isHistoryPopoverPresented = $0 }
                    ),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    SearchHistoryPopover(
                        recentSearches: recentSearchesStore.filteredSuggestions(for: searchText),
                        onSelect: { term in
                            searchText = term
                            recentSearchesStore.addSearch(term)
                            isHistoryPopoverPresented = false
                        },
                        onDelete: { term in
                            recentSearchesStore.removeSearch(term)
                        },
                        onClearAll: {
                            recentSearchesStore.clearAllSearches()
                            isHistoryPopoverPresented = false
                        }
                    )
                    .frame(width: 280)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)),
                    removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .trailing))
                ))
            } else {
                DashboardToolbarIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Buscar") {
                    withAnimation(.snappy(duration: 0.22)) {
                        isSearchExpanded = true
                    }
                    isSearchFocused = true
                    if !recentSearchesStore.recentSearches.isEmpty {
                        isHistoryPopoverPresented = true
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(3)
        .background {
            if #available(macOS 26.0, *) {
                Capsule(style: .continuous)
                    .glassEffect(.regular, in: .capsule)
            } else {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    }
            }
        }
        .animation(.snappy(duration: 0.22), value: isSearchExpanded)
    }
}

// MARK: - Popover de Histórico de Pesquisas

private struct SearchHistoryPopover: View {
    let recentSearches: [String]
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pesquisas Recentes")
//                    .font(.caption.weight(.semibold))
                    .adaptiveTextStyle(.caption)
                    .fontWeight(Font.Weight.semibold)
                    .foregroundStyle(Color.Token.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button("Limpar Tudo", action: onClearAll)
//                    .font(.caption.weight(.medium))
                    .adaptiveTextStyle(.caption)
                    .fontWeight(Font.Weight.medium)
                    .foregroundStyle(Color.Token.interactiveAccent)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(recentSearches.enumerated()), id: \.element) { index, item in
                        SearchHistoryRow(
                            text: item,
                            isLast: index == recentSearches.count - 1,
                            onTap: { onSelect(item) },
                            onDelete: { onDelete(item) }
                        )
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(.vertical, 4)
    }
}

private struct SearchHistoryRow: View {
    let text: String
    let isLast: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
//                    .font(.callout)
                    .adaptiveTextStyle(.callout)
                    .foregroundStyle(Color.Token.textSecondary)

                Text(text)
//                    .font(.callout)
                    .adaptiveTextStyle(.callout)
                    .foregroundStyle(Color.Token.textPrimary)
                    .lineLimit(1)

                Spacer()

                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
//                            .font(.caption2.weight(.bold))
                            .adaptiveTextStyle(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.Token.textSecondary)
                            .frame(width: 18, height: 18)
                            .background(Color.Token.surfaceRaised, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.Token.surfaceRaised.opacity(0.6) : Color.clear)
        .onHover { isHovering = $0 }

        if !isLast {
            Divider()
                .padding(.leading, 38)
        }
    }
}

private struct DashboardToolbarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DashboardRefreshStatusView: View {
    let isRefreshing: Bool
    let lastUpdated: Date?
    let onRefresh: () -> Void
    @Environment(\.appTheme) private var theme

    private var formattedDate: String {
        guard let lastUpdated else {
            return "Sincronizado recentemente"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d 'de' MMMM, HH:mm'h'"
        return "Última atualização em \(formatter.string(from: lastUpdated))"
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
//                            .font(.caption2)
                            .adaptiveTextStyle(.caption2)
                    }
                    Text(isRefreshing ? "Atualizando…" : "Atualizar")
                }
            }
//            .font(.caption.weight(.semibold))
            .adaptiveTextStyle(.caption)
            .fontWeight(Font.Weight.semibold)
            .underline(!isRefreshing)
            .buttonStyle(.plain)
            .foregroundStyle(theme.accentColor)
            .disabled(isRefreshing)

            Text(formattedDate)
//                .font(.caption2)
                .adaptiveTextStyle(.caption2)
                .foregroundStyle(Color.Token.textSecondary)
        }
        .frame(minWidth: 235, alignment: .trailing)
    }
}

private struct DashboardToolbarPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
//                    .font(.body.weight(.semibold))
                    .adaptiveTextStyle(.body)
                    .fontWeight(.semibold)

                Text(title)
//                    .font(.body.weight(.semibold))
                    .adaptiveTextStyle(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.Token.textOnAccent)
            .padding(.horizontal, 18)
            .frame(minWidth: 136)
            .frame(height: 48)
            .background(Capsule().fill(theme.accentColor))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .shadow(color: Color.Token.interactiveAccent.opacity(0.16), radius: 4, y: 2)
        .accessibilityLabel(title)
    }
}

struct NewBoardItemSheet: View {
    let teamNames: [String]
    let createItem: (BoardItemDraft, String, DashboardItemCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = BoardItemDraft()
    @State private var assigneesText = ""
    @State private var selectedTeam = ""
    @State private var selectedCategory: DashboardItemCategory = .meeting
    @State private var scheduledDate = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Novo item")
//                .font(.title2.weight(.semibold))
                .adaptiveTextStyle(.title2)
                .fontWeight(.semibold)

            ScrollView {
                Form {
                    TextField("Título", text: $draft.title)
                    TextField("Responsáveis", text: $assigneesText)
                    DatePicker(
                        "Data e hora",
                        selection: $scheduledDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    TextField("Local", text: $draft.location)

                    Picker("Time", selection: $selectedTeam) {
                        ForEach(teamNames, id: \.self) { team in
                            Text(team.capitalized).tag(team)
                        }
                    }

                    Picker("Tipo", selection: $selectedCategory) {
                        ForEach(DashboardItemCategory.allCases, id: \.self) { category in
                            Text(category.title).tag(category)
                        }
                    }

                    BoardItemPriorityPicker(selection: $draft.priority)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Descrição")
                        TextEditor(text: $draft.description)
//                            .font(.body)
                            .adaptiveTextStyle(.body)
                            .frame(height: 150)
                            .accessibilityLabel("Descrição")
                    }
                }
                .formStyle(.grouped)
            }
            .frame(maxHeight: 500)

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) {
                    dismiss()
                }
                Button("Criar item") {
                    draft.assignees = assignees(from: assigneesText)
                    draft.scheduledAt = scheduledDate
                    createItem(draft, selectedTeam, selectedCategory)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTeam.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460, height: 670)
        .onAppear {
            selectedTeam = teamNames.first ?? ""
        }
    }
}


// MARK: - Board (colunas estilo Kanban)

struct BoardView: View {
    let columns: [BoardColumn]
    let filter: DashboardItemCategory?
    let searchText: String
    let selectedWeek: WeekRange
    let people: [PersonDTO]
    let markAsReviewed: (BoardItem.ID, BoardColumn.ID) -> Void
    let updateItem: (BoardItem.ID, BoardColumn.ID, BoardItemDraft) -> Void
    let archiveItem: (BoardItem.ID, BoardColumn.ID) -> Void
    let deleteItem: (BoardItem.ID, BoardColumn.ID) -> Void
    @State private var selectedTeam: TeamDetail?
    @State private var itemPendingDeletion: PendingDeletion?

    var body: some View {
        // Altura mínima confortável para o board, sem cortar cards em telas comuns.
        // Em janelas muito altas o board cresce junto, evitando desperdiçar espaço
        // sem prender o usuário a um valor fixo pequeno demais.
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 32) {
                ForEach(columns) { rawColumn in
                    let displayColumn = rawColumn.filtered(by: filter, matching: searchText, in: selectedWeek)
                    BoardColumnView(
                        column: displayColumn,
                        people: people,
                        onSelectTeam: {
                            selectedTeam = TeamDetail(column: rawColumn, people: people)
                        },
                        markAsReviewed: { itemID in
                            markAsReviewed(itemID, rawColumn.id)
                        },
                        updateItem: { itemID, draft in
                            updateItem(itemID, rawColumn.id, draft)
                        },
                        archiveItem: { itemID in
                            archiveItem(itemID, rawColumn.id)
                        },
                        requestDeletion: { item in
                            itemPendingDeletion = PendingDeletion(item: item, columnID: rawColumn.id)
                        }
                    )
                        .frame(width: 320)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(minHeight: 520)
        .sheet(item: $selectedTeam) { team in
            TeamDetailSheet(team: team)
        }
        .alert("Excluir card?", isPresented: Binding(
            get: { itemPendingDeletion != nil },
            set: { if !$0 { itemPendingDeletion = nil } }
        ), presenting: itemPendingDeletion) { pendingDeletion in
            Button("Excluir", role: .destructive) {
                deleteItem(pendingDeletion.item.id, pendingDeletion.columnID)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { pendingDeletion in
            Text("\"\(pendingDeletion.item.title)\" será movido para Excluídos e poderá ser restaurado por até 7 dias.")
        }
    }
}

private struct StoredItemsBoardView: View {
    let items: [StoredBoardItem]
    let title: String
    let actionTitle: String
    let actionSystemImage: String
    let action: (StoredBoardItem) -> Void

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "Nenhum card \(title.lowercased())",
                systemImage: "tray"
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 32) {
                    ForEach(teamNames, id: \.self) { teamName in
                        let teamItems = items.filter { $0.teamName == teamName }
                        if !teamItems.isEmpty {
                            StoredItemsColumnView(
                                teamName: teamName,
                                items: teamItems,
                                timestampTitle: title,
                                actionTitle: actionTitle,
                                actionSystemImage: actionSystemImage,
                                action: action
                            )
                                .frame(width: 320)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .frame(minHeight: 520)
        }
    }

    private var teamNames: [String] {
        Array(Set(items.map(\.teamName))).sorted()
    }
}

private struct StoredItemsColumnView: View {
    let teamName: String
    let items: [StoredBoardItem]
    let timestampTitle: String
    let actionTitle: String
    let actionSystemImage: String
    let action: (StoredBoardItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(teamName.capitalized)
                .font(.headline)
                .foregroundStyle(Color.Token.textPrimary)
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { storedItem in
                        StoredBoardItemCard(
                            item: storedItem,
                            timestampTitle: timestampTitle,
                            actionTitle: actionTitle,
                            actionSystemImage: actionSystemImage,
                            action: { action(storedItem) }
                        )
                    }
                }
            }
        }
    }
}

private struct StoredBoardItemCard: View {
    let item: StoredBoardItem
    let timestampTitle: String
    let actionTitle: String
    let actionSystemImage: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.item.title)
//                .font(.subheadline.weight(.semibold))
                .adaptiveTextStyle(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.Token.textPrimary)
            if let description = item.item.descriptionText {
                Text(description)
                    .adaptiveTextStyle(.caption)
                    .foregroundStyle(Color.Token.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.item.assignees.isEmpty {
                Text(item.item.assignees.map(\.name).joined(separator: ", "))
                    .adaptiveTextStyle(.caption)                    .foregroundStyle(Color.Token.textSecondary)
            }
            Label(
                "\(timestampTitle) \(item.storedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))",
                systemImage: "calendar"
            )
            .adaptiveTextStyle(.caption)            .foregroundStyle(Color.Token.textSecondary)
            Button(actionTitle, systemImage: actionSystemImage, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCardModifier())
    }
}

private struct PendingDeletion: Identifiable {
    let item: BoardItem
    let columnID: BoardColumn.ID

    var id: BoardItem.ID { item.id }
}

struct BoardColumnView: View {
    let column: BoardColumn
    let people: [PersonDTO]
    let onSelectTeam: () -> Void
    let markAsReviewed: (BoardItem.ID) -> Void
    let updateItem: (BoardItem.ID, BoardItemDraft) -> Void
    let archiveItem: (BoardItem.ID) -> Void
    let requestDeletion: (BoardItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onSelectTeam) {
                Text(column.title.capitalized)
//                    .font(.headline)
                    .adaptiveTextStyle(.headline)
                    .foregroundStyle(Color.Token.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Image(systemName: "arrow.down.left.and.arrow.up.right")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre os detalhes da equipe \(column.title)")

            Divider()

            if column.items.isEmpty {
                EmptyColumnView()
            } else {
                // Lista vertical rolável independente do scroll horizontal do board,
                // garantindo que cards longos não sejam cortados em janelas baixas.
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(column.items) { item in
                            BoardItemCardView(
                                item: item,
                                people: people,
                                markAsReviewed: markAsReviewed,
                                updateItem: updateItem,
                                archiveItem: archiveItem,
                                requestDeletion: requestDeletion
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyColumnView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wind")
//                .font(.largeTitle.weight(.light))
                .adaptiveTextStyle(.largeTitle)
                .fontWeight(Font.Weight.light)
                .foregroundStyle(Color.Token.textSecondary)
            Text("Tudo calmo por aqui!")
//                .font(.subheadline)
                .adaptiveTextStyle(.subheadline)
                .foregroundStyle(Color.Token.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
        .padding(.top, 24)
    }
}

// MARK: - Card de item, com material Liquid Glass

struct BoardItemCardView: View {
    let item: BoardItem
    let people: [PersonDTO]
    let markAsReviewed: (BoardItem.ID) -> Void
    let updateItem: (BoardItem.ID, BoardItemDraft) -> Void
    let archiveItem: (BoardItem.ID) -> Void
    let requestDeletion: (BoardItem) -> Void
    @State private var isEditing = false

    /// Cards pendentes de revisão sempre usam uma superfície clara, inclusive
    /// no Dark Mode. Por isso, não podem herdar os tokens adaptativos de texto.
    private var titleColor: Color {
        item.isAwaitingReview ? .black.opacity(0.88) : Color.Token.textPrimary
    }

    private var supportingTextColor: Color {
        item.isAwaitingReview ? .black.opacity(0.64) : Color.Token.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                BoardItemPriorityTag(priority: item.priority)

                Spacer(minLength: 8)

                cardActions
            }

            Text(item.title)
//                .font(.subheadline.weight(.semibold))
                .adaptiveTextStyle(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(titleColor)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if let description = item.descriptionText {
                Text(description)
//                    .font(.caption)
                    .adaptiveTextStyle(.caption)
                    .foregroundStyle(supportingTextColor)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)

                if description.count > 120 {
                    Button("Ler mais") {
                        isEditing = true
                    }
//                    .font(.caption.weight(.semibold))
                    .adaptiveTextStyle(.caption)
                    .fontWeight(.semibold)
                    .buttonStyle(.link)
                    .accessibilityHint("Abre o card com a descrição completa")
                }
            }

            if let assignee = item.assignees.first {
                MetadataRow(
                    systemImage: assignee.isGroup ? "person.2.fill" : "person.fill",
                    text: item.assignees.count == 1 ? assignee.name : "\(assignee.name) +\(item.assignees.count - 1)",
                    textColor: supportingTextColor
                )
            }

            if let dateText = item.dateText {
                MetadataRow(
                    systemImage: "calendar",
                    text: item.isRescheduled ? "Nova data: \(dateText)" : dateText,
                    highlighted: item.isRescheduled && !item.isAwaitingReview,
                    textColor: supportingTextColor
                )
            }

            if let location = item.location {
                MetadataRow(
                    systemImage: "mappin.and.ellipse",
                    text: location,
                    textColor: supportingTextColor
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(BoardItemCardModifier(isAwaitingReview: item.isAwaitingReview))
        .sheet(isPresented: $isEditing) {
            BoardItemEditorSheet(item: item, people: people) { draft in
                updateItem(item.id, draft)
            }
        }
    }

    @ViewBuilder
    private var cardActions: some View {
        if item.isAwaitingReview {
            UnreadCardActionsView {
                isEditing = true
            } markAsReviewed: {
                markAsReviewed(item.id)
            }
        } else {
            Menu {
                Button("Editar", systemImage: "pencil") {
                    isEditing = true
                }
                Button("Arquivar", systemImage: "archivebox") {
                    archiveItem(item.id)
                }
                Button("Excluir", systemImage: "trash", role: .destructive) {
                    requestDeletion(item)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct UnreadCardActionsView: View {
    let edit: () -> Void
    let markAsReviewed: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: edit) {
                Image(systemName: "pencil")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.Token.surfaceRaised, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Editar")

            Button(action: markAsReviewed) {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.Token.textOnAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.Token.statusSuccess, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Marcar como revisado")
        }
        .buttonStyle(.plain)
    }
}

struct BoardItemCardModifier: ViewModifier {
    let isAwaitingReview: Bool
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                if isAwaitingReview {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.newCardFillColor)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.boardItemCard)
                }
            }
            .overlay {
                if isAwaitingReview {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            theme.newCardStrokeColor,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }
            }
            .shadow(
                color: Color.black.opacity(0.06),
                radius: 3,
                x: 0,
                y: 2
            )
    }
}

extension View {
    func boardItemCardStyle(isAwaitingReview: Bool = false) -> some View {
        self.modifier(BoardItemCardModifier(isAwaitingReview: isAwaitingReview))
    }
}


private struct BoardItemEditorSheet: View {
    let item: BoardItem
    let people: [PersonDTO]
    let save: (BoardItemDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: BoardItemDraft
    @State private var selectedPersonID: UUID?

    init(item: BoardItem, people: [PersonDTO], save: @escaping (BoardItemDraft) -> Void) {
        self.item = item
        self.people = people
        self.save = save
        _draft = State(initialValue: BoardItemDraft(item: item))
        _selectedPersonID = State(initialValue: people.first(where: { person in
            guard let id = person.id else { return false }
            return item.assignees.contains { assignee in
                assignee.name == person.name || assignee.name.hasPrefix("\(person.name) &")
            } && id == person.id
        })?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Editar card")
//                .font(.title2.weight(.semibold))
                .adaptiveTextStyle(.title2)
                .fontWeight(.semibold)

            ScrollView {
                Form {
                    Section {
                        TextField("Título", text: $draft.title)
                        Picker("Responsável", selection: $selectedPersonID) {
                            Text("Sem responsável").tag(UUID?.none)
                            ForEach(availablePeople, id: \.id) { person in
                                Text(person.name).tag(Optional(person.id!))
                            }
                        }
                    }

                    Section("Agendamento") {
                        DatePicker(
                            "Data",
                            selection: $draft.scheduledAt,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)

                        DatePicker(
                            "Horário",
                            selection: $draft.scheduledAt,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                    }

                    Section {
                        TextField("Local", text: $draft.location)
                        BoardItemPriorityPicker(selection: $draft.priority)
                    }

                    Section("Descrição") {
                        TextEditor(text: $draft.description)
//                            .font(.body)
                            .adaptiveTextStyle(.body)
                            .frame(height: 150)
                            .accessibilityLabel("Descrição")
                    }
                }
                .formStyle(.grouped)
            }
            .frame(maxHeight: 400)

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) {
                    dismiss()
                }
                Button("Salvar") {
                    draft.assigneeID = selectedPersonID
                    draft.assignees = availablePeople
                        .first(where: { $0.id == selectedPersonID })
                        .map { [Assignee(name: $0.name, isGroup: false)] } ?? []
                    save(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460, height: 600)
    }

    private var availablePeople: [PersonDTO] {
        people
            .filter { $0.active && $0.id != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private func assignees(from names: String) -> [Assignee] {
    names
        .split(separator: ",")
        .map { name in
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            return Assignee(name: trimmedName, isGroup: trimmedName.contains("&"))
        }
}

private struct BoardItemPriorityPicker: View {
    @Binding var selection: BoardItemPriority

    var body: some View {
        Picker("Prioridade", selection: $selection) {
            ForEach(BoardItemPriority.allCases) { priority in
                BoardItemPriorityTag(priority: priority)
                    .tag(priority)
            }
        }
    }
}

private struct BoardItemPriorityTag: View {
    let priority: BoardItemPriority

    private var accentColor: Color {
        switch priority {
        case .high: Color.alta
        case .medium: Color.media
        case .low: Color.baixa
        case .unset: Color.definirPrioridade
        }
    }

    private var backgroundColor: Color {
        switch priority {
        case .high: Color.alta.opacity(0.5)
        case .medium: Color.media.opacity(0.5)
        case .low: Color.baixa.opacity(0.5)
        case .unset: Color.definirPrioridade.opacity(0.5)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)

            Text(priority.title)
//                .font(.caption.weight(.medium))
                .adaptiveTextStyle(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.textPriorityTag)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor, in: Capsule(style: .continuous))
    }
}

private struct MetadataRow: View {
    let systemImage: String
    let text: String
    var highlighted: Bool = false
    var textColor: Color = Color.Token.textSecondary
    
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
//                .font(.caption)
                .adaptiveTextStyle(.caption)
                .foregroundStyle(theme.accentColor)
            Text(text)
//                .font(.caption.weight(highlighted ? .semibold : .regular))
                .adaptiveTextStyle(.caption)
                .fontWeight(highlighted ? .semibold : .regular)
                .foregroundStyle(highlighted ? Color.Token.statusAttention : textColor)
        }
    }
}

// MARK: - Modificadores de "Liquid Glass"
//
// As APIs `glassEffect(_:in:)` e `GlassEffectContainer` (introduzidas nas
// plataformas Apple de 2025/2026) aplicam o material translúcido "Liquid
// Glass" recomendado pela HIG para superfícies de controle e cards
// flutuantes. Os modificadores abaixo encapsulam o uso correto (incluindo
// o agrupamento via `GlassEffectContainer`, necessário para transições
// suaves entre elementos de vidro adjacentes) e caem para `.ultraThinMaterial`
// em versões de sistema anteriores, preservando a aparência em ambos os casos.

/// Container que agrupa elementos de vidro adjacentes, permitindo que o
/// sistema funda/anime as formas entre si (comportamento nativo do
/// Liquid Glass). Faz fallback para um `HStack` simples em versões antigas.
struct GlassEffectContainerCompat<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

/// Aplica o efeito de vidro em forma de "pílula" (cápsula), usado em
/// botões e no campo de busca.
struct GlassPillModifier: ViewModifier {
    let tint: Color?
    let isSelected: Bool
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(
                    tint.map { .regular.tint($0).interactive() } ?? .regular.interactive(),
                    in: .capsule
                )
        } else {
            content
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            tint != nil
                            ? AnyShapeStyle(tint!.gradient)
                            : AnyShapeStyle(.ultraThinMaterial)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}

/// Aplica o efeito de vidro em cards retangulares de conteúdo (colunas do board).
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )
//                .shadow(color: .red.opacity(0.06), radius: 6, y: 2)
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .frame(minWidth: 1200, minHeight: 800)
}
