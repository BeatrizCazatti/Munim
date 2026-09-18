import SwiftUI


struct ToolbarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.Token.interactiveAccent)

                Image(systemName: systemImage)
//                    .font(.title3.weight(.medium))
                    .adaptiveTextStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Token.textOnAccent)
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: Color.Token.interactiveAccent.opacity(0.22), radius: 10, y: 4)
        .accessibilityLabel(accessibilityLabel)
    }
}
