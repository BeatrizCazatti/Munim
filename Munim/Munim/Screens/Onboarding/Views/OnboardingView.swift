import SwiftUI
import AuthenticationServices

enum OnboardingStep {
    case welcome
    case explanation
    case permissions
}

struct OnboardingView: View {
    /// Entrega o callback capturado por `ASWebAuthenticationSession` ao fluxo
    /// principal do app. Em macOS, esse callback não passa necessariamente por
    /// `onOpenURL`, pois a sessão de autenticação pode consumi-lo primeiro.
    let onFinish: (URL) -> Void

    @Environment(AuthService.self) private var authService

    @State private var currentStep: OnboardingStep = .welcome
    @State private var isLoadingAuthURL: Bool = false
    @State private var authError: String?
    @State private var authenticationSession: ASWebAuthenticationSession?

    @ScaledMetric(relativeTo: .title) private var welcomeTitleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .largeTitle) private var brandTitleSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title3) private var bodyTitleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title2) private var explanationTitleSize: CGFloat = 30
    @ScaledMetric(relativeTo: .title2) private var permissionsTitleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var supportingTextSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var buttonTextSize: CGFloat = 16

    init(onFinish: @escaping (URL) -> Void = { _ in }) {
        self.onFinish = onFinish
    }
    
    private let primaryBlue = Color(red: 0.25, green: 0.45, blue: 0.88)
    private let lightBlue = Color(red: 0.35, green: 0.55, blue: 0.90)
    
    var body: some View {
        HStack(spacing: 0) {
            // Lado Esquerdo: Conteúdo dinâmico com base na etapa atual
            VStack(alignment: .leading, spacing: 0) {
                
                // Indicador de Progresso (apenas nos passos 2 e 3)
                if currentStep != .welcome {
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(currentStep == .explanation ? primaryBlue : Color.gray.opacity(0.35))
                            .frame(width: 24, height: 6)
                        
                        Capsule()
                            .fill(currentStep == .permissions ? primaryBlue : Color.gray.opacity(0.35))
                            .frame(width: 24, height: 6)
                    }
                    .padding(.bottom, 48)
                }
                
                // Conteúdo de texto e botão
                switch currentStep {
                case .welcome:
                    welcomeView
                case .explanation:
                    explanationView
                case .permissions:
                    permissionsView
                }
                
                Spacer()

                // Mensagem de erro (local ou vinda do callback deep-link)
                if let error = displayedError {
                    Text(error)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.red)
                        .frame(maxWidth: 400, alignment: .leading)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                
                // Botão de Ação
                actionButton
            }
            .padding(.top, currentStep == .welcome ? 120 : 72)
            .padding(.leading, 80)
            .padding(.trailing, 40)
            .padding(.bottom, 60) // Adicionado espaçamento interno inferior para afastar o botão da borda
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.white) // Garante fundo branco específico no lado esquerdo
            
            // Lado Direito: Imagem estática de fundo/prévia
            GeometryReader { geometry in
                Image("OnboardingTest")
                    .resizable()
                    .scaledToFill()
                    .frame(height: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 960, height: 600)
        .background(Color.white) // Fundo branco global da janela
        .animation(.easeInOut(duration: 0.25), value: currentStep)
        .animation(.easeInOut(duration: 0.2), value: authError)
    }

    
    // MARK: - Passos de Texto
    
    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bem-vindo ao")
                .font(.system(size: welcomeTitleSize, weight: .regular))
                .foregroundColor(primaryBlue)
            
            Text("munim")
                .font(.system(size: brandTitleSize, weight: .bold, design: .rounded))
                .foregroundColor(primaryBlue)
                .padding(.bottom, 24)
            
            Text("A memória organizacional que reúne o conhecimento que sua equipe já compartilha todo dia em um só lugar.")
                .font(.system(size: bodyTitleSize, weight: .regular))
                .foregroundColor(primaryBlue)
                .lineSpacing(4)
                .frame(maxWidth: 380, alignment: .leading)
        }
    }
    
    private var explanationView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Munim funciona recebendo o que sua empresa já compartilha")
                .font(.system(size: explanationTitleSize, weight: .bold))
                .foregroundColor(primaryBlue)
                .lineSpacing(4)
                .frame(maxWidth: 420, alignment: .leading)
            
            Text("Traduzimos conversas e dados brutos em um repositório organizacional, integrando o Google Workspace ao Munim.")
                .font(.system(size: bodyTitleSize, weight: .regular))
                .foregroundColor(lightBlue)
                .lineSpacing(4)
                .frame(maxWidth: 400, alignment: .leading)
        }
    }
    
    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Para começar, forneça as permissões com a conta de **Administrador** do seu **Google Workspace**")
                .font(.system(size: permissionsTitleSize, weight: .regular))
                .foregroundColor(primaryBlue)
                .lineSpacing(4)
                .frame(maxWidth: 440, alignment: .leading)
            
            Text("É assim que conseguimos montar o mapa da equipe sem que ninguém precise digitar nada.")
                .font(.system(size: supportingTextSize, weight: .regular))
                .foregroundColor(lightBlue)
                .lineSpacing(3)
                .frame(maxWidth: 380, alignment: .leading)
        }
    }
    
    // MARK: - Botão de Ação
    
    private var actionButton: some View {
        Button(action: handleAction) {
            HStack(spacing: 8) {
                if isLoadingAuthURL {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(buttonTitle)
                    .font(.system(size: buttonTextSize, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, currentStep == .permissions ? 28 : 36)
            .padding(.vertical, 14)
            .background(primaryBlue.opacity(isLoadingAuthURL ? 0.7 : 1.0))
            .cornerRadius(24)
        }
        .buttonStyle(.plain)
        .disabled(isLoadingAuthURL)
    }
    
    private var buttonTitle: String {
        switch currentStep {
        case .welcome:
            return "Começar"
        case .explanation:
            return "Avançar"
        case .permissions:
            return isLoadingAuthURL ? "Abrindo Google…" : "Iniciar com Google Workspace"
        }
    }

    private var displayedError: String? {
        authError ?? authService.authError
    }

    // MARK: - Lógica do botão

    private func handleAction() {
        authError = nil
        authService.authError = nil
        switch currentStep {
        case .welcome:
            currentStep = .explanation
        case .explanation:
            currentStep = .permissions
        case .permissions:
            startGoogleOAuth()
        }
    }
    
    // Cria uma classe auxiliar para fornecer o contexto da janela no macOS
    private class WebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            // Retorna a janela principal ativa do aplicativo no macOS
            return NSApplication.shared.windows.first ?? NSWindow()
        }
    }

    // Mantem a instância guardada para evitar que seja desalocada antes do término
    private let presentationProvider = WebAuthPresentationProvider()

    private func startGoogleOAuth() {
        isLoadingAuthURL = true
        Task {
            defer { isLoadingAuthURL = false }
            do {
                let authURL = try await authService.fetchGoogleAuthURL()
                let callbackURLScheme = "munim"
                
                let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackURLScheme) { callbackURL, error in
                    if let error = error {
                        Task { @MainActor in
                            authenticationSession = nil
                            authError = "Não foi possível conectar ao servidor: \(error.localizedDescription)"
                        }
                        return
                    }
                    
                    guard let callbackURL = callbackURL else { return }
                    Task { @MainActor in
                        authenticationSession = nil
                        onFinish(callbackURL)
                    }
                }
                
                // Atribui a classe compatível com NSObject
                session.presentationContextProvider = presentationProvider
                // A sessão precisa permanecer viva até o Google redirecionar ao app.
                // Sem essa referência, ela é desalocada ao fim desta função e o
                // callback nunca atualiza `AuthService.isAuthenticated`.
                authenticationSession = session
                session.start()
                
            } catch {
                authError = "Não foi possível conectar ao servidor: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    OnboardingView()
        .frame(width: 960, height: 600)
        .environment(AuthService())
}
