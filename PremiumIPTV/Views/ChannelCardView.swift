import SwiftUI

struct ChannelCardView: View {
    let channel: Channel
    let channelNumber: Int
    let isSelected: Bool
    let isArabic: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background / logo
            if !channel.logo.isEmpty, let url = URL(string: channel.logo) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }

            // Gradient overlay
            LinearGradient(
                colors: [.clear, IptvColors.scrim.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Bottom labels
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(IptvColors.textPrimary)
                    .lineLimit(1)
                Text(channel.category)
                    .font(.system(size: 12))
                    .foregroundColor(IptvColors.cyan)
                    .lineLimit(1)
            }
            .padding(12)

            // Channel number badge
            VStack {
                HStack {
                    Text(String(format: "%03d", channelNumber))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(IptvColors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(IptvColors.scrimLight)
                        .clipShape(Capsule())
                    Spacer()
                    // LIVE badge
                    if isSelected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(IptvColors.live.opacity(pulse ? 1 : 0.4))
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                                .onAppear { pulse = true }
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(IptvColors.live)
                                .kerning(0.6)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(IptvColors.surfaceGlass)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(IptvColors.cyan.opacity(0.3), lineWidth: 0.5))
                    }
                }
                .padding(10)
                Spacer()
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(IptvColors.surfaceElevated)
        .cornerRadius(IptvRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: IptvRadius.large)
                .stroke(isSelected ? IptvColors.cyan : IptvColors.border, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? IptvColors.cyanGlow : .black.opacity(0.3), radius: isSelected ? 12 : 4)
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onTapGesture { onTap() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }

    private var fallbackIcon: some View {
        ZStack {
            IptvColors.surfaceElevated
            Image(systemName: "tv.fill")
                .font(.system(size: 36))
                .foregroundColor(isSelected ? IptvColors.cyan : IptvColors.textMuted)
        }
    }
}
