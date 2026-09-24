import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var picker = false
    @State private var account = "Checking"
    @State private var accountKind: StatementAccountKind = .checking
    @State private var bankSelection = "new"
    @State private var newBankID = UUID()
    @State private var notes = ""
    @State private var balanceDate = Date()
    @State private var selectedCardID: UUID?
    private var bankAccounts: [(UUID, String)] {
        accountKind == .checking ? (store.household.checkingAccounts ?? []).map { ($0.id, $0.name) } : (store.household.savingsAccounts ?? []).map { ($0.id, $0.name) }
    }
    private var bankID: UUID? { accountKind == .creditCard ? nil : UUID(uuidString: bankSelection) ?? newBankID }
    private var suggestedBalance: Double? { accountKind == .creditCard ? draft?.suggestedBalance : draft?.endingBalance }
    private func configureBalance() {
        cardBalance = suggestedBalance ?? 0
        updateBalance = suggestedBalance != nil && (accountKind != .creditCard || selectedCard != nil)
    }
    private var detectedAccountName: String? { draft?.detectedAccount?.name(for: accountKind) }
    private func detectExistingAccount() {
        guard accountKind != .creditCard, bankSelection == "new", let detected = draft?.detectedAccount else { return }
        if let match = store.household.matchingBankAccount(identity: detected.identity(for: accountKind), kind: accountKind) {
            bankSelection = match.uuidString
            account = bankAccounts.first { $0.0 == match }?.1 ?? detected.name(for: accountKind)
        } else { account = detected.name(for: accountKind) }
        for index in entries.indices { entries[index].account = account }
    }
    private var selectedCard: Card? { store.household.cards.first { $0.id == selectedCardID } }
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var draft: ImportDraft?
    @State private var entries: [Entry] = []
    @State private var busy = false
    @State private var error: String?
    @State private var reviewed = false
    @State private var updateBalance = false
    @State private var cardBalance = 0.0
    private var canImport: Bool {
        reviewed && !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!updateBalance || (cardBalance.isFinite && (accountKind == .checking || cardBalance >= 0))) &&
        (accountKind == .creditCard || bankSelection != "new" || (updateBalance && detectedAccountName != nil)) &&
        (!entries.isEmpty || updateBalance) && entries.allSatisfy { $0.amount.isFinite && !$0.merchant.isEmpty }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Picker("Statement type", selection: $accountKind) {
                        ForEach(StatementAccountKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if accountKind == .creditCard {
                        Picker("Attach to card", selection: $selectedCardID) {
                            Text("No credit card").tag(nil as UUID?)
                            ForEach(store.household.cards) { card in Text(card.name + " · " + card.lastFour).tag(Optional(card.id)) }
                        }

                    } else {
                        Picker("Account", selection: $bankSelection) {
                            Text("Add new account").tag("new")
                            ForEach(bankAccounts, id: \.0) { item in Text(item.1).tag(item.0.uuidString) }
                        }
                        if bankSelection == "new" {
                            Text("The account will be detected from your statement and added after you review and import it.")
                                .font(.caption).foregroundStyle(theme.muted)
                            if let name = detectedAccountName {
                                Label(name, systemImage: "building.columns").font(.subheadline)
                            } else if draft != nil {
                                Text("We couldn’t identify the bank and account number. Select an existing account or try a statement that includes its account details.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }.disabled(busy)
                Section("Statement notes") {
                    TextField("Add a note about this statement", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                if let draft {
                    Section {
                        Label(draft.name, systemImage: "doc.text").font(.headline)
                        Text("\(entries.count) transactions found. \(draft.skipped) non-transaction or unrecognized lines skipped. Compare with the original statement; some layouts may be incomplete.").font(.caption).foregroundStyle(theme.muted)
                        if draft.unrecognizedTransactions > 0 {
                            Label("\(draft.unrecognizedTransactions) transaction rows could not be read. This import is incomplete; compare it with the original statement.", systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.orange)
                        }
                        Button("Reverse all amount signs") { for index in entries.indices { entries[index].amount *= -1 } }
                    }
                    Section("Review transactions · swipe to remove") {
                        ForEach($entries) { $entry in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Merchant", text: $entry.merchant).font(.subheadline.bold())
                                if StatementParser.isGenericDescription(entry.merchant) {
                                    Label("Description missing. Check the statement and enter the merchant or payment details.", systemImage: "exclamationmark.triangle")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                                HStack { DatePicker("Date", selection: $entry.date, displayedComponents: .date).labelsHidden(); Spacer(); TextField("Amount", value: $entry.signedAmount, format: .number.precision(.fractionLength(2))).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
                                TransactionCategoryPicker(entry: $entry)
                            }.padding(.vertical, 4)
                        }.onDelete { entries.remove(atOffsets: $0) }
                    }
                    if accountKind != .creditCard || selectedCard != nil {
                        Section {
                            Toggle("Update account balance", isOn: $updateBalance)
                            if updateBalance {
                                TextField("Ending balance ($)", value: $cardBalance, format: .number.precision(.fractionLength(2))).keyboardType(.numbersAndPunctuation)
                                DatePicker("Statement ending date", selection: $balanceDate, displayedComponents: .date)
                            }
                            if suggestedBalance == nil {
                                Text("No ending balance detected. Enter the statement’s ending balance to update this account.").font(.caption).foregroundStyle(theme.muted)
                            }
                        } footer: { Text("Confirm the ending balance and date for \(account). Older bank statements won’t replace a newer balance. A new bank account needs an ending balance.") }
                    }
                    Section { Toggle("I checked these against my statement", isOn: $reviewed) }
                    Section { Button("Import statement · \(entries.count) transactions") { store.add(draft, entries: entries, cardBalance: updateBalance ? cardBalance : nil, account: account, cardID: accountKind == .creditCard ? selectedCardID : nil, accountKind: accountKind, bankAccountID: bankID, balanceDate: balanceDate, notes: notes); dismiss() }.disabled(!canImport) } footer: { Text("Matching transactions already saved for this account are linked to this statement without adding duplicates. The original document is saved with your household. You can also update balances and payment dates in Cards.") }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 12) { Image(systemName: "doc.text.viewfinder").font(.largeTitle).foregroundStyle(theme.accent); Text("Turn statements into clarity.").font(.title2.bold()); Text("PDF, scanned PDF, CSV, or text. Reading and category suggestions happen on this iPhone.").font(.subheadline).foregroundStyle(theme.muted) }.padding(.vertical, 12)
                    }
                    Section {
                        Stepper("Statement year: \(String(year))", value: $year, in: 2000...2100)
                    } header: { Text("Statement details") } footer: { Text("The year is used for dates without a year. For statements spanning December and January, check each date during review.") }
                    Section { Button { picker = true } label: { HStack { Label(busy ? "Reading statement…" : "Choose a document", systemImage: "folder"); if busy { Spacer(); ProgressView() } } }.disabled(busy || account.trimmingCharacters(in: .whitespaces).isEmpty) }
                    Section { Text("CSV format: Date, Description, Amount. Dates: YYYY-MM-DD or MM/DD/YYYY. For CSV source files, positive amounts mean expenses; the review displays expenses as negative. PDF tables and scanned pages are read on this iPhone. Check the detected transactions and amount signs against your statement; some layouts may need correction. Up to 15 MB and the first 50 PDF pages.").font(.caption).foregroundStyle(theme.muted) }
                }
            }.scrollContentBackground(.hidden).background(theme.canvas).navigationTitle(draft == nil ? "Upload statement" : "Review import").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onChange(of: accountKind) { _, kind in
                    selectedCardID = nil; bankSelection = "new"; newBankID = UUID(); account = kind.rawValue
                    configureBalance()
                    detectExistingAccount()
                }
                .onChange(of: bankSelection) { _, selection in
                    account = bankAccounts.first { $0.0.uuidString == selection }?.1 ?? detectedAccountName ?? accountKind.rawValue
                }
                .onChange(of: selectedCardID) { _, _ in
                    if let selectedCard { account = selectedCard.name }
                    configureBalance()
                }
                .onChange(of: account) { _, value in
                    for index in entries.indices { entries[index].account = value }
                }
                .fileImporter(isPresented: $picker, allowedContentTypes: [.pdf, .commaSeparatedText, .plainText]) { result in
                    switch result {
                    case .success(let url):
                        busy = true
                        let selectedAccount = account; let selectedYear = year
                        Task {
                            do {
                                let parsed = try await Task.detached(priority: .userInitiated) { try StatementParser.parse(url: url, account: selectedAccount, year: selectedYear) }.value
                                draft = parsed; entries = parsed.entries
                                balanceDate = parsed.statementDate ?? entries.map(\.date).max() ?? Date()
                                configureBalance()
                                detectExistingAccount()
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    case .failure(let error): self.error = error.localizedDescription
                    }
                }
                .alert("Couldn’t read statement", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}
