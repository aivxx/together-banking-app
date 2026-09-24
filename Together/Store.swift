import SwiftUI
import LocalAuthentication
import CloudKit

@MainActor final class Store: ObservableObject {
    @Published var household = Household()
    @Published var demo = true
    @Published var unlocked = false
    @Published var error: String?
    @Published var cloudStatus = "Stored on this iPhone"
    @Published var syncing = false
    @Published var sharing: CKShare?
    @Published var cloud: CloudService?
    @Published var lockEnabled = UserDefaults.standard.bool(forKey: "lockEnabled")
    private var diskURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("household.json") }
    init() {
        if FileManager.default.fileExists(atPath: diskURL.path) {
            do { household = try JSONDecoder().decode(Household.self, from: Data(contentsOf: diskURL)); demo = false }
            catch { self.error = "Saved data could not be opened. \(error.localizedDescription)"; demo = false }
        } else { household = .demo }
        unlocked = !lockEnabled
        if Bundle.main.object(forInfoDictionaryKey: "CloudKitEnabled") as? String == "YES" { cloud = CloudService() }
    }
    func save() {
        guard !demo else { return }
        do {
            try FileManager.default.createDirectory(at: diskURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(household)
            try data.write(to: diskURL, options: [.atomic, .completeFileProtection])
        } catch { self.error = "Could not save your changes: \(error.localizedDescription)" }
    }
    func startHousehold() { household = Household(); demo = false; save() }
    func authenticate(enable: Bool = false) async {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your household finances")
            if ok { unlocked = true; if enable { lockEnabled = true; UserDefaults.standard.set(true, forKey: "lockEnabled") } }
        } catch { self.error = error.localizedDescription }
    }
    func add(_ draft: ImportDraft, entries: [Entry], cardBalance: Double? = nil, account: String = "") {
        if demo { startHousehold() }
        let new = entries.filter { entry in !household.entries.contains { $0.date == entry.date && $0.merchant == entry.merchant && $0.amount == entry.amount && $0.account == entry.account } }
        household.entries += new
        household.statements.append(Statement(name: draft.name, count: new.count, data: draft.data))
        if let balance = cardBalance, let index = household.cards.firstIndex(where: { $0.name == account }) {
            household.cards[index].balance = balance
            household.cards[index].modified = Date()
        }
        save()
    }
    func sync() async {
        guard let cloud, !demo, !syncing else { return }
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
            household = synced; save(); cloudStatus = "Synced just now"
        }
        catch { self.error = error.localizedDescription; cloudStatus = "Sync needs attention" }
    }
    func invite() async {
        guard let cloud else { error = "iCloud sharing needs Apple developer setup. Follow README.md in the Xcode project to enable CloudKit for both phones."; return }
        if demo { error = "Start your household before inviting your partner."; return }
        await sync()
        do { sharing = try await cloud.makeShare() } catch { self.error = error.localizedDescription }
    }
    func accept(_ metadata: CKShare.Metadata) async {
        guard let cloud else { error = "Enable CloudKit in the signed app to accept this invitation."; return }
        do {
            try await cloud.accept(metadata)
            if demo { startHousehold() }
            await sync()
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor final class CloudService {
    let container = CKContainer(identifier: "iCloud.com.together.household")
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
            } else if kind == "statement" {
                let remote = try decoder.decode(Statement.self, from: data)
                if !merged.statements.contains(where: { $0.id == remote.id }) { merged.statements.append(remote) }
            }
        }
        let encoder = JSONEncoder()
        var items: [(UUID, String, Data)] = []
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
