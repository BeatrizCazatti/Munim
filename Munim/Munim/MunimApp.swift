import SwiftUI

@main
struct MunimApp: App {
    @AppStorage(AppTheme.storageKey) private var storedTheme = AppTheme.defaultTheme.rawValue
    @AppStorage(InterfaceAppearance.storageKey) private var storedAppearance = InterfaceAppearance.system.rawValue

    // MARK: - Serviços globais
    @State private var authService = AuthService()

    private var theme: AppTheme {
        AppTheme(storedValue: storedTheme)
    }

    private var appearance: InterfaceAppearance {
        InterfaceAppearance(rawValue: storedAppearance) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            AppFlowView(authService: authService, onOpenURL: handleDeepLink)
                .environment(authService)
                .environment(\.appTheme, theme)
                .tint(theme.accentColor)
                .dynamicTypeSize(.large ... .accessibility2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Captura munim://auth/callback?token=...
                // A rota /api/auth/google/auth-url já inclui escopos de Directory
                // e Google Chat quando a organização ainda não tem integração conectada
                // (loginPlusAdmin). Não há tela intermediária de "conectar workspace".
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }

        Window("Configurações", id: "settings") {
            SettingsWindow()
                .environment(authService)
                .environment(\.appTheme, theme)
                .tint(theme.accentColor)
                .dynamicTypeSize(.large ... .accessibility2)
        }
        .windowResizability(.contentMinSize)

//        Window("Diagnóstico & Debug", id: "debug-inspector") {
//            DebugInspectorView()
//                .environment(authService)
//        }
//        .windowResizability(.contentMinSize)
//        .commands {
//            CommandGroup(after: .appSettings) {
//                Button("Configurações…") {
//                    NSApp.sendAction(
//                        Selector(("showSettingsWindow:")),
//                        to: nil,
//                        from: nil
//                    )
//                }
//                .keyboardShortcut(",", modifiers: .command)
//
//                Button("Diagnóstico & Debug…") {
//                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "debug-inspector" }) {
//                        window.makeKeyAndOrderFront(nil)
//                    } else {
//                        NSApp.sendAction(
//                            #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
//                            to: nil,
//                            from: nil
//                        )
//                    }
//                }
//                .keyboardShortcut("d", modifiers: [.command, .option])
//            }
//        }
    }

    // MARK: - Processamento do deep-link OAuth
    //
    // O backend emite o JWT via HTML redirect para munim://auth/callback?token=...
    // No primeiro login (org sem integração), o backend também salva o refreshToken
    // da conta admin, habilitando Directory e Google Chat automaticamente.
    // Gmail, Calendar e Drive precisam de Service Account configurada separadamente.
    @MainActor
    private func handleDeepLink(_ url: URL) {
        if let errorCode = AuthService.extractError(from: url) {
            if errorCode == "workspace_required" || errorCode == "workspace_admin_required" {
                authService.authError = "Esta aplicação exige uma conta administradora do Google Workspace. Faça login com o e-mail de administrador da sua organização."
            } else {
                authService.authError = "Erro na autenticação: \(errorCode)"
            }
            return
        }

        guard let token = AuthService.extractToken(from: url) else { return }
        authService.authError = nil

        Task {
            APIClient.shared.bearerToken = token

            do {
                // Selecionar organização ativa
                let orgs: [OrganizationDTO] = try await APIClient.shared.request("/api/organizations")
                if let activeOrg = orgs.first(where: { $0.isActive }),
                   let orgID = activeOrg.id?.uuidString {
                    APIClient.shared.organizationID = orgID
                }

                // Buscar person logada
                let people: [PersonDTO] = try await APIClient.shared.request("/api/people")
                let identity = AuthService.identity(from: token)
                let person = people.first(where: { $0.id == identity.personID })
                    ?? people.first(where: {
                        guard let profileEmail = identity.email,
                              let personEmail = $0.email else { return false }
                        return personEmail.caseInsensitiveCompare(profileEmail) == .orderedSame
                    })
                    ?? people.first ?? PersonDTO(
                    name: "Usuário",
                    jobTitle: "",
                    active: true,
                    joinedAt: Date()
                )

                await MainActor.run {
                    authService.handleCallback(token: token, person: person)
                    if let orgID = APIClient.shared.organizationID {
                        authService.setOrganization(id: orgID)
                    }
                }
            } catch {
                // Salva token mesmo sem org/person; LoadingView tentará novamente
                await MainActor.run {
                    authService.handleCallback(
                        token: token,
                        person: PersonDTO(name: "Usuário", jobTitle: "", active: true, joinedAt: Date())
                    )
                }
            }
        }
    }
}

// MARK: - AppFlowView

private struct AppFlowView: View {
    let authService: AuthService
    let onOpenURL: (URL) -> Void

    private enum Screen: Equatable {
        case onboarding   // Boas-vindas + botão "Iniciar com Google Workspace"
        case loading      // Syncs (directory + chat) após login OAuth
        case ready        // "Sua memória está pronta!"
        case dashboard    // App principal
    }

    @State private var screen: Screen
    @State private var syncWarning: String?
    @State private var isShowingDebugInspector: Bool = false

    init(authService: AuthService, onOpenURL: @escaping (URL) -> Void) {
        self.authService = authService
        self.onOpenURL = onOpenURL
        _screen = State(initialValue: authService.isAuthenticated ? .dashboard : .onboarding)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch screen {
                case .onboarding:
                    OnboardingView(onFinish: onOpenURL)
                        .environment(authService)

                case .loading:
                    LoadingView(syncWarning: $syncWarning) {
                        // Após concluir a preparação, entra diretamente na área
                        // principal com o perfil que acabou de autenticar.
                        screen = .dashboard
                    }
                    .environment(authService)

                case .ready:
                    ReadySuccessView(syncWarning: syncWarning) {
                        screen = .dashboard
                    }

                case .dashboard:
                    DashboardView()
                        .onAppear {
                            resizeWindow(to: CGSize(width: 1300, height: 800))
                        }
                }
            }

            // Botão flutuante discreto de diagnóstico/debug
//            Button {
//                isShowingDebugInspector = true
//            } label: {
//                HStack(spacing: 5) {
//                    Image(systemName: "ladybug.fill")
//                    Text("Debug")
//                        .font(.system(size: 11, weight: .bold))
//                }
//                .foregroundColor(.white)
//                .padding(.horizontal, 10)
//                .padding(.vertical, 5)
//                .background(Color.purple.opacity(0.85))
//                .cornerRadius(14)
//                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
//            }
//            .buttonStyle(.plain)
//            .padding(14)
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
//        .sheet(isPresented: $isShowingDebugInspector) {
//            DebugInspectorView()
//                .environment(authService)
//        }
        // Deep-link recebido → avança do onboarding para loading; logout/exclusão → volta para onboarding
        .onChange(of: authService.isAuthenticated) { _, isAuth in
            if isAuth && screen == .onboarding {
                screen = .loading
            } else if !isAuth {
                screen = .onboarding
            }
        }
        // 401 global → logout + volta para onboarding
        .onReceive(
            NotificationCenter.default.publisher(for: APIClient.unauthorizedNotification)
        ) { _ in
            authService.logout()
            screen = .onboarding
        }
    }

    private func resizeWindow(to size: CGSize) {
        guard let window = NSApplication.shared.windows.first else { return }
        var newFrame = window.frame
        let originX = newFrame.origin.x - (size.width - newFrame.width) / 2
        let originY = newFrame.origin.y - (size.height - newFrame.height) / 2
        newFrame.origin = CGPoint(x: originX, y: originY)
        newFrame.size = size
        window.setFrame(newFrame, display: true, animate: true)
    }
}
