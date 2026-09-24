import Foundation

struct Entry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var merchant: String
    var amount: Double
    var category: Category
    var account: String
    var reviewed = false
    var modified = Date()
}
enum Category: String, Codable, CaseIterable, Identifiable {
    case groceries = "Groceries", dining = "Food & drink", shopping = "Shopping", transport = "Transport", home = "Home", health = "Health", entertainment = "Entertainment", travel = "Travel", income = "Income & payments", other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .groceries: "basket.fill"
        case .dining: "fork.knife"
        case .shopping: "bag.fill"
        case .transport: "car.fill"
        case .home: "house.fill"
        case .health: "cross.case.fill"
        case .entertainment: "play.rectangle.fill"
        case .travel: "airplane"
        case .income: "arrow.down.left"
        case .other: "square.grid.2x2.fill"
        }
    }
    static func suggest(_ text: String) -> Category {
        let s = text.lowercased()
        let rules: [(Category, [String])] = [(.income,["payment received","payroll","refund","autopay payment"]),(.groceries,["trader joe","whole foods","safeway","grocery","costco"]),(.dining,["coffee","starbucks","restaurant","cafe","doordash","sweetgreen"]),(.transport,["uber","lyft","shell","chevron","parking"]),(.entertainment,["netflix","spotify","hulu","apple.com","disney"]),(.home,["electric","water","rent","internet","comcast"]),(.health,["pharmacy","cvs","medical"]),(.travel,["airlines","hotel","airbnb"]),(.shopping,["amazon","target","store","nike"])]
        return rules.first { $0.1.contains(where: s.contains) }?.0 ?? .other
    }
}
struct Card: Identifiable, Codable {
    var id = UUID()
    var name: String
    var lastFour: String
    var balance: Double
    var limit: Double
    var due: Date
    var minimum: Double
    var modified = Date()
}
struct Statement: Identifiable, Codable {
    var id = UUID()
    var name: String
    var imported = Date()
    var count: Int
    var data: Data
}
struct Household: Codable {
    var entries: [Entry] = []
    var cards: [Card] = []
    var statements: [Statement] = []
}
extension Double {
    var money: String { formatted(.currency(code: "USD")) }
}
enum Insights {
    static func key(_ s: String) -> String { s.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }.joined(separator: " ") }
    static func recurring(_ entries: [Entry]) -> Set<UUID> {
        var result = Set<UUID>()
        for group in Dictionary(grouping: entries.filter { $0.amount > 0 }, by: { key($0.merchant) }).values {
            let sorted = group.sorted { $0.date < $1.date }
            for pair in zip(sorted, sorted.dropFirst()) {
                let days = pair.1.date.timeIntervalSince(pair.0.date) / 86400
                let similar = abs(pair.1.amount - pair.0.amount) <= max(2, pair.0.amount * 0.1)
                if similar && ((6...8).contains(days) || (25...35).contains(days) || (350...380).contains(days)) {
                    result.insert(pair.0.id); result.insert(pair.1.id)
                }
            }
        }
        return result
    }
    static func unusual(_ entry: Entry, in entries: [Entry]) -> Bool {
        guard entry.amount > 0, !entry.reviewed else { return false }
        let peers = entries.filter { $0.id != entry.id && $0.category == entry.category && $0.amount > 0 }
        guard peers.count >= 3 else { return entry.amount >= 500 }
        let sorted = peers.map(\.amount).sorted()
        return entry.amount > max(150, sorted[sorted.count / 2] * 3)
    }
}
extension Household {
    static var demo: Household {
        let now = Date()
        func ago(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: now)! }
        let entries: [Entry] = [
            Entry(date: ago(0), merchant: "Whole Foods Market", amount: 86.42, category: .groceries, account: "Sapphire Preferred"),
            Entry(date: ago(1), merchant: "Blue Bottle Coffee", amount: 12.50, category: .dining, account: "Sapphire Preferred"),
            Entry(date: ago(1), merchant: "West Elm", amount: 649, category: .shopping, account: "Blue Cash Everyday"),
            Entry(date: ago(2), merchant: "Netflix", amount: 15.49, category: .entertainment, account: "Sapphire Preferred"),
            Entry(date: ago(32), merchant: "Netflix", amount: 15.49, category: .entertainment, account: "Sapphire Preferred"),
            Entry(date: ago(3), merchant: "Trader Joe’s", amount: 73.18, category: .groceries, account: "Blue Cash Everyday"),
            Entry(date: ago(4), merchant: "Spotify", amount: 16.99, category: .entertainment, account: "Sapphire Preferred"),
            Entry(date: ago(34), merchant: "Spotify", amount: 16.99, category: .entertainment, account: "Sapphire Preferred"),
            Entry(date: ago(5), merchant: "Sweetgreen", amount: 32.80, category: .dining, account: "Sapphire Preferred"),
            Entry(date: ago(6), merchant: "Shell", amount: 58.24, category: .transport, account: "Blue Cash Everyday"),
            Entry(date: ago(7), merchant: "Pacific Gas & Electric", amount: 142.60, category: .home, account: "Checking"),
            Entry(date: ago(8), merchant: "Target", amount: 64.28, category: .shopping, account: "Blue Cash Everyday")]
        return Household(entries: entries, cards: [Card(name: "Sapphire Preferred", lastFour: "4829", balance: 1248.62, limit: 10000, due: Calendar.current.date(byAdding: .day, value: 8, to: now)!, minimum: 40), Card(name: "Blue Cash Everyday", lastFour: "1006", balance: 864.30, limit: 8000, due: Calendar.current.date(byAdding: .day, value: 15, to: now)!, minimum: 35)])
    }
}
