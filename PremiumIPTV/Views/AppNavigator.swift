import SwiftUI

private let DEFAULT_PLAYLIST_URL = "https://roamingadmin.incentivetravel.co.ke/ALFA_DATA/playlist.m3u"

struct AppNavigator: View {
    @StateObject private var prefs = AppPreferences()
    @State private var db = ChannelRepository()
    @State private var screen: Screen = .splash
    @State private var progress = 0

    enum Screen {
        case splash, loadingSaved, languageSelection, sourceChoice,
             loadingDefault, uploadPlaylist, homeDashboard
    }

    var body: some View {
        Group {
            switch screen {
            case .splash:
                SplashView {
                    screen = prefs.hasProfile ? .loadingSaved : .languageSelection
                }
                .transition(.opacity)

            case .loadingSaved:
                LoadingView(
                    text: isArabic ? "جاري تحميل ملفك الشخصي…" : "Loading Your Profile…",
                    subText: progress > 0 ? "Parsed \(progress) channels" : ""
                )
                .task { await loadSavedProfile() }
                .transition(.opacity)

            case .languageSelection:
                LanguageSelectionView { lang in
                    prefs.languageCode = lang
                    screen = .sourceChoice
                }
                .transition(.opacity)

            case .sourceChoice:
                SourceChoiceView(
                    isArabic: isArabic,
                    onUseDefault: { screen = .loadingDefault },
                    onUseCustom:  { screen = .uploadPlaylist }
                )
                .transition(.opacity)

            case .loadingDefault:
                LoadingView(
                    text: isArabic ? "جاري سحب وتجهيز القنوات…" : "Fetching & Processing Channels…",
                    subText: progress > 0 ? "Parsed \(progress) channels" : ""
                )
                .task { await loadDefaultPlaylist() }
                .transition(.opacity)

            case .uploadPlaylist:
                UploadPlaylistView(
                    isArabic: isArabic,
                    prefs: prefs,
                    db: db,
                    onPlaylistLoaded: { count, name, isUrl, path in
                        prefs.hasProfile      = true
                        prefs.profileName     = name
                        prefs.sourceIsUrl     = isUrl
                        prefs.sourcePath      = path
                        prefs.isDefaultSource = false
                        prefs.lastFetchTimestamp = Date().timeIntervalSince1970
                        screen = .homeDashboard
                    }
                )
                .transition(.opacity)

            case .homeDashboard:
                HomeDashboardView(
                    db: db,
                    isArabic: isArabic,
                    prefs: prefs,
                    onLogout: {
                        prefs.logout()
                        screen = .languageSelection
                    },
                    onAdultToggleChanged: { newVal in
                        prefs.allowAdult = newVal
                        screen = .loadingSaved
                    },
                    onSwitchSource: {
                        screen = .sourceChoice
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private var isArabic: Bool { prefs.languageCode == "ar" }

    // MARK: - Async loaders

    private func loadSavedProfile() async {
        progress = 0
        do {
            db.clearAll()
            let count: Int
            if prefs.sourceIsUrl {
                let text = try await fetchM3uText(urlString: prefs.sourcePath)
                count = await Task.detached(priority: .userInitiated) {
                    parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                        DispatchQueue.main.async { progress = p }
                    }
                }.value
            } else {
                // Try to reload from bookmarked file URL
                guard let url = URL(string: prefs.sourcePath),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    await MainActor.run {
                        if prefs.isDefaultSource { screen = .sourceChoice }
                        else { prefs.logout(); screen = .uploadPlaylist }
                    }
                    return
                }
                count = await Task.detached(priority: .userInitiated) {
                    parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                        DispatchQueue.main.async { progress = p }
                    }
                }.value
            }
            await MainActor.run {
                if count > 0 {
                    prefs.lastFetchTimestamp = Date().timeIntervalSince1970
                    screen = .homeDashboard
                } else if prefs.isDefaultSource {
                    screen = .sourceChoice
                } else {
                    prefs.logout()
                    screen = .uploadPlaylist
                }
            }
        } catch {
            await MainActor.run {
                if prefs.isDefaultSource { screen = .sourceChoice }
                else { prefs.logout(); screen = .uploadPlaylist }
            }
        }
    }

    private func loadDefaultPlaylist() async {
        progress = 0
        do {
            let text = try await fetchM3uText(urlString: DEFAULT_PLAYLIST_URL)
            db.clearAll()
            let count = await Task.detached(priority: .userInitiated) {
                parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                    DispatchQueue.main.async { progress = p }
                }
            }.value
            await MainActor.run {
                if count > 0 {
                    prefs.hasProfile      = true
                    prefs.profileName     = "Premium IPTV Player"
                    prefs.sourceIsUrl     = true
                    prefs.sourcePath      = DEFAULT_PLAYLIST_URL
                    prefs.isDefaultSource = true
                    prefs.lastFetchTimestamp = Date().timeIntervalSince1970
                    screen = .homeDashboard
                } else {
                    screen = .sourceChoice
                }
            }
        } catch {
            await MainActor.run { screen = .sourceChoice }
        }
    }
}
