import SwiftUI

struct SourceChoiceView: View {
    let isArabic: Bool
    let onUseDefault: () -> Void
    let onUseCustom: () -> Void

    var body: some View {
        ZStack {
            IptvColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(IptvColors.cyanSoft)
                        .frame(width: 90, height: 90)
                        .overlay(Circle().stroke(IptvColors.cyan.opacity(0.25), lineWidth: 1))
                    Image(systemName: "tv.fill")
                        .font(.system(size: 44))
                        .foregroundColor(IptvColors.cyan)
                }
                Spacer().frame(height: Spacing.xl)
                Text(isArabic ? "اختر قائمة القنوات" : "Choose Your Playlist")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(IptvColors.textPrimary)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 8)
                Text(isArabic ? "استخدم القائمة الافتراضية أو حمّل قائمتك الخاصة." : "Use the built-in channel list or load your own.")
                    .font(.system(size: 15))
                    .foregroundColor(IptvColors.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: Spacing.xl3)
                SourceOptionRow(
                    title:    isArabic ? "استخدام القائمة الافتراضية" : "Use Default Playlist",
                    subtitle: isArabic ? "قنوات مختارة، تتحدث تلقائياً من السيرفر" : "Curated channels, auto-updated from the server",
                    icon:     "checkmark.icloud.fill",
                    accent:   IptvColors.cyan,
                    action:   onUseDefault
                )
                Spacer().frame(height: Spacing.lg)
                SourceOptionRow(
                    title:    isArabic ? "تحميل قائمتي الخاصة" : "Load My Own Playlist",
                    subtitle: isArabic ? "أدخل رابطاً أو اختر ملفاً من جهازك" : "Enter a URL or pick a file from your device",
                    icon:     "folder.fill",
                    accent:   IptvColors.orange,
                    action:   onUseCustom
                )
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
        }
    }
}

private struct SourceOptionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: IptvRadius.medium)
                    .fill(accent.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(IptvColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(IptvColors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 16))
                .foregroundColor(IptvColors.textMuted)
        }
        .padding(Spacing.lg)
        .background(IptvColors.surfaceElevated)
        .cornerRadius(IptvRadius.large)
        .overlay(RoundedRectangle(cornerRadius: IptvRadius.large).stroke(accent.opacity(0.25), lineWidth: 1))
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onTapGesture { action() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}
