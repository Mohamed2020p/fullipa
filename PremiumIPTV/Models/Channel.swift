import Foundation

struct Channel: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let url: String
    let category: String
    let logo: String

    init(name: String, url: String, category: String, logo: String) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.category = category
        self.logo = logo
    }

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
