import SwiftUI

private let DEFAULT_PLAYLIST_URL = "https://roamingadmin.incentivetravel.co.ke/ALFA_DATA/playlist.m3u"
private let FRESHNESS_MS: Double = 30 * 60 * 1000

struct HomeDashboardView: View {
    let db: ChannelRepository
    let isArabic: Bool
    let prefs: AppPreferences
    let onLogout: () -> Void
    let onAdultToggleChanged: (Bool) -> Void
    let onSwitchSource: () -> Void

    @State private var selectedChannel: Channel? = nil
    @State private var searchQuery     = ""
    @State private var selectedCategory = "__all__"
    @State private var channels: [Channel] = []
    @State private var offset    = 0
    @State private var totalCount = 0
    @State private var categories: [String] = []
    @State private var isLoadingMore = false
    @State private var isFullScreen  = false
    @State private var drawerOpen    = false

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 12)]

    var body: some View {
        ZStack(alignment: .leading) {
            // Main content
            ZStack {
                IptvColors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Player area
                    if let ch = selectedChannel {
                        ChannelPlayerWidget(
                            channel: ch,
                            isArabic: isArabic,
                            isFullScreen: $isFullScreen
                        )
                        .frame(height: isFullScreen ? UIScreen.main.bounds.height : 230)
                        .ignoresSafeArea(edges: isFullScreen ? .all : [])
                    } else if !isFullScreen {
                        playerPlaceholder
                    }

                    if !isFullScreen {
                        topBar
                        searchBar
                        categoryRow
                        channelGrid
                    }
                }
            }
            .disabled(drawerOpen)

            // Drawer scrim
            if drawerOpen {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { drawerOpen = false } }
            }

            // Drawer panel
            if drawerOpen {
                HStack {
                    DrawerPanel(
                        isArabic: isArabic,
                        allowAdult: prefs.allowAdult,
                        isDefaultSource: prefs.isDefaultSource,
                        onAdultToggle: { newVal in
                            onAdultToggleChanged(newVal)
                            withAnimation { drawerOpen = false }
                        },
                        onLogout: {
                            withAnimation { drawerOpen = false }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onLogout() }
                        },
                        onSwitchSource: {
                            withAnimation { drawerOpen = false }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onSwitchSource() }
                        }
                    )
                    .frame(width: 300)
                    .transition(.move(edge: .leading))
                    Spacer()
                }
                .ignoresSafeArea()
            }
        }
        .onAppear { loadInitial() }
        .onChange(of: selectedCategory) { _ in loadInitial() }
        .onChange(of: searchQuery) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { loadInitial() }
        }
        .task {
            // Background refresh for default playlist
            guard prefs.isDefaultSource else { return }
            while true {
                try? await Task.sleep(nanoseconds: UInt64(FRESHNESS_MS) * 1_000_000)
                if let text = try? await fetchM3uText(urlString: DEFAULT_PLAYLIST_URL) {
                    db.clearAll()
                    _ = parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { _ in }
                    prefs.lastFetchTimestamp = Date().timeIntervalSince1970
                }
            }
        }
    }

    // MARK: - Sub-views

    private var playerPlaceholder: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(IptvColors.surfaceElevated)
                        .frame(width: 64, height: 64)
                        .overlay(Circle().stroke(IptvColors.cyan.opacity(0.2), lineWidth: 1))
                    Image(systemName: "play.circle")
                        .font(.system(size: 32))
                        .foregroundColor(IptvColors.cyan)
                }
                Text(isArabic ? "اختر قناة للتشغيل" : "Select a channel to play")
                    .font(.system(size: 15))
                    .foregroundColor(IptvColors.textSecondary)
            }
        }
        .frame(height: 230)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: { withAnimation { drawerOpen.toggle() } }) {
                ZStack {
                    Circle()
                        .fill(IptvColors.surfaceElevated)
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(IptvColors.border, lineWidth: 0.5))
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18))
                        .foregroundColor(IptvColors.textPrimary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(prefs.profileName.isEmpty ? "Premium IPTV" : prefs.profileName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(IptvColors.textPrimary)
                Text("\(totalCount) \(isArabic ? "قناة" : "Channels")")
                    .font(.system(size: 12))
                    .foregroundColor(IptvColors.cyan)
            }
            Spacer()
        }
        .padding(Spacing.lg)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(IptvColors.textMuted)
            TextField(isArabic ? "البحث عن قناة…" : "Search channels…", text: $searchQuery)
                .foregroundColor(IptvColors.textPrimary)
                .autocorrectionDisabled()
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark")
                        .foregroundColor(IptvColors.textMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(IptvColors.surfaceElevated)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                searchQuery.isEmpty ? IptvColors.border : IptvColors.cyan.opacity(0.3),
                lineWidth: 1
            )
        )
        .padding(.horizontal, Spacing.lg)
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    label: isArabic ? "الكل" : "All",
                    isSelected: selectedCategory == "__all__",
                    action: { selectedCategory = "__all__" }
                )
                ForEach(categories, id: \.self) { cat in
                    CategoryChip(label: cat, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
        .padding(.vertical, Spacing.md)
    }

    @ViewBuilder
    private var channelGrid: some View {
        if channels.isEmpty && !isLoadingMore {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(channels.enumerated()), id: \.element.url) { (index, ch) in
                        ChannelCardView(
                            channel: ch,
                            channelNumber: index + 1,
                            isSelected: selectedChannel?.url == ch.url,
                            isArabic: isArabic,
                            onTap: { selectedChannel = ch }
                        )
                        .onAppear {
                            if index == channels.count - 8 { loadMore() }
                        }
                    }
                    if isLoadingMore {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: IptvColors.cyan))
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(IptvColors.surfaceElevated)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(IptvColors.border, lineWidth: 1))
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(IptvColors.textMuted)
            }
            Text(searchQuery.isEmpty
                 ? (isArabic ? "لا توجد قنوات" : "No channels")
                 : (isArabic ? "لا توجد قنوات تطابق \"\(searchQuery)\"" : "No channels match \"\(searchQuery)\""))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(IptvColors.textPrimary)
                .multilineTextAlignment(.center)
            Text(isArabic ? "جرب كلمة بحث أخرى أو فئة مختلفة" : "Try a different search term or category")
                .font(.system(size: 12))
                .foregroundColor(IptvColors.textSecondary)
            Spacer()
        }
        .padding(Spacing.xl)
    }

    // MARK: - Data loading
    private func loadInitial() {
        isLoadingMore = true
        Task.detached(priority: .userInitiated) {
            let cats  = db.getCategories()
            let total = db.getTotalCount(category: selectedCategory, search: searchQuery)
            let first = db.getChannelsPage(category: selectedCategory, search: searchQuery, offset: 0, limit: 60)
            await MainActor.run {
                categories  = cats
                totalCount  = total
                channels    = first
                offset      = 0
                isLoadingMore = false
            }
        }
    }

    private func loadMore() {
        guard !isLoadingMore, channels.count < totalCount else { return }
        isLoadingMore = true
        let nextOffset = offset + 60
        Task.detached(priority: .userInitiated) {
            let more = db.getChannelsPage(category: selectedCategory, search: searchQuery, offset: nextOffset, limit: 60)
            await MainActor.run {
                channels += more
                offset    = nextOffset
                isLoadingMore = false
            }
        }
    }
}

// MARK: - Category Chip
private struct CategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isSelected ? IptvColors.background : IptvColors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? IptvColors.cyan : IptvColors.surfaceElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : IptvColors.border, lineWidth: 1)
                )
                .shadow(color: isSelected ? IptvColors.cyanGlow : .clear, radius: 6)
        }
    }
}

// MARK: - Drawer Panel
private struct DrawerPanel: View {
    let isArabic: Bool
    let allowAdult: Bool
    let isDefaultSource: Bool
    let onAdultToggle: (Bool) -> Void
    let onLogout: () -> Void
    let onSwitchSource: () -> Void

    @State private var adultToggle: Bool

    init(isArabic: Bool, allowAdult: Bool, isDefaultSource: Bool,
         onAdultToggle: @escaping (Bool) -> Void,
         onLogout: @escaping () -> Void,
         onSwitchSource: @escaping () -> Void) {
        self.isArabic = isArabic
        self.allowAdult = allowAdult
        self.isDefaultSource = isDefaultSource
        self.onAdultToggle = onAdultToggle
        self.onLogout = onLogout
        self.onSwitchSource = onSwitchSource
        _adultToggle = State(initialValue: allowAdult)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ZStack {
                LinearGradient(
                    colors: [IptvColors.cyanSoft.opacity(0.6), IptvColors.surface],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(IptvColors.cyanSoft).frame(width: 72, height: 72)
                            .overlay(Circle().stroke(IptvColors.cyan.opacity(0.25), lineWidth: 1.5))
                        Image(systemName: "tv.fill")
                            .font(.system(size: 36))
                            .foregroundColor(IptvColors.cyan)
                    }
                    Text(isArabic ? "المطوّر" : "Developer")
                        .font(.system(size: 12))
                        .foregroundColor(IptvColors.textMuted)
                    Text("mohamed annati")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(IptvColors.textPrimary)
                    Text("c0derz")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(IptvColors.cyan)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }

            Divider().background(IptvColors.border).padding(.horizontal, Spacing.lg)
            Spacer().frame(height: Spacing.xl)

            // Settings
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(isArabic ? "الإعدادات" : "Settings")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(IptvColors.cyan)

                // Adult toggle
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(IptvColors.textSecondary)
                        .frame(width: 20)
                    Text(isArabic ? "إظهار محتوى +18" : "Show 18+ Content")
                        .font(.system(size: 15))
                        .foregroundColor(IptvColors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $adultToggle)
                        .labelsHidden()
                        .tint(IptvColors.cyan)
                        .onChange(of: adultToggle) { v in onAdultToggle(v) }
                }

                // Source indicator
                HStack(spacing: 12) {
                    Image(systemName: isDefaultSource ? "checkmark.icloud.fill" : "folder.fill")
                        .foregroundColor(isDefaultSource ? IptvColors.cyan : IptvColors.orange)
                        .frame(width: 20)
                    Text(isArabic
                         ? (isDefaultSource ? "القائمة الافتراضية (تتحدث تلقائياً)" : "قائمة مخصصة (يدوي)")
                         : (isDefaultSource ? "Default playlist (auto-updated)" : "Custom playlist (manual)"))
                        .font(.system(size: 12))
                        .foregroundColor(IptvColors.textSecondary)
                }
                .padding(Spacing.md)
                .background(IptvColors.background)
                .cornerRadius(IptvRadius.medium)

                // Switch source
                Button(action: onSwitchSource) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundColor(IptvColors.cyan)
                        Text(isArabic ? "تغيير مصدر القائمة" : "Switch Playlist Source")
                            .foregroundColor(IptvColors.textPrimary)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(Capsule().stroke(IptvColors.cyan.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            // Logout
            Button(action: onLogout) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(isArabic ? "تغيير القائمة" : "Change Playlist")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(IptvColors.error)
                .cornerRadius(IptvRadius.medium)
            }
            .padding(.horizontal, Spacing.lg)
            Spacer().frame(height: Spacing.lg)
        }
        .frame(maxHeight: .infinity)
        .background(IptvColors.surface)
        .ignoresSafeArea()
    }
}
