import SwiftUI

/// Apple 风格的视觉系统：单一强调色、大量留白、hairline 分隔
enum Theme {
    static let bg      = Color(red: 0.961, green: 0.961, blue: 0.969)   // #F5F5F7
    static let ink     = Color(red: 0.114, green: 0.114, blue: 0.122)   // #1D1D1F
    static let sub     = Color(red: 0.353, green: 0.365, blue: 0.412)   // 更深的次级文字
    static let faint   = Color(red: 0.447, green: 0.459, blue: 0.510)
    static let line    = Color(red: 0.824, green: 0.824, blue: 0.843)   // #D2D2D7

    static let accent  = Color(red: 0.000, green: 0.443, blue: 0.890)   // #0071E3
    static let accent2 = Color(red: 0.000, green: 0.478, blue: 1.000)   // #007AFF

    static let ok      = Color(red: 0.204, green: 0.780, blue: 0.349)   // #34C759
    static let warn    = Color(red: 1.000, green: 0.624, blue: 0.039)   // #FF9F0A
    static let danger  = Color(red: 1.000, green: 0.231, blue: 0.188)   // #FF3B30

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - 卡片

struct CardBackground: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            // macOS 26 起系统自带 Liquid Glass，直接用，别手搓
            return AnyView(
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: radius))
            )
        }
        return AnyView(
            content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.white.opacity(0.06)))
            }
            .clipShape(shape)
            // 斜切高光：模拟玻璃表面的反光
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
            }
            // 顶边高光：玻璃受光的边缘
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), Color.white.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
            )
            .shadow(color: .black.opacity(0.22), radius: 34, y: 16)
        )
    }
}

// MARK: - 真实毛玻璃（透到桌面）

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// 把窗口变成非不透明，否则材质只能采样窗口自身，看不到桌面
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.hasShadow = true
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { }
}

/// Liquid Glass 的背景：柔和的多色光斑，让玻璃材质有东西可以透
struct AppBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.42, green: 0.48, blue: 0.98),
                        Color(red: 0.36, green: 0.72, blue: 0.98),
                        Color(red: 0.80, green: 0.56, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // 有明确边界的色块，模糊后仍保留结构，玻璃才能"折射"出层次
                Circle()
                    .fill(Color(red: 0.30, green: 0.36, blue: 1.00).opacity(0.85))
                    .frame(width: w * 0.55)
                    .blur(radius: 90)
                    .offset(x: -w * 0.28, y: -h * 0.30)

                Circle()
                    .fill(Color(red: 0.20, green: 0.86, blue: 1.00).opacity(0.75))
                    .frame(width: w * 0.45)
                    .blur(radius: 80)
                    .offset(x: w * 0.32, y: -h * 0.22)

                Circle()
                    .fill(Color(red: 0.95, green: 0.45, blue: 0.78).opacity(0.65))
                    .frame(width: w * 0.50)
                    .blur(radius: 100)
                    .offset(x: w * 0.10, y: h * 0.38)

                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: w * 0.30)
                    .blur(radius: 70)
                    .offset(x: -w * 0.05, y: h * 0.05)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func card(radius: CGFloat = 18) -> some View { modifier(CardBackground(radius: radius)) }
}

// MARK: - 小组件

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

func riskColor(_ risk: Risk) -> Color {
    switch risk {
    case .safe:    return Theme.ok
    case .careful: return Theme.warn
    case .risky:   return Theme.danger
    }
}

// MARK: - 按钮

/// 主操作：实心蓝，用于"清理"这类一步到位的动作
struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 14 : 22)
            .padding(.vertical, compact ? 7 : 11)
            .background(
                Capsule().fill(Theme.accent)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 次要操作：浅灰胶囊
struct GhostButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(Theme.ink.opacity(0.85))
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6 : 8)
            .background(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.08 : 0.05)))
    }
}
