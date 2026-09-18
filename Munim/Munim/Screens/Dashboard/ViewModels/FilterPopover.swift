import SwiftUI

/// Painel de filtros reutilizável para as ações de filtro do dashboard.
struct FilterPopover: View {
    @Binding var selectedPeople: Set<String>
    @Binding var selectedSubjects: Set<String>
    @Binding var selectedTeams: Set<String>
    let teams: [String]

    @State private var peopleSearchText = ""
    @State private var teamsSearchText = ""

    private let people = ["Leonardo Drummond", "Eduarda Vieira"]

    private var visiblePeople: [String] {
        people.filter { peopleSearchText.isEmpty || $0.localizedCaseInsensitiveContains(peopleSearchText) }
    }

    private var visibleTeams: [String] {
        teams.filter { teamsSearchText.isEmpty || $0.localizedCaseInsensitiveContains(teamsSearchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filtrar por")
//                .font(.headline)
                .adaptiveTextStyle(.headline)

            Divider()

            filterSection(title: "Pessoas") {
                FilterSearchField(placeholder: "Pesquisar pessoas", text: $peopleSearchText)
                FlowLayout(spacing: 6) {
                    ForEach(visiblePeople, id: \.self) { person in
                        FilterChip(title: person, isSelected: selectedPeople.contains(person), showsCloseButton: true) {
                            toggle(person, in: &selectedPeople)
                        }
                    }
                }
            }

            filterSection(title: "Assuntos") {
                FlowLayout(spacing: 6) {
                    ForEach(FilterSubject.allCases) { subject in
                        FilterChip(
                            title: subject.title,
                            isSelected: selectedSubjects.contains(subject.rawValue),
                            showsCloseButton: false
                        ) {
                            toggle(subject.rawValue, in: &selectedSubjects)
                        }
                    }
                }
            }

            if !teams.isEmpty {
                filterSection(title: "Equipes") {
                    FilterSearchField(placeholder: "Pesquisar equipes e grupos", text: $teamsSearchText)
                    FlowLayout(spacing: 6) {
                        ForEach(visibleTeams, id: \.self) { team in
                            FilterChip(title: team, isSelected: selectedTeams.contains(team), showsCloseButton: true) {
                                toggle(team, in: &selectedTeams)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 366)
    }

    private func filterSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
//                .font(.subheadline.weight(.medium))
                .adaptiveTextStyle(.subheadline)
                .fontWeight(.medium)
            content()
        }
    }

    private func toggle(_ value: String, in selection: inout Set<String>) {
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }
}

struct FilterSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
//                .font(.caption)
                .adaptiveTextStyle(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
//        .font(.caption)
        .adaptiveTextStyle(.caption)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.Token.interactiveAccent.opacity(0.09)))
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let showsCloseButton: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsCloseButton, isSelected {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                } else {
                    Circle()
                        .fill(isSelected ? Color.Token.textOnAccent : Color.Token.interactiveAccent.opacity(0.28))
                        .overlay {
                            if !isSelected {
                                Circle().stroke(Color.Token.interactiveAccent.opacity(0.8), lineWidth: 1)
                            }
                        }
                        .frame(width: 10, height: 10)
                }

                Text(title)
                    .lineLimit(1)
            }
//            .font(.caption)
            .adaptiveTextStyle(.caption)
            .foregroundStyle(isSelected ? Color.Token.textOnAccent : .primary)
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(isSelected ? Color.Token.interactiveAccent : Color.Token.interactiveAccent.opacity(0.09)))
        .accessibilityValue(isSelected ? "Selecionado" : "Não selecionado")
    }
}
