import Foundation

struct Entry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var merchant: String
    var amount: Double
    var category: Category
    var account: String
    var customCategory: String? = nil
    var sourceStatementIDs: [UUID]? = nil
    var cardID: UUID? = nil
    var bankAccountID: UUID? = nil
    var recurringOverride: Bool? = nil
    // Keep the existing persisted expense-positive convention for sync compatibility.
    // All transaction displays and editors use the bank's money-in/money-out signs.
    var signedAmount: Double {
        get { amount == 0 ? 0 : -amount }
        set { amount = newValue == 0 ? 0 : -newValue }
    }
    var signedMoney: String { (signedAmount > 0 ? "+" : "") + signedAmount.money }
    var otherDescription: String {
        get { customCategory ?? "" }
        set { customCategory = newValue.isEmpty ? nil : newValue }
    }
    var categoryName: String {
        let label = otherDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return category == .other && !label.isEmpty ? label : category.rawValue
    }
    var reviewed = false
    var modified = Date()
}
enum Category: String, Codable, CaseIterable, Identifiable {
    case groceries = "Groceries", dining = "Food & drink", shopping = "Shopping", transport = "Transport", home = "Home", utilities = "Utilities", health = "Health", entertainment = "Entertainment", travel = "Travel", income = "Income & payments", other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .groceries: "basket.fill"
        case .dining: "fork.knife"
        case .shopping: "bag.fill"
        case .transport: "car.fill"
        case .home: "house.fill"
        case .utilities: "bolt.fill"
        case .health: "cross.case.fill"
        case .entertainment: "play.rectangle.fill"
        case .travel: "airplane"
        case .income: "arrow.down.left"
        case .other: "square.grid.2x2.fill"
        }
    }
    static func suggest(_ text: String) -> Category {
        let s = text.lowercased()
        let rules: [(Category, [String])] = [(.income,["payment received","payroll","refund","autopay payment"]),(.groceries,["trader joe","whole foods","safeway","grocery","costco"]),(.dining,["coffee","starbucks","restaurant","cafe","doordash","sweetgreen"]),(.transport,["uber","lyft","shell","chevron","parking"]),(.entertainment,["netflix","spotify","hulu","apple.com","disney"]),(.utilities,["electric","water company","water compa","water bill","utilities","utility","internet","comcast","xfinity","natural gas","sewer","pg&e"]),(.home,["rent"]),(.health,["pharmacy","cvs","medical"]),(.travel,["airlines","hotel","airbnb"]),(.shopping,["amazon","target","store","nike"])]
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
enum StatementAccountKind: String, Codable, CaseIterable, Identifiable {
    case checking = "Checking", savings = "Savings", creditCard = "Credit card"
    var id: String { rawValue }
}
struct Statement: Identifiable, Codable {
    var id = UUID()
    var name: String
    var imported = Date()
    var count: Int
    var data: Data
    var notes: String? = nil
    var accountKind: StatementAccountKind? = nil
    var accountID: UUID? = nil
    var endingBalance: Double? = nil
    var balanceDate: Date? = nil
}
struct SavedCategory: Identifiable, Codable {
    var id = UUID()
    var name: String
}
enum CategoryNameError: LocalizedError {
    case invalid, builtIn
    var errorDescription: String? {
        switch self {
        case .invalid: "Enter a category name between 1 and 40 characters."
        case .builtIn: "That category already exists in the standard list."
        }
    }
}
struct SavingsAccount: Identifiable, Codable {
    var id = UUID()
    var name: String
    var balance: Double
    var modified = Date()
    var balanceDate: Date? = nil
    var statementIdentity: String? = nil
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && balance.isFinite && balance >= 0 }
}
struct CheckingAccount: Identifiable, Codable {
    var id = UUID()
    var name: String
    var balance: Double
    var modified = Date()
    var balanceDate: Date? = nil
    var statementIdentity: String? = nil
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && balance.isFinite }
}
struct Household: Codable {
    var entries: [Entry] = []
    var cards: [Card] = []
    var statements: [Statement] = []
    // Optional so households saved before custom categories still decode.
    var savedCategories: [SavedCategory]? = nil
    var savingsAccounts: [SavingsAccount]? = nil
    var checkingAccounts: [CheckingAccount]? = nil
    var positiveCheckingBalance: Double { (checkingAccounts ?? []).reduce(0) { $0 + max(0, $1.balance) } }
    var totalMoneyReceived: Double { entries.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount } }
    mutating func mergeChecking(_ incoming: [CheckingAccount]) {
        var accounts = checkingAccounts ?? []
        for account in incoming {
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                let current = accounts[index]
                let useIncoming: Bool
                if let date = account.balanceDate, let previous = current.balanceDate, date != previous { useIncoming = date > previous }
                else { useIncoming = account.modified > current.modified }
                if useIncoming { accounts[index] = account }
            } else { accounts.append(account) }
        }
        if !accounts.isEmpty { checkingAccounts = accounts }
    }
    var totalSavings: Double { (savingsAccounts ?? []).reduce(0) { $0 + $1.balance } }
    mutating func mergeSavings(_ incoming: [SavingsAccount]) {
        var accounts = savingsAccounts ?? []
        for account in incoming {
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                let current = accounts[index]
                let useIncoming: Bool
                if let date = account.balanceDate, let previous = current.balanceDate, date != previous { useIncoming = date > previous }
                else { useIncoming = account.modified > current.modified }
                if useIncoming { accounts[index] = account }
            } else { accounts.append(account) }
        }
        if !accounts.isEmpty { savingsAccounts = accounts }
    }
    mutating func importEntries(_ incoming: [Entry], statementID: UUID, cardID: UUID?, bankAccountID: UUID? = nil) -> Int {
        for var entry in incoming {
            entry.cardID = cardID
            entry.bankAccountID = bankAccountID
            if let index = entries.firstIndex(where: {
                $0.date == entry.date && $0.merchant == entry.merchant && $0.amount == entry.amount &&
                ($0.bankAccountID != nil && entry.bankAccountID != nil ? $0.bankAccountID == entry.bankAccountID : ($0.cardID != nil && entry.cardID != nil ? $0.cardID == entry.cardID : $0.account == entry.account))
            }) {
                var sources = entries[index].sourceStatementIDs ?? []
                if !sources.contains(statementID) { sources.append(statementID) }
                entries[index].sourceStatementIDs = sources
                if entries[index].cardID == nil { entries[index].cardID = cardID }
                if entries[index].bankAccountID == nil { entries[index].bankAccountID = bankAccountID }
                entries[index].modified = Date()
            } else {
                entry.sourceStatementIDs = [statementID]
                entries.append(entry)
            }
        }
        return entries.filter { ($0.sourceStatementIDs ?? []).contains(statementID) }.count
    }
    func matchingBankAccount(identity: String, kind: StatementAccountKind) -> UUID? {
        let matches: [UUID]
        if kind == .checking { matches = (checkingAccounts ?? []).filter { $0.statementIdentity == identity }.map(\.id) }
        else if kind == .savings { matches = (savingsAccounts ?? []).filter { $0.statementIdentity == identity }.map(\.id) }
        else { return nil }
        return matches.count == 1 ? matches[0] : nil
    }
    mutating func applyStatementBalance(kind: StatementAccountKind, accountID: UUID, name: String, balance: Double, date: Date, identity: String? = nil) {
        guard balance.isFinite else { return }
        if kind == .checking {
            if let existing = (checkingAccounts ?? []).first(where: { $0.id == accountID }), let previous = existing.balanceDate, date < previous { return }
            var account = (checkingAccounts ?? []).first { $0.id == accountID } ?? CheckingAccount(id: accountID, name: name, balance: balance)
            account.balance = balance; account.balanceDate = date; account.modified = Date()
            if account.statementIdentity == nil { account.statementIdentity = identity }
            mergeChecking([account])
        } else if kind == .savings {
            guard balance >= 0 else { return }
            if let existing = (savingsAccounts ?? []).first(where: { $0.id == accountID }), let previous = existing.balanceDate, date < previous { return }
            var account = (savingsAccounts ?? []).first { $0.id == accountID } ?? SavingsAccount(id: accountID, name: name, balance: balance)
            account.balance = balance; account.balanceDate = date; account.modified = Date()
            if account.statementIdentity == nil { account.statementIdentity = identity }
            mergeSavings([account])
        }
    }
    static func categoryKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    var customCategoryNames: [String] {
        let builtIns = Set(Category.allCases.map { Self.categoryKey($0.rawValue) })
        let names = (savedCategories ?? []).map(\.name) + entries.filter { $0.category == .other }.map(\.otherDescription)
        var seen = builtIns
        return names.sorted().compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(Self.categoryKey(name)).inserted else { return nil }
            return name
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    mutating func addCategory(_ raw: String) throws -> String {
        let name = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !name.isEmpty, name.count <= 40 else { throw CategoryNameError.invalid }
        let key = Self.categoryKey(name)
        guard !Category.allCases.contains(where: { Self.categoryKey($0.rawValue) == key }) else { throw CategoryNameError.builtIn }
        let canonical = customCategoryNames.first { Self.categoryKey($0) == key } ?? name
        if !(savedCategories ?? []).contains(where: { Self.categoryKey($0.name) == key }) {
            savedCategories = (savedCategories ?? []) + [SavedCategory(name: canonical)]
        }
        return canonical
    }
    mutating func mergeCategories(_ incoming: [SavedCategory]) {
        var categories = savedCategories ?? []
        for category in incoming where !categories.contains(where: { $0.id == category.id }) { categories.append(category) }
        if !categories.isEmpty { savedCategories = categories }
    }
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
        for entry in entries {
            if entry.recurringOverride == false { result.remove(entry.id) }
            else if entry.recurringOverride == true { result.insert(entry.id) }
        }
        return result
    }
    static func unusual(_ entry: Entry, in entries: [Entry]) -> Bool {
        guard entry.amount > 0, !entry.reviewed else { return false }
        let peers = entries.filter { $0.id != entry.id && Household.categoryKey($0.categoryName) == Household.categoryKey(entry.categoryName) && $0.amount > 0 }
        guard peers.count >= 3 else { return entry.amount >= 500 }
        let sorted = peers.map(\.amount).sorted()
        return entry.amount > max(150, sorted[sorted.count / 2] * 3)
    }
}


struct SpendingMonth {
    let date: Date
    let calendar: Calendar
    let entries: [Entry]
    init(_ date: Date, entries: [Entry], calendar: Calendar = .current) {
        self.calendar = calendar
        self.date = calendar.dateInterval(of: .month, for: date)!.start
        self.entries = entries.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
    }
    var spending: [Entry] { entries.filter { $0.amount > 0 } }
    var total: Double { spending.reduce(0) { $0 + $1.amount } }
    var moneyReceived: Double { entries.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount } }
    var dayCount: Int { calendar.range(of: .day, in: .month, for: date)!.count }
    func moved(by months: Int) -> Date { calendar.date(byAdding: .month, value: months, to: date)! }
}

// A structured task group would wait for an unresponsive CloudKit child even
// after its timer wins. This gate returns on time and ignores late completions.
@MainActor private final class CloudDeadlineGate<Value> {
    var continuation: CheckedContinuation<Value, Error>?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?
    func finish(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        work?.cancel(); timer?.cancel()
        work = nil; timer = nil
        continuation.resume(with: result)
    }
}
enum CloudTimeout: LocalizedError {
    case expired
    var errorDescription: String? { "iCloud didn’t finish in time. Your saved data is still on this device. Check your connection and try Sync household again." }
}
@MainActor func withCloudDeadline<Value>(seconds: Double, operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
    try Task.checkCancellation()
    let gate = CloudDeadlineGate<Value>()
    return try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { continuation in
            gate.continuation = continuation
            gate.work = Task { @MainActor in
                do { gate.finish(.success(try await operation())) }
                catch { gate.finish(.failure(error)) }
            }
            gate.timer = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    gate.finish(.failure(CloudTimeout.expired))
                } catch { }
            }
        }
    }, onCancel: { Task { @MainActor in gate.finish(.failure(CancellationError())) } })
}
enum CloudPayload {
    static func equivalent(_ lhs: Data, _ rhs: Data) -> Bool {
        guard let left = try? JSONSerialization.jsonObject(with: lhs),
              let right = try? JSONSerialization.jsonObject(with: rhs),
              let a = try? JSONSerialization.data(withJSONObject: left, options: [.sortedKeys]),
              let b = try? JSONSerialization.data(withJSONObject: right, options: [.sortedKeys]) else { return lhs == rhs }
        return a == b
    }
}
