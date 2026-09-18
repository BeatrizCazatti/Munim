import SwiftUI

struct SortPopover: View {

    @Binding var selection: SortOption

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            Text("Ordenar por")
//                .font(.subheadline.weight(.medium))
                .adaptiveTextStyle(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 12)

            VStack(spacing: 0) {

                ForEach(SortOption.allCases) { option in

                    SortOptionRow(
                        option: option,
                        isSelected: selection == option
                    ) {
                        selection = option
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 180)
        .padding(12)
        .modifier(GlassCardModifier(cornerRadius: 16))
    }
}

struct SortOptionRow: View {

    let option: SortOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {

        Button(action: action) {

            HStack(spacing: 8) {

                Image(systemName: isSelected ? "checkmark" : "circle")
//                .font(.subheadline.weight(.semibold))
                    .adaptiveTextStyle(.subheadline)
                    .fontWeight(.semibold)
                .frame(
                    width: 16,
                    alignment: .center
                )

                Text(option.title)
//                    .font(.subheadline)
                    .adaptiveTextStyle(.subheadline)

                Spacer()
            }
            .foregroundStyle(isSelected ? Color.Token.textOnAccent : .primary)
            .frame(
                maxWidth: .infinity,
                minHeight: 32
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .background(
            Capsule().fill(isSelected ? Color.Token.interactiveAccent : Color.Token.interactiveAccent.opacity(0.09))
        )
        .accessibilityValue(isSelected ? "Selecionado" : "Não selecionado")
    }
}
