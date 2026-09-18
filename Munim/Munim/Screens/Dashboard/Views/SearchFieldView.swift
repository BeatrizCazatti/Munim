import SwiftUI

/// Campo de pesquisa customizado com sugestões em tempo real e histórico de pesquisas recentes.
struct SearchFieldView: View {
    @Binding var searchText: String
    @StateObject private var recentSearchesStore = RecentSearchesStore.shared
    @State private var isFocused: Bool = false
    @State private var showSuggestions: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var placeholder: LocalizedStringKey = "Buscar cards, pessoas e locais"
    var onSearchSubmit: (() -> Void)?
    var onSearchChange: ((String) -> Void)?

    private var filteredSuggestions: [String] {
        recentSearchesStore.filteredSuggestions(for: searchText)
    }

    private var showRecentSearches: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isFocused
    }

    private var showFilteredSuggestions: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isFocused
    }

    var body: some View {
        VStack(spacing: 0) {
            // Campo de texto principal
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
//                    .font(.body.weight(.medium))
                    .adaptiveTextStyle(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(isFocused ? Color.Token.interactiveAccent : Color.Token.textSecondary)

                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
//                    .font(.body)
                    .adaptiveTextStyle(.body)
                    .foregroundStyle(Color.Token.textPrimary)
                    .focused($isTextFieldFocused)
                    .onChange(of: searchText) { _, newValue in
                        onSearchChange?(newValue)
                        // Mostra sugestões quando começa a digitar
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showSuggestions = true
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showSuggestions = false
                            }
                        }
                    }
                    .onSubmit {
                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            recentSearchesStore.addSearch(searchText)
                            onSearchSubmit?()
                        }
                    }

                // Botão de limpar (X) - aparece quando há texto
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showSuggestions = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
//                            .font(.body.weight(.medium))
                            .adaptiveTextStyle(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.Token.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.Token.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isFocused ? Color.Token.interactiveAccent.opacity(0.5) : Color.Token.borderSubtle,
                                lineWidth: isFocused ? 1.5 : 1
                            )
                    )
            )
            .onTapGesture {
                isTextFieldFocused = true
            }

            // Painel de sugestões/histórico
            if showSuggestions && isFocused {
                VStack(spacing: 0) {
                    if showFilteredSuggestions && !filteredSuggestions.isEmpty {
                        // Sugestões filtradas
                        SearchSuggestionsSection(
                            title: "Sugestões de Pesquisa",
                            items: filteredSuggestions,
                            onSelect: { suggestion in
                                searchText = suggestion
                                recentSearchesStore.addSearch(suggestion)
                                onSearchSubmit?()
                                isTextFieldFocused = false
                            },
                            onDelete: { suggestion in
                                recentSearchesStore.removeSearch(suggestion)
                            }
                        )
                    } else if showRecentSearches && !recentSearchesStore.recentSearches.isEmpty {
                        // Pesquisas recentes
                        SearchSuggestionsSection(
                            title: "Pesquisas Recentes",
                            items: recentSearchesStore.recentSearches,
                            showClearAll: true,
                            onSelect: { suggestion in
                                searchText = suggestion
                                recentSearchesStore.addSearch(suggestion)
                                onSearchSubmit?()
                                isTextFieldFocused = false
                            },
                            onDelete: { suggestion in
                                recentSearchesStore.removeSearch(suggestion)
                            },
                            onClearAll: {
                                recentSearchesStore.clearAllSearches()
                            }
                        )
                    } else if showRecentSearches && recentSearchesStore.recentSearches.isEmpty {
                        // Estado vazio
                        EmptyRecentSearchesView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98))
                ))
                .zIndex(1)
            }
        }
        .onChange(of: isTextFieldFocused) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                isFocused = newValue
                if !newValue {
                    showSuggestions = false
                }
            }
        }
        .onAppear {
            isFocused = isTextFieldFocused
        }
    }
}

// MARK: - Subviews de Suporte

/// Seção de sugestões/pesquisas recentes
private struct SearchSuggestionsSection: View {
    let title: String
    let items: [String]
    var showClearAll: Bool = false
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    var onClearAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cabeçalho com título e botão "Limpar Tudo"
            HStack {
                Text(title)
//                    .font(.caption.weight(.semibold))
                    .adaptiveTextStyle(.caption)
                    .fontWeight(Font.Weight.semibold)
                    .foregroundStyle(Color.Token.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if showClearAll {
                    Button("Limpar Tudo", action: onClearAll ?? {})
//                        .font(.caption.weight(.medium))
                        .adaptiveTextStyle(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.Token.interactiveAccent)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.Token.backgroundPrimary)

            Divider()
                .padding(.leading, 12)

            // Lista de itens
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                SearchSuggestionRow(
                    text: item,
                    isLast: index == items.count - 1,
                    onTap: { onSelect(item) },
                    onDelete: { onDelete(item) }
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.Token.backgroundPrimary)
                .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.Token.borderSubtle, lineWidth: 0.5)
        )
        .padding(.top, 6)
    }
}

/// Linha individual de sugestão/histórico
private struct SearchSuggestionRow: View {
    let text: String
    let isLast: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
//                    .font(.subheadline.weight(.medium))
                    .adaptiveTextStyle(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Token.iconAccent)
                    .frame(width: 20)

                Text(text)
//                    .font(.subheadline)
                    .adaptiveTextStyle(.subheadline)

                    .foregroundStyle(Color.Token.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Botão de excluir (X) - aparece no hover
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
//                            .font(.caption2.weight(.semibold))
                            .adaptiveTextStyle(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Token.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Color.Token.surfaceRaised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isHovering ? Color.Token.surfaceRaised.opacity(0.5) : Color.clear
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }

        if !isLast {
            Divider()
                .padding(.leading, 42)
        }
    }
}

/// View para estado vazio de pesquisas recentes
private struct EmptyRecentSearchesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
//                .font(.title.weight(.light))
                .adaptiveTextStyle(.title)
                .fontWeight(.light)
                .foregroundStyle(Color.Token.textSecondary.opacity(0.5))

            Text("Nenhuma pesquisa recente")
//                .font(.subheadline.weight(.medium))
                .adaptiveTextStyle(.subheadline)
                .fontWeight(Font.Weight.medium)
                .foregroundStyle(Color.Token.textSecondary)

            Text("Suas pesquisas aparecerão aqui")
//                .font(.caption)
                .adaptiveTextStyle(.caption)
                .foregroundStyle(Color.Token.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.Token.backgroundPrimary)
                .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.Token.borderSubtle, lineWidth: 0.5)
        )
        .padding(.top, 6)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var searchText = ""

    SearchFieldView(searchText: $searchText)
        .padding(24)
        .frame(width: 400)
        .background(Color.Token.backgroundPrimary)
}
