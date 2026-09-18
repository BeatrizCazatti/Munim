import SwiftUI


// MARK: - Sidebar recolhível

/// Sidebar de navegação seguindo o padrão `NavigationSplitView` do macOS,
/// que já oferece o botão nativo de recolher/expandir na toolbar.
struct SidebarView: View {
    @Binding var selection: SidebarDestination?
    @Environment(\.openWindow) private var openWindow
    @State private var isHistoryExpanded: Bool = true

    var body: some View {
        List(selection: $selection) {
            // Dashboard com disclosure agrupando Arquivados e Excluídos
            DisclosureGroup(isExpanded: $isHistoryExpanded) {
                NavigationLink(value: SidebarDestination.archived) {
                    Label("Arquivados", systemImage: "archivebox")
                        .adaptiveTextStyle(.caption)
                }
                .padding(.leading, 8)

                NavigationLink(value: SidebarDestination.deleted) {
                    Label("Excluídos", systemImage: "trash")
                        .adaptiveTextStyle(.caption)
                }
                .padding(.leading, 8)
            } label: {
                NavigationLink(value: SidebarDestination.dashboard) {
                    Label("Dashboard", systemImage: "house")
                        .adaptiveTextStyle(.caption)
                }
            }

            NavigationLink(value: SidebarDestination.attachments) {
                Label("Anexos", systemImage: "folder")
                    .adaptiveTextStyle(.caption)
            }
        }
        .listStyle(.sidebar)
        // Material translúcido (efeito "Liquid Glass") para que o gradiente
        // do tema, aplicado por trás no nível do NavigationSplitView, fique
        // visível através da coluna da sidebar. `.ultraThinMaterial` é o
        // fallback oficial do projeto para glassEffect em versões anteriores.
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .navigationTitle("Painel")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Configurações (⌘,)")
                .accessibilityLabel("Configurações")
            }
        }
    }
}
