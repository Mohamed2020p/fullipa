import SwiftUI

struct LanguageSelectionView: View {
    let onLanguageSelected: (String) -> Void

    var body: some View {
        ZStack {
            IptvColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(IptvColors.cyanSoft)
                        .frame(width: 84, height: 84)
                        .overlay(Circle().stroke(IptvColors.cyan.opacity(0.25), lineWidth: 1))
                    Image(systemName: "globe")
                        .font(.system(size: 40))
                        .foregroundColor(IptvColors.cyan)
                }
                Spacer().frame(height: Spacing.xl)
                Text("Select Language / اختر اللغة")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(IptvColors.textPrimary)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: Spacing.xl3)
                LanguageOptionCard(
                    label: "English",
                    accent: IptvColors.cyan
                ) { onLanguageSelected("en") }
                Spacer().frame(height: Spacing.lg)
                LanguageOptionCard(
                    label: "العربية",
                    accent: IptvColors.orange
                ) { onLanguageSelected("ar") }
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
        }
    }
}

private struct LanguageOptionCard: View {
    let label: String
    let accent: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(IptvColors.textPrimary)
            Spacer()
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(IptvColors.surfaceElevated)
        .cornerRadius(IptvRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: IptvRadius.medium)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onTapGesture { action() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}
