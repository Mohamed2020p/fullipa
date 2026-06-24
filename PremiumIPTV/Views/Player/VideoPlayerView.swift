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
        vc.allowsPictureInPicturePlayback = true
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

// MARK: - Main Player ViewModel
final class ChannelPlayerViewModel: ObservableObject {
    @Published var uiState: PlayerUIState = .buffering

    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var stalledToken: NSObjectProtocol?
    private var endTimeToken: NSObjectProtocol?

    // Tracks real, repeated stalls so we only reconnect when something is
    // actually wrong, not on every single momentary buffer dip.
    private var recentStallTimestamps: [Date] = []
    private var isReconnecting = false

    let player: AVPlayer = {
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        // مهم جداً للـ live streams
        p.preventsDisplaySleepDuringVideoPlayback = true
        return p
    }()

    init() {
        // FIX (issue 1): drive the buffering UI from timeControlStatus instead
        // of from the AVPlayerItemPlaybackStalled notification. timeControlStatus
        // automatically flips back to .playing once AVPlayer recovers from a
        // brief stall on its own, so the spinner clears itself - we don't need
        // to manually reset anything, and we never tear the stream down for it.
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self, !self.isReconnecting else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.uiState = .ready
                case .waitingToPlayAtSpecifiedRate:
                    self.uiState = .buffering
                case .paused:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    func load(channel: Channel) {
        reconnectTask?.cancel()
        reconnectAttempt = 0
        recentStallTimestamps.removeAll()
        isReconnecting = false
        uiState = .buffering
        internalLoad(urlString: channel.url)
    }

    private func internalLoad(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed) else {
            uiState = .error("INVALID_URL")
            return
        }

        // FIX: استخدم AVURLAsset مع custom headers بدل AVPlayerItem مباشرةً
        let headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "*/*",
            "Connection": "keep-alive"
        ]

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
            // مهم للـ .ts streams - بلاش precise timing
            "AVURLAssetPreferPreciseDurationAndTimingKey": false
        ])

        let item = AVPlayerItem(asset: asset)
        // FIX (issue 1): bigger cushion = far fewer false-positive stalls on
        // live streams. 3s was too thin; 8s gives AVPlayer real room to absorb
        // normal network jitter without ever hitting "stalled".
        item.preferredForwardBufferDuration = 8.0

        removeItemObservers()
        isReconnecting = false
        player.replaceCurrentItem(with: item)

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.reconnectAttempt = 0
                    self?.recentStallTimestamps.removeAll()
                    self?.isReconnecting = false
                    self?.player.play()
                case .failed:
                    // A real, fatal AVFoundation error - this is worth reconnecting for.
                    self?.handleError(urlString: urlString)
                default:
                    break
                }
            }
        }

        stalledToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.registerStall(urlString: urlString)
        }

        endTimeToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }

        player.play()
    }

    // FIX (issue 1): a single stall does NOT mean the server/stream is dead -
    // AVPlayer recovers from it on its own almost every time, and the
    // timeControlStatus observer above already shows "buffering" while it
    // does. We only tear down and reconnect if real stalls keep recurring
    // repeatedly in a short window, which is a much stronger signal that the
    // stream is actually broken rather than just hiccuping.
    private func registerStall(urlString: String) {
        let now = Date()
        recentStallTimestamps.append(now)
        recentStallTimestamps = recentStallTimestamps.filter { now.timeIntervalSince($0) < 60 }

        guard recentStallTimestamps.count >= 4 else { return }
        recentStallTimestamps.removeAll()
        handleError(urlString: urlString)
    }

    private func handleError(urlString: String) {
        reconnectTask?.cancel()
        isReconnecting = true
        reconnectAttempt += 1
        uiState = .reconnecting(attempt: reconnectAttempt)
        let delay: UInt64
        switch reconnectAttempt {
        case 1, 2: delay = 2_000_000_000
        case 3, 4, 5: delay = 4_000_000_000
        default: delay = 6_000_000_000
        }
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.internalLoad(urlString: urlString) }
        }
    }

    func retry(urlString: String) {
        reconnectAttempt = 0
        recentStallTimestamps.removeAll()
        reconnectTask?.cancel()
        isReconnecting = false
        uiState = .buffering
        internalLoad(urlString: urlString)
    }

    // FIX: the old code called NotificationCenter.default.removeObserver(self),
    // which is a no-op for block-based observers (self was never registered as
    // the observer - the tokens returned by addObserver(forName:...:using:)
    // are what need to be removed). That meant every reconnect/channel change
    // left old observers registered forever. We now store and remove the
    // actual tokens.
    private func removeItemObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let stalledToken { NotificationCenter.default.removeObserver(stalledToken) }
        if let endTimeToken { NotificationCenter.default.removeObserver(endTimeToken) }
        stalledToken = nil
        endTimeToken = nil
    }

    deinit {
        reconnectTask?.cancel()
        timeControlObserver?.invalidate()
        removeItemObservers()
    }
}

struct ChannelPlayerWidget: View {
    let channel: Channel
    let isArabic: Bool
    @Binding var isFullScreen: Bool

    @StateObject private var vm = ChannelPlayerViewModel()

    var body: some View {
        ZStack {
            Color.black
            VideoPlayerView(player: vm.player)

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
                    Text(isArabic ? "إعادة الاتصال… (\(attempt))" : "Reconnecting… (\(attempt))")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
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
                    Text(isArabic ? "القناة غير متاحة أو الرابط معطل" : "Channel offline or link broken")
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

            // FIX (issue 3): this top bar is now drawn LAST so it always sits
            // above the buffering/reconnecting/error overlays above. Before,
            // the semi-transparent Color overlays in those states were drawn
            // on top of this button and silently absorbed every tap - which is
            // why the fullscreen button "did nothing" almost any time you
            // tapped it (the player was buffering/reconnecting nearly
            // constantly because of issue 1).
            VStack {
                HStack {
                    Button(action: { withAnimation { isFullScreen.toggle() } }) {
                        ZStack {
                            Circle()
                                .fill(IptvColors.scrimLight)
                                .frame(width: 32, height: 32)
                            Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                    }
                    Spacer()
                    Text(channel.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Spacer()
            }
            .zIndex(10)
        }
        .onAppear { vm.load(channel: channel) }
        .onChange(of: channel) { newChannel in vm.load(channel: newChannel) }
    }
}
