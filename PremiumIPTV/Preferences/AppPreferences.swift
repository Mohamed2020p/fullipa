import Foundation

final class AppPreferences: ObservableObject {
    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let hasProfile       = "has_profile"
        static let profileName      = "profile_name"
        static let sourceIsUrl      = "source_is_url"
        static let sourcePath       = "source_path"
        static let allowAdult       = "allow_adult"
        static let languageCode     = "language_code"
        static let isDefaultSource  = "is_default_source"
        static let lastFetchTs      = "last_fetch_timestamp"
    }

    @Published var hasProfile: Bool {
        didSet { defaults.set(hasProfile, forKey: Key.hasProfile) }
    }
    @Published var profileName: String {
        didSet { defaults.set(profileName, forKey: Key.profileName) }
    }
    @Published var sourceIsUrl: Bool {
        didSet { defaults.set(sourceIsUrl, forKey: Key.sourceIsUrl) }
    }
    @Published var sourcePath: String {
        didSet { defaults.set(sourcePath, forKey: Key.sourcePath) }
    }
    @Published var allowAdult: Bool {
        didSet { defaults.set(allowAdult, forKey: Key.allowAdult) }
    }
    @Published var languageCode: String {
        didSet { defaults.set(languageCode, forKey: Key.languageCode) }
    }
    @Published var isDefaultSource: Bool {
        didSet { defaults.set(isDefaultSource, forKey: Key.isDefaultSource) }
    }
    var lastFetchTimestamp: Double {
        get { defaults.double(forKey: Key.lastFetchTs) }
        set { defaults.set(newValue, forKey: Key.lastFetchTs) }
    }

    init() {
        self.hasProfile      = defaults.bool(forKey: Key.hasProfile)
        self.profileName     = defaults.string(forKey: Key.profileName) ?? ""
        self.sourceIsUrl     = defaults.bool(forKey: Key.sourceIsUrl)
        self.sourcePath      = defaults.string(forKey: Key.sourcePath) ?? ""
        self.allowAdult      = defaults.bool(forKey: Key.allowAdult)
        self.languageCode    = defaults.string(forKey: Key.languageCode) ?? ""
        self.isDefaultSource = defaults.bool(forKey: Key.isDefaultSource)
    }

    func logout() {
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
        hasProfile      = false
        profileName     = ""
        sourceIsUrl     = false
        sourcePath      = ""
        allowAdult      = false
        languageCode    = ""
        isDefaultSource = false
    }
}
