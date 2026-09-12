import SwiftUI

enum AppTextStyle {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case subheadline
    case body
    case callout
    case caption
    case caption2

    var macOSBaseSize: CGFloat {
        switch self {
        case .largeTitle: 28
        case .title: 22
        case .title2: 18
        case .title3: 17
        case .headline: 14
        case .subheadline: 12
        case .body: 13
        case .callout: 12
        case .caption: 11
        case .caption2: 10
        }
    }
}

struct AdaptiveTextStyle: ViewModifier {
    let style: AppTextStyle

    @AppStorage("macOSTextScale")
    private var macOSTextScale = 1.5

    func body(content: Content) -> some View {
        #if os(macOS)
        content.font(.system(size: style.macOSBaseSize * macOSTextScale))
        #else
        content.font(style.iOS)
        #endif
    }
}

extension View {
    func adaptiveTextStyle(_ style: AppTextStyle = .body) -> some View {
        modifier(AdaptiveTextStyle(style: style))
    }
}
