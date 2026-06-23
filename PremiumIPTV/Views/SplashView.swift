import SwiftUI

struct SplashView: View {
    let onTimeout: () -> Void

    @State private var opacity: Double = 0
    @State private var scale: Double = 0.88

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [IptvColors.cyanSoft.opacity(0.4), IptvColors.background],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(IptvColors.cyanSoft)
                        .frame(width: 100, height: 100)
                        .overlay(Circle().stroke(IptvColors.cyan.opacity(0.3), lineWidth: 1.5))
                    Image(systemName: "tv.fill")
                        .font(.system(size: 48))
                        .foregroundColor(IptvColors.cyan)
                        .opacity(opacity)
                        .scaleEffect(scale)
                }
                Spacer().frame(height: 32)
                Text("PREMIUM IPTV")
                    .font(.system(size: 30, weight: .black))
                    .foregroundColor(IptvColors.textPrimary)
                    .opacity(opacity)
                Spacer().frame(height: 16)
                SignalBars(animated: true)
                    .opacity(opacity)
                Spacer().frame(height: 16)
                Text("By c0derz")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(IptvColors.cyan)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9)) {
                opacity = 1
                scale   = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                onTimeout()
            }
        }
    }
}
