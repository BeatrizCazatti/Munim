import SwiftUI

// Estrutura de dados para definir cada partícula de bolha verde
struct BubbleParticle: Identifiable {
    let id = UUID()
    let size: CGFloat
    let finalX: CGFloat
    let finalY: CGFloat
    let duration: Double
    let delay: Double
}

struct LoadingView: View {
    @Binding var syncWarning: String?
    let onComplete: () -> Void

    @Environment(AuthService.self) private var authService

    @State private var isAnimating: Bool = false
    @State private var progress: CGFloat = 0.0
    @State private var statusText: String = "Conectando ao servidor…"

    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 16

    init(syncWarning: Binding<String?>, onComplete: @escaping () -> Void = {}) {
        self._syncWarning = syncWarning
        self.onComplete = onComplete
    }
    
    private let primaryBlue = Color(red: 0.25, green: 0.45, blue: 0.88)
    private let lightBlue   = Color(red: 0.35, green: 0.55, blue: 0.90)
    private let bubbleColor = Color(red: 0.65, green: 0.85, blue: 0.30)
    
    private let particles: [BubbleParticle] = [
        BubbleParticle(size: 26, finalX: -160, finalY: -110, duration: 2.6, delay: 0.0),
        BubbleParticle(size: 16, finalX: -200, finalY: -160, duration: 3.1, delay: 0.4),
        BubbleParticle(size: 32, finalX: 180,  finalY: -150, duration: 2.8, delay: 0.2),
        BubbleParticle(size: 22, finalX: 200,  finalY: -80,  duration: 3.4, delay: 0.6),
        BubbleParticle(size: 28, finalX: 190,  finalY: 10,   duration: 2.9, delay: 0.3),
        BubbleParticle(size: 14, finalX: 230,  finalY: 20,   duration: 3.2, delay: 0.8),
        BubbleParticle(size: 34, finalX: -70,  finalY: -125, duration: 2.7, delay: 0.1),
        BubbleParticle(size: 12, finalX: -30,  finalY: -110, duration: 2.4, delay: 0.5),
        BubbleParticle(size: 18, finalX: 20,   finalY: -170, duration: 3.3, delay: 0.7),
        BubbleParticle(size: 10, finalX: 90,   finalY: -160, duration: 2.5, delay: 0.2),
        BubbleParticle(size: 24, finalX: 165,  finalY: -60,  duration: 3.0, delay: 0.9),
        BubbleParticle(size: 16, finalX: -170, finalY: -45,  duration: 2.6, delay: 0.4),
        BubbleParticle(size: 12, finalX: -100, finalY: -70,  duration: 3.2, delay: 0.3),
        BubbleParticle(size: 18, finalX: -60,  finalY: -60,  duration: 2.8, delay: 0.7),
        BubbleParticle(size: 22, finalX: -150, finalY: 30,   duration: 3.1, delay: 0.5),
        BubbleParticle(size: 14, finalX: -80,  finalY: 20,   duration: 2.7, delay: 0.2),
        BubbleParticle(size: 10, finalX: -60,  finalY: 55,   duration: 3.5, delay: 0.6),
        BubbleParticle(size: 10, finalX: 220,  finalY: -40,  duration: 2.9, delay: 0.8),
        BubbleParticle(size: 12, finalX: 215,  finalY: 70,   duration: 3.3, delay: 0.4)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            ZStack {
                ForEach(particles) { p in
                    Circle()
                        .fill(bubbleColor.opacity(isAnimating ? 0.75 : 0.0))
                        .frame(width: p.size, height: p.size)
                        .scaleEffect(isAnimating ? 1.0 : 0.1)
                        .offset(x: isAnimating ? p.finalX : 0, y: isAnimating ? p.finalY : 0)
                        .animation(
                            .easeInOut(duration: p.duration)
                            .repeatForever(autoreverses: true)
                            .delay(p.delay),
                            value: isAnimating
                        )
                }
                
                Image("MunimCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 170, height: 170)
            }
            .frame(height: 280)
            
            VStack(spacing: 8) {
                Text("Iniciando sincronização dos dados do Workspace")
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundColor(primaryBlue)
                    .multilineTextAlignment(.center)

                Text(statusText)
                    .font(.system(size: bodySize, weight: .regular))
                    .foregroundColor(lightBlue)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .animation(.easeInOut(duration: 0.3), value: statusText)
            }
            .padding(.top, 24)
            .padding(.bottom, 36)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.18))
                        .frame(height: 7)
                    Capsule()
                        .fill(primaryBlue)
                        .frame(width: geometry.size.width * progress, height: 7)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(width: 440, height: 7)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingTheme.background)
        .ignoresSafeArea()
        .onAppear { isAnimating = true }
        .task { await performSyncs() }
    }

    // MARK: - Syncs pós-login
    //
    // Apenas Directory e Google Chat são sincronizados aqui:
    //   • Ambos requerem OAuth admin, obtido no primeiro login via loginPlusAdmin().
    //   • Se a conta Google usada NÃO for admin de Workspace, o Google não concede
    //     esses escopos — os syncs retornam 404 e o app continua normalmente.
    //
    // Gmail, Calendar e Drive requerem Service Account configurada separadamente
    // em Configurações → Integração (não são ativados via OAuth do usuário).
    private func performSyncs() async {
        var warnings: [String] = []

        // ── Passo 1: Selecionar organização (0 → 20%) ──────────────────────
        setStatus("Selecionando organização…", progress: 0.10)
        do {
            _ = try await OrganizationService.shared.selectDefaultOrganization(
                authService: authService
            )
            setStatus("Organização selecionada", progress: 0.20)
        } catch {
            warnings.append("Organização: \(error.localizedDescription)")
            setStatus("Organização com erro — continuando…", progress: 0.20)
        }

        // ── Passo 2: Directory (20 → 60%) ──────────────────────────────────
        setStatus("Sincronizando diretório de usuários e times…", progress: 0.25)
        do {
            let result: DirectorySyncResultDTO = try await APIClient.shared.request(
                "/api/integrations/directory/sync", method: "POST"
            )
            setStatus(
                "\(result.usersSynced) usuários e \(result.groupsSynced) grupos importados",
                progress: 0.60
            )
        } catch APIError.notFound {
            // Ocorre quando: (a) conta não é admin Workspace, ou (b) integração não conectada
            warnings.append("Directory não configurado — a conta usada pode não ser administradora de um Google Workspace.")
            setStatus("Diretório não configurado — continuando…", progress: 0.60)
        } catch {
            warnings.append("Directory: \(error.localizedDescription)")
            setStatus("Diretório com erro — continuando…", progress: 0.60)
        }

        // ── Passo 3: Google Chat (60 → 100%) ───────────────────────────────
        setStatus("Sincronizando espaços do Google Chat…", progress: 0.65)
        do {
            let result: GoogleChatSyncResultDTO = try await APIClient.shared.request(
                "/api/integrations/google-chat/sync", method: "POST"
            )
            setStatus(
                "\(result.spacesSynced) espaços e \(result.messagesSynced) mensagens sincronizados",
                progress: 1.0
            )
        } catch APIError.notFound {
            warnings.append("Google Chat não configurado — verifique se a conta é administradora do Workspace.")
            setStatus("Google Chat não configurado — continuando…", progress: 1.0)
        } catch {
            warnings.append("Google Chat: \(error.localizedDescription)")
            setStatus("Google Chat com erro — continuando…", progress: 1.0)
        }

        // Aviso fixo: Gmail/Calendar/Drive precisam de Service Account
        warnings.append("Para sincronizar Gmail, Calendário e Drive, configure a Service Account em Ajustes → Integração.")

        // Só exibir warning se houver mais do que o aviso padrão da SA
        syncWarning = warnings.joined(separator: "\n• ")

        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled else { return }
        onComplete()
    }


    @MainActor
    private func setStatus(_ text: String, progress newProgress: CGFloat) {
        statusText = text
        progress = newProgress
    }
}

#Preview {
    LoadingView(syncWarning: .constant(nil))
        .frame(width: 960, height: 600)
        .environment(AuthService())
}
