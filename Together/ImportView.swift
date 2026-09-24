import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var picker = false
    @State private var account = "Checking"
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var draft: ImportDraft?
    @State private var entries: [Entry] = []
    @State private var busy = false
    @State private var error: String?
    @State private var reviewed = false
    @State private var updateBalance = false
    @State private var cardBalance = 0.0
    private var canImport: Bool { reviewed && (!updateBalance || (cardBalance.isFinite && cardBalance >= 0)) && !entries.isEmpty && entries.allSatisfy { $0.amount.isFinite && !$0.merchant.isEmpty } }
    var body: some View {
        NavigationStack {
            Form {
                if let draft {
                    Section {
                        Label(draft.name, systemImage: "doc.text").font(.headline)
                        Text("\(entries.count) transactions found. \(draft.skipped) non-transaction or unrecognized lines skipped. Compare with the original statement; some layouts may be incomplete.").font(.caption).foregroundStyle(theme.muted)
                        Button("Reverse all amount signs") { for index in entries.indices { entries[index].amount *= -1 } }
                        Text("Money out is negative. Deposits, refunds, and money received are positive.").font(.caption).foregroundStyle(theme.muted)
                    }
                    Section("Review transactions · swipe to remove") {
                        ForEach($entries) { $entry in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Merchant", text: $entry.merchant).font(.subheadline.bold())
                                if StatementParser.isGenericDescription(entry.merchant) {
                                    Label("Description missing. Check the statement and enter the merchant or payment details.", systemImage: "exclamationmark.triangle")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                                HStack { DatePicker("Date", selection: $entry.date, displayedComponents: .date).labelsHidden(); Spacer(); TextField("Amount", value: $entry.signedAmount, format: .number).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
                                Picker("Category", selection: $entry.category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }.font(.caption)
                                if entry.category == .other {
                                    TextField("Describe Other (e.g. Pets)", text: $entry.otherDescription)
                                        .textInputAutocapitalization(.sentences)
                                }
                            }.padding(.vertical, 4)
                        }.onDelete { entries.remove(atOffsets: $0) }
                    }
                    if store.household.cards.contains(where: { $0.name == account }) {
                        Section {
                            Toggle("Update this card’s statement balance", isOn: $updateBalance)
                            if updateBalance { TextField("Statement balance", value: $cardBalance, format: .number).keyboardType(.decimalPad) }
                        } footer: { Text("Confirm this balance against the statement. It replaces the saved balance for \(account).") }
                    }
                    Section { Toggle("I checked these against my statement", isOn: $reviewed) }
                    Section { Button("Import \(entries.count) transactions") { store.add(draft, entries: entries, cardBalance: updateBalance ? cardBalance : nil, account: account); dismiss() }.disabled(!canImport) } footer: { Text("Matching transactions already saved for this account are skipped. The original document is saved with your household. You can also update balances and payment dates in Cards.") }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 12) { Image(systemName: "doc.text.viewfinder").font(.largeTitle).foregroundStyle(theme.accent); Text("Turn statements into clarity.").font(.title2.bold()); Text("PDF, scanned PDF, CSV, or text. Reading and category suggestions happen on this iPhone.").font(.subheadline).foregroundStyle(theme.muted) }.padding(.vertical, 12)
                    }
                    Section {
                        TextField("Account or card nickname", text: $account)
                        if !store.household.cards.isEmpty { Picker("Use a saved card", selection: $account) { Text("Checking").tag("Checking"); ForEach(store.household.cards) { Text($0.name).tag($0.name) } } }
                        Stepper("Statement year: \(String(year))", value: $year, in: 2000...2100)
                    } header: { Text("Statement details") } footer: { Text("The year is used for dates without a year. For statements spanning December and January, check each date during review.") }
                    Section { Button { picker = true } label: { HStack { Label(busy ? "Reading statement…" : "Choose a document", systemImage: "folder"); if busy { Spacer(); ProgressView() } } }.disabled(busy || account.trimmingCharacters(in: .whitespaces).isEmpty) }
                    Section { Text("CSV format: Date, Description, Amount. Dates: YYYY-MM-DD or MM/DD/YYYY. For CSV source files, positive amounts mean expenses; the review displays expenses as negative. PDF tables and scanned pages are read on this iPhone. Check the detected transactions and amount signs against your statement; some layouts may need correction. Up to 15 MB and the first 50 PDF pages.").font(.caption).foregroundStyle(theme.muted) }
                }
            }.scrollContentBackground(.hidden).background(theme.canvas).navigationTitle(draft == nil ? "Upload statement" : "Review import").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .fileImporter(isPresented: $picker, allowedContentTypes: [.pdf, .commaSeparatedText, .plainText]) { result in
                    switch result {
                    case .success(let url):
                        busy = true
                        let selectedAccount = account; let selectedYear = year
                        Task {
                            do {
                                let parsed = try await Task.detached(priority: .userInitiated) { try StatementParser.parse(url: url, account: selectedAccount, year: selectedYear) }.value
                                draft = parsed; entries = parsed.entries; cardBalance = parsed.suggestedBalance ?? 0; updateBalance = parsed.suggestedBalance != nil && store.household.cards.contains(where: { $0.name == account })
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
