import SwiftUI
import LocalAuthentication
import CloudKit

@MainActor final class Store: ObservableObject {
    @Published var household = Household()
    @Published var unlocked = false
    @Published var error: String?
    @Published var cloudStatus = "Stored on this iPhone"
    @Published var syncing = false
    @Published var familyMembers: [FamilyMember] = []
    @Published var loadingFamily = false
    @Published var familyLoaded = false
    @Published var familyError: String?
    @Published var preparingInvitation = false
    @Published var sharing: CKShare?
    @Published var cloud: CloudService?
    @Published var lockEnabled = UserDefaults.standard.bool(forKey: "lockEnabled")
    private var diskURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("household.json") }
    init() {
        if FileManager.default.fileExists(atPath: diskURL.path) {
            do { household = try JSONDecoder().decode(Household.self, from: Data(contentsOf: diskURL)) }
            catch { self.error = "Saved data could not be opened. \(error.localizedDescription)" }
        }
        unlocked = !lockEnabled
        if Bundle.main.object(forInfoDictionaryKey: "CloudKitEnabled") as? String == "YES" { cloud = CloudService() }
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: diskURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(household)
            try data.write(to: diskURL, options: [.atomic, .completeFileProtection])
        } catch { self.error = "Could not save your changes: \(error.localizedDescription)" }
    }
    func authenticate(enable: Bool = false) async {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your household finances")
            if ok { unlocked = true; if enable { lockEnabled = true; UserDefaults.standard.set(true, forKey: "lockEnabled") } }
        } catch { self.error = error.localizedDescription }
    }
    func add(_ draft: ImportDraft, entries: [Entry], cardBalance: Double? = nil, account: String = "", cardID: UUID? = nil) {
        var statement = Statement(name: draft.name, count: 0, data: draft.data)
        statement.count = household.importEntries(entries, statementID: statement.id, cardID: cardID)
        household.statements.append(statement)
        if let balance = cardBalance, let index = household.cards.firstIndex(where: { $0.id == cardID }) {
            household.cards[index].balance = balance
            household.cards[index].modified = Date()
        }
        save()
    }
    func addCategory(_ name: String) throws -> String {
        let category = try household.addCategory(name)
        save()
        return category
    }
    func sync() async {
        guard let cloud, !syncing else { return }
        syncing = true; defer { syncing = false }
        do {
            var synced = try await cloud.sync(household)
            // Preserve edits or imports made while network requests were in flight.
            for entry in household.entries {
                if let i = synced.entries.firstIndex(where: { $0.id == entry.id }) { if entry.modified > synced.entries[i].modified { synced.entries[i] = entry } }
                else { synced.entries.append(entry) }
            }
            for card in household.cards {
                if let i = synced.cards.firstIndex(where: { $0.id == card.id }) { if card.modified > synced.cards[i].modified { synced.cards[i] = card } }
                else { synced.cards.append(card) }
            }
            for statement in household.statements where !synced.statements.contains(where: { $0.id == statement.id }) { synced.statements.append(statement) }
            synced.mergeCategories(household.savedCategories ?? [])
            synced.mergeSavings(household.savingsAccounts ?? [])
            synced.mergeChecking(household.checkingAccounts ?? [])
            household = synced; save(); cloudStatus = "Synced just now"
        }
        catch { self.error = error.localizedDescription; cloudStatus = "Sync needs attention" }
    }
    func refreshFamilyMembers() async {
        guard !loadingFamily else { return }
        guard let cloud else { familyError = "iCloud sharing isn’t available in this build."; return }
        loadingFamily = true; familyError = nil
        defer { loadingFamily = false }
        do {
            familyMembers = try await cloud.members()
            familyLoaded = true
        } catch {
            familyLoaded = false
            familyMembers = []
            familyError = error.localizedDescription
        }
    }
    func invite() async {
        guard !preparingInvitation, !syncing else { return }
        guard let cloud else { error = "iCloud sharing needs Apple developer setup. Follow README.md to enable it."; return }
        preparingInvitation = true
        defer { preparingInvitation = false }
        do {
            // Establish the private share first. Never upload local records if preparation fails.
            sharing = try await cloud.makeShare()
        } catch { self.error = error.localizedDescription }
    }
    func accept(_ metadata: CKShare.Metadata) async {
        guard let cloud else { error = "Enable CloudKit in the signed app to accept this invitation."; return }
        do {
            try await cloud.accept(metadata)
            await sync()
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor final class CloudService {
    let container = CKContainer(identifier: "iCloud.com.aivxx.togetherbanking.mmp2r7x6fn")
    var database: CKDatabase { participant ? container.sharedCloudDatabase : container.privateCloudDatabase }
    var participant: Bool { UserDefaults.standard.string(forKey: "shareOwner") != nil }
    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: UserDefaults.standard.string(forKey: "shareZone") ?? "Household", ownerName: UserDefaults.standard.string(forKey: "shareOwner") ?? CKCurrentUserDefaultName)
    }
    var rootID: CKRecord.ID { CKRecord.ID(recordName: "household", zoneID: zoneID) }
    func prepare() async throws {
        guard try await container.accountStatus() == .available else { throw CloudError.account }
        if !participant { _ = try await database.save(CKRecordZone(zoneID: zoneID)) }
        do { _ = try await database.record(for: rootID) }
        catch let error as CKError where error.code == .unknownItem {
            guard !participant else { throw error }
            let root = CKRecord(recordType: "Household", recordID: rootID); root["title"] = "Our household"; _ = try await database.save(root)
        }
    }
    func sync(_ local: Household) async throws -> Household {
        try await prepare()
        // Zone changes avoid query indexes and fetch every page. UUID records merge independent edits.
        var records: [CKRecord] = []; var token: CKServerChangeToken?
        var more = true
        while more {
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for modification in result.modificationResultsByID.values { records.append(try modification.get().record) }
            token = result.changeToken; more = result.moreComing
        }
        var merged = local
        let decoder = JSONDecoder()
        for record in records where record.recordType == "HouseholdItem" {
            guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL, let kind = record["kind"] as? String else { continue }
            let data = try Data(contentsOf: url)
            if kind == "entry" {
                let remote = try decoder.decode(Entry.self, from: data)
                if let index = merged.entries.firstIndex(where: { $0.id == remote.id }) { if remote.modified > merged.entries[index].modified { merged.entries[index] = remote } } else { merged.entries.append(remote) }
            } else if kind == "card" {
                let remote = try decoder.decode(Card.self, from: data)
                if let index = merged.cards.firstIndex(where: { $0.id == remote.id }) { if remote.modified > merged.cards[index].modified { merged.cards[index] = remote } } else { merged.cards.append(remote) }
            } else if kind == "checking" {
                merged.mergeChecking([try decoder.decode(CheckingAccount.self, from: data)])
            } else if kind == "savings" {
                merged.mergeSavings([try decoder.decode(SavingsAccount.self, from: data)])
            } else if kind == "category" {
                merged.mergeCategories([try decoder.decode(SavedCategory.self, from: data)])
            } else if kind == "statement" {
                let remote = try decoder.decode(Statement.self, from: data)
                if !merged.statements.contains(where: { $0.id == remote.id }) { merged.statements.append(remote) }
            }
        }
        let encoder = JSONEncoder()
        var items: [(UUID, String, Data)] = []
        for account in merged.checkingAccounts ?? [] { items.append((account.id, "checking", try encoder.encode(account))) }
        for account in merged.savingsAccounts ?? [] { items.append((account.id, "savings", try encoder.encode(account))) }
        for category in merged.savedCategories ?? [] { items.append((category.id, "category", try encoder.encode(category))) }
        for entry in merged.entries { items.append((entry.id, "entry", try encoder.encode(entry))) }
        for card in merged.cards { items.append((card.id, "card", try encoder.encode(card))) }
        for statement in merged.statements { items.append((statement.id, "statement", try encoder.encode(statement))) }
        for (id, kind, data) in items {
            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
            let existing = records.first(where: { $0.recordID == recordID })
            if let asset = existing?["payload"] as? CKAsset, let url = asset.fileURL, (try? Data(contentsOf: url)) == data { continue }
            let record = existing ?? CKRecord(recordType: "HouseholdItem", recordID: recordID)
            record.parent = CKRecord.Reference(recordID: rootID, action: .none)
            record["kind"] = kind
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            defer { try? FileManager.default.removeItem(at: url) }
            record["payload"] = CKAsset(fileURL: url)
            // Server change tags reject concurrent overwrites; a subsequent sync merges newer records.
            _ = try await database.save(record)
        }
        return merged
    }
    func makeShare() async throws -> CKShare {
        try await prepare()
        let root = try await database.record(for: rootID)
        if let reference = root.share { return try await database.record(for: reference.recordID) as! CKShare }
        guard !participant else { throw CloudError.owner }
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Together · Our household"
        share.publicPermission = .none
        let result = try await database.modifyRecords(saving: [root, share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        for record in result.saveResults.values { _ = try record.get() }
        return share
    }
    func accept(_ metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
        UserDefaults.standard.set(metadata.share.recordID.zoneID.ownerName, forKey: "shareOwner")
        UserDefaults.standard.set(metadata.share.recordID.zoneID.zoneName, forKey: "shareZone")
    }
    enum CloudError: LocalizedError {
        case account, owner
        var errorDescription: String? { self == .account ? "Sign in to iCloud in Settings to sync your household." : "Only the household owner can create invitations." }
    }
}

#if DEBUG
// Explicit developer-only integration check. Uses synthetic data, never household documents.
extension Store {
    func verifyCloudSetup() async {
        let resultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("cloudkit-setup-result.txt")
        let result: String
        if let cloud {
            do {
                try await cloud.verifyRoundTrip()
                if ProcessInfo.processInfo.arguments.contains("--verify-family-sharing") {
                    let share = try await cloud.makeShare()
                    guard share.publicPermission == .none else {
                        throw NSError(domain: "TogetherSharing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Household share must be private."])
                    }
                    let members = try await cloud.members()
                    guard members.contains(where: { $0.isCurrentUser && $0.role == "Owner" }) else {
                        throw NSError(domain: "TogetherSharing", code: 3, userInfo: [NSLocalizedDescriptionKey: "The signed-in owner was not found in the household share."])
                    }
                    result = "PASS: private CloudKit share prepared; signed-in owner loaded from participant list; no invitations sent. Synthetic record round-trip and cleanup passed."
                } else {
                    result = "PASS: iCloud account available; private zone and schema created; synthetic record uploaded, downloaded, and deleted."
                }
                cloudStatus = "CloudKit connection verified"
            } catch {
                result = "FAIL: " + error.localizedDescription
                self.error = result
            }
        } else { result = "FAIL: CloudKit is not enabled in this build." }
        do {
            try FileManager.default.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(result.utf8).write(to: resultURL, options: [.atomic, .completeFileProtection])
        } catch { self.error = "Could not save CloudKit setup result: " + error.localizedDescription }
    }
}
extension CloudService {
    func verifyRoundTrip() async throws {
        try await prepare()
        let id = CKRecord.ID(recordName: "setup-check-" + UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "HouseholdItem", recordID: id)
        record.parent = CKRecord.Reference(recordID: rootID, action: .none)
        record["kind"] = "entry"
        let entry = Entry(date: Date(), merchant: "Temporary CloudKit setup check", amount: 0, category: .other, account: "Setup check")
        let data = try JSONEncoder().encode(entry)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: url) }
        record["payload"] = CKAsset(fileURL: url)
        _ = try await database.save(record)
        do {
            let fetched = try await database.record(for: id)
            guard let asset = fetched["payload"] as? CKAsset, let file = asset.fileURL,
                  try Data(contentsOf: file) == data else {
                throw NSError(domain: "TogetherSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "The synthetic record did not round-trip correctly."])
            }
        } catch {
            _ = try? await database.deleteRecord(withID: id)
            throw error
        }
        _ = try await database.deleteRecord(withID: id)
    }
}
#endif

struct FamilyMember: Identifiable {
    let id: String
    let name: String
    let role: String
    let status: String
    let canEdit: Bool
    let isCurrentUser: Bool
    static let owner = FamilyMember(id: "current-owner", name: "You", role: "Owner", status: "Joined", canEdit: true, isCurrentUser: true)
}

extension CloudService {
    func members() async throws -> [FamilyMember] {
        guard try await container.accountStatus() == .available else { throw CloudError.account }
        let root: CKRecord
        do { root = try await database.record(for: rootID) }
        catch let error as CKError where !participant && (error.code == .unknownItem || error.code == .zoneNotFound) {
            return [.owner]
        }
        guard let reference = root.share else { return [.owner] }
        guard let share = try await database.record(for: reference.recordID) as? CKShare else {
            throw NSError(domain: "TogetherSharing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load household members."])
        }
        return share.participants.enumerated().filter { $0.element.acceptanceStatus != .removed }.map { index, person in
            let isYou = person == share.currentUserParticipant
            let isOwner = person.role == .owner
            let displayName = person.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
            let name = isYou ? "You" : (!displayName.isEmpty ? displayName : (isOwner ? "Household owner" : "Family member"))
            let status: String
            switch person.acceptanceStatus {
            case .accepted: status = "Joined"
            case .pending: status = "Invited"
            case .removed: status = "Removed"
            default: status = "Status unavailable"
            }
            return FamilyMember(id: person.userIdentity.userRecordID?.recordName ?? "participant-\(index)", name: name, role: isOwner ? "Owner" : "Member", status: status, canEdit: isOwner || person.permission == .readWrite, isCurrentUser: isYou)
        }.sorted { lhs, rhs in
            if lhs.role != rhs.role { return lhs.role == "Owner" }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
