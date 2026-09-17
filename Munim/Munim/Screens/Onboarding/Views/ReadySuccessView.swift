import SwiftUI

struct ReadySuccessView: View {
    var syncWarning: String?
    var onStartMunim: () -> Void = {}
    
    @State private var animateBubbles = false
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 16
    
    // MARK: - Cores
    private enum Theme {
        static let titleColor = Color(red: 0.15, green: 0.35, blue: 0.82)
        static let textColor = Color(red: 0.35, green: 0.55, blue: 0.90)
        static let buttonBackground = Color(red: 0.25, green: 0.45, blue: 0.88)
        static let bubble = Color(red: 0.68, green: 0.88, blue: 0.30)
        static let warningBackground = Color.orange.opacity(0.12)
        static let warningText = Color(red: 0.7, green: 0.4, blue: 0.0)
    }
    
    // MARK: - Configuração das Bolhas
    private struct BubbleItem: Identifiable {
        let id = UUID()
        let size: CGFloat
        let opacity: Double
        let x: CGFloat
        let y: CGFloat
    }
    
    private let bubbles: [BubbleItem] = [
        BubbleItem(size: 32, opacity: 0.35, x: -180, y: -160),
        BubbleItem(size: 48, opacity: 0.85, x: -260, y: -60),
        BubbleItem(size: 16, opacity: 0.75, x: -100, y: -75),
        BubbleItem(size: 28, opacity: 0.80, x: -30, y: -90),
        BubbleItem(size: 36, opacity: 0.85, x: -8,  y: -7),
        BubbleItem(size: 14, opacity: 0.85, x: -300, y: 70),
        BubbleItem(size: 34, opacity: 0.50, x: -390, y: 110),
        BubbleItem(size: 32, opacity: 0.80, x: -250, y: 150),
        BubbleItem(size: 38, opacity: 0.55, x: -70,  y: 190)
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                // Conteúdo textual e ação
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    descriptionSection
                    
                    // Banner de aviso (se houver integrações não configuradas)
                    if let warning = syncWarning {
                        warningBanner(message: warning)
                            .padding(.top, 20)
                    }

                    Spacer()
                    actionButton
                }
                .padding(.top, 110)
                .padding(.bottom, 80)
                .padding(.leading, 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                
                // Ilustração e partículas decorativas
                characterIllustration(geometry: geometry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingTheme.background)
        .ignoresSafeArea()
        .onAppear {
            animateBubbles = true
        }
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        Text("Sua memória organizacional\nestá pronta!")
            .font(.system(size: titleSize, weight: .bold))
            .foregroundColor(Theme.titleColor)
            .lineSpacing(6)
            .padding(.bottom, 36)
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Identificamos sua equipe e seus times, você\npode conferir ou alterar as informações da\nequipe na tela inicial.")
                .lineSpacing(4)
            
            Text("Você está pronto para começar!")
        }
        .font(.system(size: bodySize, weight: .regular))
        .foregroundColor(Theme.textColor)
    }

    private func warningBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.warningText)
                .font(.system(size: 14))
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Theme.warningText)
                .lineSpacing(3)
                .frame(maxWidth: 400, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.warningBackground)
        .cornerRadius(8)
        .frame(maxWidth: 430, alignment: .leading)
    }
    
    private var actionButton: some View {
        Button(action: onStartMunim) {
            Text("Iniciar Munim")
                .font(.system(size: buttonSize, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 14)
                .background(Theme.buttonBackground)
                .cornerRadius(24)
        }
        .buttonStyle(.plain)
    }
    
    private func characterIllustration(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(bubbles) { bubble in
                Circle()
                    .fill(Theme.bubble.opacity(bubble.opacity))
                    .frame(width: bubble.size, height: bubble.size)
                    .offset(x: bubble.x, y: bubble.y)
            }
            
            Image("MunimIdle")
                .resizable()
                .scaledToFit()
                .frame(
                    width: geometry.size.width * 0.55,
                    height: geometry.size.height * 0.75
                )
                .offset(x: 40, y: 40)
        }
        .scaleEffect(animateBubbles ? 1.02 : 0.98)
        .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: animateBubbles)
    }
}

#Preview {
    ReadySuccessView(syncWarning: "Directory não configurado • Gmail não configurado")
        .frame(width: 960, height: 600)
}
