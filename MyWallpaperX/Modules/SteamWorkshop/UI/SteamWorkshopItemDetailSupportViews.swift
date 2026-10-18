import SwiftUI
import AppKit

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct SteamWorkshopScrollFadeMask: View {
    let topFadeHeight: CGFloat
    let bottomFadeHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, topFadeHeight + bottomFadeHeight + 1)
            let topFadeRatio = min(max(topFadeHeight / height, 0.01), 0.18)
            let bottomFadeRatio = min(max(bottomFadeHeight / height, 0.01), 0.24)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: topFadeRatio),
                    .init(color: .black, location: 1 - bottomFadeRatio),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

struct SteamWorkshopSingleFactCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SteamWorkshopInlineNotice: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct SteamWorkshopInlineErrorNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("详情补全失败")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
struct SteamWorkshopValidationPill: View {
    let severity: SteamWorkshopWebValidationSeverity
    let levelTitle: String?
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                if let levelTitle, levelTitle.isEmpty == false {
                    Text(levelTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 0.7)
        }
    }

    private var iconName: String {
        switch severity {
        case .error:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .secondary
        }
    }
}
#endif

enum SteamWorkshopFooterButtonKind {
    case primary
    case secondary
    case danger
}

struct SteamWorkshopFooterButtonStyle: ButtonStyle {
    var kind: SteamWorkshopFooterButtonKind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .background(backgroundFill(isPressed: configuration.isPressed))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor.opacity(isEnabled ? 1 : 0.55), lineWidth: 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return Color(nsColor: .labelColor)
        case .danger:
            return .white
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return Color(nsColor: .systemBlue).opacity(0.42)
        case .secondary:
            return Color.white.opacity(0.16)
        case .danger:
            return Color.red.opacity(0.24)
        }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool) -> some View {
        let opacity = isPressed ? 0.9 : 1.0
        let pressed = isPressed ? 1.0 : 0.0

        switch kind {
        case .primary:
            Color(nsColor: isPressed ? .systemBlue.withSystemEffect(.pressed) : .systemBlue)
        case .secondary:
            Color.black.opacity(0.14 * opacity)
        case .danger:
            Color.red.opacity(0.68 - (0.12 * pressed))
        }
    }
}
