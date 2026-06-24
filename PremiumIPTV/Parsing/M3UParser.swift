import Foundation

// MARK: - Adult filter
func isStrictlyAdult(name: String, category: String) -> Bool {
    let lower = "\(name) \(category)".lowercased()
    let keywords = ["xxx", "porn", "adults only", "brazzers", "playboy", "18+", "vivid", "hustler"]
    return keywords.contains { lower.contains($0) }
}

// MARK: - Decoding helpers
// FIX (issue 2): m3u files from Windows-based playlist tools / IPTV panels
// are very often NOT clean UTF-8 (accented channel names saved as
// Latin-1/Windows-1252 are common), and very often start with a UTF-8
// byte-order mark (BOM). Before this fix, the file-picker path only tried
// .utf8 and rejected the file outright if that failed, and a leading BOM
// made the "#EXTM3U" header check fail even on a perfectly valid playlist
// (the line became "\u{FEFF}#EXTM3U", which doesn't match hasPrefix("#")).
// Both the URL-fetch path and the file-picker path now go through these
// two helpers so a valid playlist is recognized either way.
func decodeM3uData(_ data: Data) -> String {
    let raw = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .isoLatin1)
        ?? String(data: data, encoding: .windowsCP1252)
        ?? ""
    return stripBOM(raw)
}

func stripBOM(_ text: String) -> String {
    if text.hasPrefix("\u{FEFF}") {
        return String(text.dropFirst())
    }
    return text
}

// MARK: - URL detection
func isLikelyM3u(content: String) -> Bool {
    let lines = content.components(separatedBy: .newlines)
    var sawExtinf = false
    var sawStream = false
    for line in lines.prefix(40) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { continue }
        if t.uppercased().hasPrefix("#EXTM3U") { return true }
        if t.uppercased().hasPrefix("#EXTINF") { sawExtinf = true }
        if !t.hasPrefix("#") &&
           (t.hasPrefix("http://") || t.hasPrefix("https://") ||
            t.hasPrefix("rtmp://") || t.hasPrefix("rtsp://")) {
            sawStream = true
        }
        if sawExtinf && sawStream { return true }
    }
    return sawExtinf || sawStream
}

// MARK: - Parse lines into Channel array
func parseLinesToChannels(
    text: String,
    allowAdult: Bool,
    onProgress: @escaping (Int) -> Void
) -> [Channel] {
    let lines = text.components(separatedBy: .newlines)
    var results: [Channel] = []
    results.reserveCapacity(min(lines.count / 2, 50_000))

    var currentName     = "Unknown Channel"
    var currentCategory = "General"
    var currentLogo     = ""

    let groupRegex = try? NSRegularExpression(pattern: #"group-title="([^"]+)""#)
    let logoRegex  = try? NSRegularExpression(pattern: #"tvg-logo="([^"]+)""#)

    func regexFirst(_ regex: NSRegularExpression?, in s: String) -> String? {
        guard let regex = regex else { return nil }
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let r = m.range(at: 1)
        return r.location != NSNotFound ? ns.substring(with: r) : nil
    }

    for (idx, line) in lines.enumerated() {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.uppercased().hasPrefix("#EXTINF:") {
            currentCategory = regexFirst(groupRegex, in: t) ?? "General"
            currentLogo     = regexFirst(logoRegex,  in: t) ?? ""
            if let commaIdx = t.lastIndex(of: ",") {
                currentName = String(t[t.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                currentName = "Unknown Channel"
            }
        } else if !t.isEmpty && !t.hasPrefix("#") {
            if allowAdult || !isStrictlyAdult(name: currentName, category: currentCategory) {
                results.append(Channel(name: currentName, url: t, category: currentCategory, logo: currentLogo))
            }
            currentName     = "Unknown Channel"
            currentCategory = "General"
            currentLogo     = ""
        }
        if idx % 5000 == 0 { onProgress(results.count) }
    }
    onProgress(results.count)
    return results
}

// MARK: - Fetch from URL
func fetchM3uText(urlString: String) async throws -> String {
    guard let url = URL(string: urlString) else { throw URLError(.badURL) }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
    request.setValue("*/*", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    // FIX: now shares the same decode + BOM-strip helper as the file picker.
    return decodeM3uData(data)
}

// MARK: - Parse + batch insert
func parseAndInsert(
    text: String,
    allowAdult: Bool,
    db: ChannelRepository,
    onProgress: @escaping (Int) -> Void
) -> Int {
    let batchSize = 1000
    let lines = text.components(separatedBy: .newlines)
    var batch: [Channel] = []
    var total = 0
    var currentName     = "Unknown Channel"
    var currentCategory = "General"
    var currentLogo     = ""

    let groupRegex = try? NSRegularExpression(pattern: #"group-title="([^"]+)""#)
    let logoRegex  = try? NSRegularExpression(pattern: #"tvg-logo="([^"]+)""#)

    func regexFirst(_ regex: NSRegularExpression?, in s: String) -> String? {
        guard let regex = regex else { return nil }
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let r = m.range(at: 1)
        return r.location != NSNotFound ? ns.substring(with: r) : nil
    }

    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.uppercased().hasPrefix("#EXTINF:") {
            currentCategory = regexFirst(groupRegex, in: t) ?? "General"
            currentLogo     = regexFirst(logoRegex,  in: t) ?? ""
            if let commaIdx = t.lastIndex(of: ",") {
                currentName = String(t[t.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                currentName = "Unknown Channel"
            }
        } else if !t.isEmpty && !t.hasPrefix("#") {
            if allowAdult || !isStrictlyAdult(name: currentName, category: currentCategory) {
                batch.append(Channel(name: currentName, url: t, category: currentCategory, logo: currentLogo))
                if batch.count >= batchSize {
                    db.insertBatch(batch)
                    total += batch.count
                    onProgress(total)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            currentName     = "Unknown Channel"
            currentCategory = "General"
            currentLogo     = ""
        }
    }
    if !batch.isEmpty {
        db.insertBatch(batch)
        total += batch.count
        onProgress(total)
    }
    return total
}
