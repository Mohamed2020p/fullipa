import SwiftUI

// MARK: - Colors
enum IptvColors {
    static let background      = Color(hex: "000000")
    static let surface         = Color(hex: "0A0A0A")
    static let surfaceElevated = Color(hex: "141414")
    static let surfaceGlass    = Color(hex: "1A1A1A").opacity(0.85)

    static let cyan            = Color(hex: "00D4FF")
    static let cyanSoft        = Color(hex: "00D4FF").opacity(0.12)
    static let cyanGlow        = Color(hex: "00D4FF").opacity(0.45)

    static let orange          = Color(hex: "FF6B00")

    static let textPrimary     = Color.white
    static let textSecondary   = Color(hex: "B0B0B0")
    static let textMuted       = Color(hex: "707070")

    static let error           = Color(hex: "FF4444")
    static let errorSoft       = Color(hex: "FF4444").opacity(0.12)

    static let live            = Color(hex: "00E676")
    static let border          = Color(hex: "222222")
    static let borderLight     = Color(hex: "333333")

    static let scrim           = Color.black.opacity(0.75)
    static let scrimLight      = Color.black.opacity(0.35)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF)         / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Corner Radii
enum IptvRadius {
    static let small:  CGFloat = 8
    static let medium: CGFloat = 12
    static let large:  CGFloat = 16
    static let pill:   CGFloat = 50
}

// MARK: - Spacing
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xl3: CGFloat = 48
}

// MARK: - Animated Signal Bars
struct SignalBars: View {
    var color: Color = IptvColors.cyan
    var animated: Bool = true
    var barCount: Int = 4

    @State private var phases: [Double] = [0.3, 0.5, 0.7, 1.0]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: 16 * phases[i])
                    .animation(
                        animated
                        ? Animation.easeInOut(duration: 0.48 + Double(i) * 0.09)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12)
                        : .none,
                        value: phases[i]
                    )
            }
        }
        .onAppear {
            if animated {
                for i in 0..<barCount {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                        withAnimation { phases[i] = (i % 2 == 0) ? 1.0 : 0.3 }
                    }
                }
            }
        }
    }
}

// MARK: - Primary Button
struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(IptvColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(enabled ? IptvColors.cyan : IptvColors.border)
                .cornerRadius(IptvRadius.medium)
        }
        .disabled(!enabled)
    }
}

// MARK: - Iptv Text Field
struct IptvTextField: View {
    @Binding var text: String
    let label: String
    var isError: Bool = false
    var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: IptvRadius.medium)
                    .fill(IptvColors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: IptvRadius.medium)
                            .stroke(isError ? IptvColors.error : (text.isEmpty ? IptvColors.border : IptvColors.cyan), lineWidth: 1)
                    )
                    .frame(height: 56)
                VStack(alignment: .leading, spacing: 0) {
                    if !text.isEmpty {
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundColor(IptvColors.textMuted)
                            .padding(.top, 8)
                            .padding(.horizontal, 12)
                    }
                    TextField(text.isEmpty ? label : "", text: $text)
                        .foregroundColor(IptvColors.textPrimary)
                        .font(.system(size: 15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, text.isEmpty ? 17 : 6)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            if isError, let msg = errorText {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(IptvColors.error)
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundColor(IptvColors.error)
                }
            }
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    let text: String
    var subText: String = ""

    var body: some View {
        ZStack {
            IptvColors.background.ignoresSafeArea()
            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: IptvColors.cyan))
                    .scaleEffect(1.4)
                Text(text)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(IptvColors.textPrimary)
                if !subText.isEmpty {
                    Text(subText)
                        .font(.system(size: 15))
                        .foregroundColor(IptvColors.cyan)
                }
            }
        }
    }
}
