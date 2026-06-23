import SwiftUI
import UniformTypeIdentifiers

struct UploadPlaylistView: View {
    let isArabic: Bool
    let prefs: AppPreferences
    let db: ChannelRepository
    let onPlaylistLoaded: (Int, String, Bool, String) -> Void

    @State private var inputMode   = "link"
    @State private var profileName = ""
    @State private var m3uUrl      = ""
    @State private var urlError: String? = nil
    @State private var isProcessing = false
    @State private var progress     = 0
    @State private var showFilePicker = false
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if isProcessing {
                LoadingView(
                    text: isArabic ? "جاري سحب وتجهيز القنوات…" : "Fetching & Processing Channels…",
                    subText: progress > 0 ? "Parsed \(progress) channels" : ""
                )
            } else {
                mainContent
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFilePick(result: result)
        }
        .alert(isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Alert(title: Text("Error"), message: Text(errorMessage ?? ""), dismissButton: .default(Text("OK")))
        }
    }

    private var mainContent: some View {
        ZStack {
            IptvColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: Spacing.xl3)
                    ZStack {
                        Circle()
                            .fill(IptvColors.cyanSoft)
                            .frame(width: 76, height: 76)
                            .overlay(Circle().stroke(IptvColors.cyan.opacity(0.25), lineWidth: 1))
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .font(.system(size: 36))
                            .foregroundColor(IptvColors.cyan)
                    }
                    Spacer().frame(height: Spacing.lg)
                    Text(isArabic ? "إعداد حساب IPTV" : "Setup IPTV Profile")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(IptvColors.textPrimary)
                    Spacer().frame(height: Spacing.xl)

                    // Segment tabs
                    HStack(spacing: 0) {
                        SegmentTab(
                            label: isArabic ? "رابط URL" : "URL Link",
                            isSelected: inputMode == "link"
                        ) { inputMode = "link" }
                        SegmentTab(
                            label: isArabic ? "ملف محلي" : "Local File",
                            isSelected: inputMode == "file"
                        ) { inputMode = "file" }
                    }
                    .background(IptvColors.surfaceElevated)
                    .cornerRadius(IptvRadius.medium)
                    .overlay(RoundedRectangle(cornerRadius: IptvRadius.medium).stroke(IptvColors.border, lineWidth: 1))
                    .padding(4)

                    Spacer().frame(height: Spacing.xl)
                    IptvTextField(
                        text: $profileName,
                        label: isArabic ? "اسم الحساب (اختياري)" : "Profile Name (Optional)"
                    )
                    Spacer().frame(height: Spacing.lg)

                    if inputMode == "link" {
                        VStack(spacing: Spacing.xl) {
                            IptvTextField(
                                text: $m3uUrl,
                                label: isArabic ? "رابط قائمة M3U" : "M3U Playlist URL",
                                isError: urlError != nil,
                                errorText: urlError
                            )
                            PrimaryButton(
                                title: isArabic ? "اتصال وتحميل" : "Connect & Load"
                            ) {
                                loadFromUrl()
                            }
                        }
                    } else {
                        Button(action: { showFilePicker = true }) {
                            VStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(IptvColors.cyan)
                                Text(isArabic ? "اختر ملف M3U من الجهاز" : "Select M3U File")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(IptvColors.textPrimary)
                                Text(".m3u  .m3u8")
                                    .font(.system(size: 12))
                                    .foregroundColor(IptvColors.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .background(IptvColors.surfaceElevated)
                            .cornerRadius(IptvRadius.large)
                            .overlay(
                                RoundedRectangle(cornerRadius: IptvRadius.large)
                                    .stroke(
                                        LinearGradient(
                                            colors: [IptvColors.cyan.opacity(0.5), IptvColors.orange.opacity(0.5)],
                                            startPoint: .leading, endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                        }
                    }
                    Spacer().frame(height: Spacing.xl3)
                }
                .padding(.horizontal, Spacing.xl)
            }
        }
    }

    private func loadFromUrl() {
        let trimmed = m3uUrl.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            urlError = isArabic ? "الرجاء إدخال رابط القائمة أولاً." : "Please enter a playlist URL first."
            return
        }
        urlError = nil
        isProcessing = true
        Task {
            do {
                let text = try await fetchM3uText(urlString: trimmed)
                let count = await Task.detached(priority: .userInitiated) {
                    self.db.clearAll()
                    return parseAndInsert(text: text, allowAdult: self.prefs.allowAdult, db: self.db) { p in
                        DispatchQueue.main.async { self.progress = p }
                    }
                }.value
                await MainActor.run {
                    isProcessing = false
                    if count > 0 {
                        let name = profileName.isEmpty ? (isArabic ? "حساب السيرفر" : "Server Profile") : profileName
                        onPlaylistLoaded(count, name, true, trimmed)
                    } else {
                        errorMessage = isArabic
                            ? "فشل التحميل من الرابط. تحقق من الرابط واتصالك بالإنترنت."
                            : "Failed to load from URL. Check the link and your connection."
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = isArabic
                        ? "فشل التحميل من الرابط. تحقق من الرابط واتصالك بالإنترنت."
                        : "Failed to load from URL. Check the link and your connection."
                }
            }
        }
    }

    private func handleFilePick(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isProcessing = true
            Task.detached(priority: .userInitiated) {
                guard url.startAccessingSecurityScopedResource() else {
                    await MainActor.run { isProcessing = false; errorMessage = "Cannot access file." }
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    guard isLikelyM3u(content: text) else {
                        await MainActor.run {
                            isProcessing = false
                            errorMessage = isArabic
                                ? "ملف غير صالح! الرجاء اختيار ملف m3u. أو m3u8."
                                : "Invalid file! Please select an .m3u or .m3u8 file."
                        }
                        return
                    }
                    await MainActor.run { self.db.clearAll() }
                    let count = parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                        DispatchQueue.main.async { self.progress = p }
                    }
                    await MainActor.run {
                        isProcessing = false
                        if count > 0 {
                            let name = profileName.isEmpty
                                ? (isArabic ? "حسابي المحلي" : "My Local Profile")
                                : profileName
                            // store bookmark for future access
                            if let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                                UserDefaults.standard.set(bookmark, forKey: "file_bookmark")
                            }
                            onPlaylistLoaded(count, name, false, url.absoluteString)
                        } else {
                            errorMessage = isArabic
                                ? "لم يتم العثور على أي قنوات في هذا الملف."
                                : "No channels found in this file."
                        }
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        errorMessage = isArabic
                            ? "ملف غير صالح! الرجاء اختيار ملف m3u. أو m3u8."
                            : "Invalid file!"
                    }
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

private struct SegmentTab: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSelected ? IptvColors.background : IptvColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(isSelected ? IptvColors.cyan : Color.clear)
                .cornerRadius(IptvRadius.small)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
