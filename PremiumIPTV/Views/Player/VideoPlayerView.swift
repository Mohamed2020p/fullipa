import SwiftUI
import AVKit
import AVFoundation

// MARK: - Player State
enum PlayerUIState: Equatable {
    case buffering
    case ready
    case reconnecting(attempt: Int)
    case error(String)
}

// MARK: - AVPlayer SwiftUI wrapper
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

// MARK: - Main Player Widget
final class ChannelPlayerViewModel: ObservableObject {
    @Published var uiState: PlayerUIState = .buffering
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var stalledObserver: NSObjectProtocol?

    let player: AVPlayer = {
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        return p
    }()

    func load(channel: Channel) {
        reconnectTask?.cancel()
        reconnectAttempt = 0
        uiState = .buffering
        internalLoad(urlString: channel.url)
    }

    private func internalLoad(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed) else {
            uiState = .error("INVALID_URL")
            return
        }
        let item = AVPlayerItem(url: url)
        NotificationCenter.default.removeObserver(self)
        player.replaceCurrentItem(with: item)

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.reconnectAttempt = 0
                    self?.uiState = .ready
                    self?.player.play()
                case .failed:
                    self?.handleError(urlString: urlString)
                default: break
                }
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handleError(urlString: urlString)
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }

        player.play()
    }

    private func handleError(urlString: String) {
        reconnectTask?.cancel()
        reconnectAttempt += 1
        uiState = .reconnecting(attempt: reconnectAttempt)
        let delay: UInt64
        switch reconnectAttempt {
        case 1, 2: delay = 1_000_000_000
        case 3, 4, 5: delay = 2_000_000_000
        default: delay = 3_000_000_000
        }
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.internalLoad(urlString: urlString)
            }
        }
    }

    func retry(urlString: String) {
        reconnectAttempt = 0
        reconnectTask?.cancel()
        uiState = .buffering
        internalLoad(urlString: urlString)
    }

    deinit {
        reconnectTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

struct ChannelPlayerWidget: View {
    let channel: Channel
    let isArabic: Bool
    @Binding var isFullScreen: Bool

    @StateObject private var vm = ChannelPlayerViewModel()
    @State private var livePulse = false

    var body: some View {
        ZStack {
            Color.black
            VideoPlayerView(player: vm.player)

            // Top bar
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        if case .ready = vm.uiState {
                            Circle()
                                .fill(IptvColors.live.opacity(livePulse ? 1 : 0.4))
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: livePulse)
                                .onAppear { livePulse = true }
                        }
                        Text(channel.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: { isFullScreen.toggle() }) {
                        Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 18))
                            .foregroundColor(IptvColors.cyan)
                    }
                    .frame(width: 32, height: 32)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(IptvColors.scrimLight)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(IptvColors.borderLight, lineWidth: 0.5))
                .padding(12)
                Spacer()
            }

            // State overlays
            switch vm.uiState {
            case .buffering:
                Color.black.opacity(0.35)
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: IptvColors.cyan))
                        .scaleEffect(1.3)
                    Text(isArabic ? "جاري التحميل…" : "Buffering…")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }

            case .reconnecting(let attempt):
                Color.black.opacity(0.35)
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: IptvColors.orange))
                        .scaleEffect(1.3)
                    Text(isArabic
                         ? "جاري إعادة الاتصال… (\(attempt) / 99)"
                         : "Reconnecting… (\(attempt) / 99)")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }

            case .error(_):
                Color.black.opacity(0.75)
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(IptvColors.error)
                    Text(isArabic ? "فشل التشغيل" : "Playback failed")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text(isArabic
                         ? "قد تكون هذه القناة غير متاحة أو الرابط معطل."
                         : "This channel may be offline or the link is broken.")
                        .font(.system(size: 12))
                        .foregroundColor(IptvColors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(action: { vm.retry(urlString: channel.url) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text(isArabic ? "إعادة المحاولة" : "Retry")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(IptvColors.background)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(IptvColors.cyan)
                        .clipShape(Capsule())
                    }
                }
                .padding()

            case .ready:
                EmptyView()
            }
        }
        .onAppear { vm.load(channel: channel) }
        .onChange(of: channel) { newChannel in vm.load(channel: newChannel) }
    }
}
