import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAILED: \(name)") }
    checks += 1
    print("PASS: \(name)")
}
let csv = """
Date,Description,Amount
2026-09-01,"Whole Foods, Market",86.42
2026-09-02,Payment received,-150.00
2026-09-03,Netflix,15.49
"""
let parsed = StatementParser.parseText(csv, account: "Test card", year: 2026)
check(parsed.0.count == 3, "CSV header excluded and quoted merchant parsed")
check(parsed.0[0].merchant == "Whole Foods, Market", "Comma preserved in quoted merchant")
check(parsed.0[0].category == .groceries, "Grocery categorization")
check(parsed.0[1].amount == -150 && parsed.0[1].category == .income, "Payment is a credit")
let pdfText = "09/04 WEST ELM $1,249.00\n09/05 REFUND (29.99)\n09/06 PAYMENT 25.00 CR\nNot a transaction"
let pdf = StatementParser.parseText(pdfText, account: "Card", year: 2026)
check(pdf.0.count == 3, "PDF-style transaction lines")
check(pdf.0[0].amount == 1249, "Thousands separator")
check(pdf.0[1].amount == -29.99 && pdf.0[2].amount == -25, "Parentheses and CR credits")
check(StatementParser.date("02/30/2026", year: 2026) == nil, "Invalid calendar date rejected")
check(StatementParser.amount("NaN") == nil, "Invalid amount rejected")
check(StatementParser.parseText("Nothing to parse", account: "Card", year: 2026).0.isEmpty, "No invented transactions")
let a = Entry(date: StatementParser.date("2026-08-03", year: 2026)!, merchant: "Netflix", amount: 15.49, category: .entertainment, account: "Card")
let b = Entry(date: StatementParser.date("2026-09-03", year: 2026)!, merchant: "Netflix", amount: 15.49, category: .entertainment, account: "Card")
check(Insights.recurring([a,b]).count == 2, "Monthly recurrence")
var sameDay = b; sameDay.date = a.date
check(Insights.recurring([a,sameDay]).isEmpty, "Same-day duplicates not recurring")
var outlier = b; outlier.amount = 800
check(Insights.unusual(outlier, in: [a,outlier]), "Large charge flagged with sparse history")
outlier.reviewed = true
check(!Insights.unusual(outlier, in: [a,outlier]), "Reviewed charge dismissed")
let empty = Household()
check(empty.entries.isEmpty && empty.cards.isEmpty && empty.statements.isEmpty, "New household starts empty")
let original = Household(entries: [a,b], cards: [Card(name: "Test card", lastFour: "1234", balance: 100, limit: 1000, due: Date(), minimum: 25)])
let encoded = try JSONEncoder().encode(original)
let decoded = try JSONDecoder().decode(Household.self, from: encoded)
check(decoded.entries.count == original.entries.count && decoded.cards.count == 1, "Persistence round trip")
check(StatementParser.statementBalance("New Balance: $1,248.62") == 1248.62, "Statement balance extracted")
check(StatementParser.statementBalance("Available credit $4,000.00") == nil, "Available credit not confused with debt")
let balanceRows = StatementParser.parseText("09/01 Beginning balance 1,000.00\n09/30 Ending balance 850.00", account: "Checking", year: 2026)
check(balanceRows.0.isEmpty, "Beginning and ending balances never become transactions")
check(!StatementParser.isBalanceSummary("09/02 NEW BALANCE STORE 45.00"), "Merchant containing balance is retained")
let table = StatementParser.parseText("""
Date Description Amount Balance
09/01 Beginning balance 1,000.00
09/02 GROCERY STORE 42.50 957.50
09/03 PAYROLL 200.00 1,157.50
09/30 Ending balance 1,157.50
""", account: "Checking", year: 2026)
check(table.0.count == 2, "Transaction table excludes summary rows")
check(table.0[0].amount == 42.50 && table.0[0].merchant == "GROCERY STORE", "Running balance is not imported as charge")
check(table.0[1].amount == -200, "Reconciled balance increase becomes income")
let posted = StatementParser.parseText("09/04 09/05 WEST ELM 19.99\nSep 6 COFFEE SHOP 5.50", account: "Card", year: 2026)
check(posted.0.count == 2 && posted.0[0].merchant == "WEST ELM", "Transaction and posting dates supported")
check(posted.0[1].date == StatementParser.date("09/06/2026", year: 2026), "Month-name date uses selected statement year")
let fragments: [StatementParser.TextFragment] = [
    .init(text: "19.99", x: 0.8, y: 0.301, height: 0.02),
    .init(text: "COFFEE SHOP", x: 0.3, y: 0.35, height: 0.02),
    .init(text: "09/04", x: 0.1, y: 0.30, height: 0.02),
    .init(text: "WEST ELM", x: 0.3, y: 0.302, height: 0.02),
    .init(text: "5.50", x: 0.8, y: 0.351, height: 0.02),
    .init(text: "09/05", x: 0.1, y: 0.35, height: 0.02)
]
let reconstructed = StatementParser.reconstructedRows(fragments)
let layoutEntries = StatementParser.parseText(reconstructed.joined(separator: "\n"), account: "Card", year: 2026).0
check(layoutEntries.count == 2 && layoutEntries[0].amount == 19.99 && layoutEntries[1].amount == 5.50, "Positioned OCR joins columns without mixing adjacent rows")
check(StatementParser.parseText("09/04 MERCHANT 10.00 500.00", account: "Card", year: 2026).0.isEmpty, "Ambiguous money columns require a balance heading")
let wrapped: [StatementParser.TextFragment] = [
    .init(text: "Date", x: 0.1, y: 0.10, height: 0.02),
    .init(text: "Description", x: 0.3, y: 0.10, height: 0.02),
    .init(text: "Amount", x: 0.8, y: 0.10, height: 0.02),
    .init(text: "09/04", x: 0.1, y: 0.20, height: 0.02),
    .init(text: "Debit", x: 0.3, y: 0.20, height: 0.02),
    .init(text: "19.99", x: 0.8, y: 0.20, height: 0.02),
    .init(text: "WHOLE FOODS MARKET", x: 0.3, y: 0.225, height: 0.02),
    .init(text: "09/05", x: 0.1, y: 0.30, height: 0.02),
    .init(text: "Credit", x: 0.3, y: 0.30, height: 0.02),
    .init(text: "100.00", x: 0.8, y: 0.30, height: 0.02),
    .init(text: "PAYROLL ACME", x: 0.3, y: 0.325, height: 0.02),
    .init(text: "Statement total", x: 0.3, y: 0.35, height: 0.02)
]
let wrappedText = StatementParser.reconstructedRows(wrapped).joined(separator: "\n")
let wrappedEntries = StatementParser.parseText(wrappedText, account: "Checking", year: 2026).0
check(wrappedEntries.count == 2, "Wrapped descriptions do not add transactions")
check(wrappedEntries[0].merchant == "WHOLE FOODS MARKET" && wrappedEntries[0].category == .groceries, "Merchant below Debit row retained and categorized")
check(wrappedEntries[1].merchant == "PAYROLL ACME" && wrappedEntries[1].amount == -100, "Credit details retained with income sign")
check(!wrappedEntries[1].merchant.contains("total"), "Footer is not attached to a merchant")
let genericText = "09/04 Debit 19.99\n09/05 Credit 100.00"
check(StatementParser.preferredText(native: genericText, positioned: wrappedText, account: "Checking", year: 2026) == wrappedText, "Equal row counts prefer recovered merchant descriptions")
check(StatementParser.preferredText(native: wrappedText, positioned: genericText, account: "Checking", year: 2026) == wrappedText, "OCR cannot replace detailed native text with generic types")
var distant = wrapped
// Description too far from the row must not be attached.
distant.removeAll { $0.y > 0.23 }
distant[distant.count - 1].y = 0.28
check(!StatementParser.reconstructedRows(distant)[1].contains("WHOLE FOODS"), "Distant text is not guessed to belong to transaction")
check(StatementParser.isGenericDescription(" Credit ") && !StatementParser.isGenericDescription("Credit Union payment"), "Missing-description warning distinguishes transaction types from names")
let creditUnion = StatementParser.parseText("09/05 Credit Union fee 5.00", account: "Checking", year: 2026).0
check(creditUnion[0].merchant == "Credit Union fee" && creditUnion[0].amount == 5, "Merchant starting with Credit is not mistaken for transaction type")
// Synthetic amounts and names; geometry follows the supplied Amex checking layout.
func amexCell(_ text: String, _ x: Double, _ y: Double, _ width: Double = 0.05) -> StatementParser.TextFragment {
    .init(text: text, x: x, y: y, height: 0.015, width: width)
}
let amexHeader = [amexCell("Date", 0.06, 0.10), amexCell("Description", 0.17, 0.10), amexCell("Credits", 0.55, 0.10), amexCell("Debits", 0.70, 0.10), amexCell("Balance", 0.85, 0.10)]
let amexRows = amexHeader + [
    amexCell("08/01/2026", 0.06, 0.13), amexCell("Beginning Balance", 0.17, 0.13), amexCell("1,000.00", 0.83, 0.13, 0.07),
    amexCell("08/04/2026", 0.06, 0.17), amexCell("Online Transfer: Credit", 0.17, 0.17), amexCell("250.00", 0.55, 0.17), amexCell("1,250.00", 0.83, 0.17, 0.07),
    amexCell("EXAMPLE BANK TRANSFER", 0.17, 0.195), amexCell("External Checking", 0.17, 0.22),
    amexCell("08/08/2026", 0.06, 0.26), amexCell("Debit Card Purchase", 0.17, 0.26), amexCell("-45.00", 0.70, 0.26), amexCell("1,205.00", 0.83, 0.26, 0.07),
    amexCell("EXAMPLE WATER COMPANY", 0.17, 0.285), amexCell("EXAMPLE CITY", 0.17, 0.31), amexCell("ID 123456789", 0.17, 0.335),
    amexCell("Continued on next page", 0.72, 0.37),
    amexCell("Account Details", 0.06, 0.42), amexCell("Contact Us", 0.57, 0.42)
]
let amexText = StatementParser.reconstructedRows(amexRows).joined(separator: "\n")
let amex = StatementParser.parseText(amexText, account: "Checking", year: 2026).0
check(amex.count == 2, "Amex layout excludes beginning balance and footer")
check(amex[0].merchant == "EXAMPLE BANK TRANSFER · External Checking" && amex[0].amount == -250, "Amex credit column uses income sign and full description")
check(amex[1].merchant == "EXAMPLE WATER COMPANY · EXAMPLE CITY · ID 123456789" && amex[1].amount == 45, "Amex debit column preserves all continuation lines and spending sign")
let redacted = amexRows.filter { !["250.00", "-45.00"].contains($0.text) }
check(StatementParser.parseText(StatementParser.reconstructedRows(redacted).joined(separator: "\n"), account: "Checking", year: 2026).0.isEmpty, "Balance column never substitutes for a missing or redacted amount")
let pageTwo = amexHeader + [amexCell("08/10/2026", 0.06, 0.17), amexCell("Online Transfer / Payment: Debit", 0.17, 0.17), amexCell("-80.00", 0.70, 0.17), amexCell("CARD PAYMENT", 0.17, 0.195)]
let pageTwoEntries = StatementParser.parseText(StatementParser.reconstructedRows(pageTwo).joined(separator: "\n"), account: "Checking", year: 2026).0
check(pageTwoEntries.count == 1 && pageTwoEntries[0].merchant == "CARD PAYMENT" && pageTwoEntries[0].amount == 80, "Repeated page headers work without carrying descriptions across pages")
check(StatementParser.preferredText(native: "08/04/2026 Credit 1250.00", positioned: "Date,Description,Amount", account: "Checking", year: 2026) == "Date,Description,Amount", "Recognized table never falls back to a balance-only native row")
check(amex[0].signedAmount == 250 && amex[1].signedAmount == -45, "Amex deposits display positive and withdrawals negative")
var edited = amex[1]
edited.signedAmount = -72.50
check(edited.amount == 72.50 && edited.signedAmount == -72.50, "Editing negative expense preserves spending calculations")
edited.signedAmount = 120
check(edited.amount == -120 && !Insights.unusual(edited, in: [edited]), "Editing positive deposit does not classify it as spending")
check(Category.suggest("SAN JOSE WATER COMPANY") == .utilities && Category.suggest("COMCAST-XFINITY CABLE SVCS") == .utilities && Category.suggest("ELECTRIC BILL") == .utilities, "Utilities suggestions cover water electricity and internet")
edited.category = .other
edited.otherDescription = "Pets"
let customRoundTrip = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(edited))
check(customRoundTrip.categoryName == "Pets" && customRoundTrip.otherDescription == "Pets", "Custom Other label survives disk and cloud encoding")
edited.otherDescription = "   "
check(edited.categoryName == "Other", "Blank custom label falls back to Other")
edited.otherDescription = "Pets"
edited.category = .utilities
check(edited.categoryName == "Utilities", "Custom label is only displayed for Other")
var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as! [String: Any]
legacyJSON.removeValue(forKey: "customCategory")
let legacy = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
check(legacy.customCategory == nil && legacy.amount == edited.amount, "Previously saved transactions load without sign migration")
let delayedCredit = amexHeader + [
    amexCell("08/04/2026", 0.06, 0.17), amexCell("Online Transfer: Credit", 0.17, 0.17),
    amexCell("2,500.00", 0.52, 0.185, 0.08), amexCell("3,500.00", 0.82, 0.185, 0.08),
    amexCell("EXTERNAL ACCOUNT TRANSFER", 0.17, 0.21)
]
let delayedText = StatementParser.reconstructedRows(delayedCredit).joined(separator: "\n")
let delayedEntries = StatementParser.parseText(delayedText, account: "Checking", year: 2026).0
check(delayedEntries.count == 1 && delayedEntries[0].signedAmount == 2500 && delayedEntries[0].merchant == "EXTERNAL ACCOUNT TRANSFER", "Transfer credit below date line is retained with positive display sign")
let wideCredit = amexHeader + [
    amexCell("08/04/2026", 0.06, 0.17), amexCell("Online Transfer: Credit", 0.17, 0.17),
    amexCell("12,500.00", 0.47, 0.17, 0.13), amexCell("13,500.00", 0.81, 0.17, 0.09),
    amexCell("EXTERNAL ACCOUNT TRANSFER", 0.17, 0.195)
]
let wideEntries = StatementParser.parseText(StatementParser.reconstructedRows(wideCredit).joined(separator: "\n"), account: "Checking", year: 2026).0
check(wideEntries.count == 1 && wideEntries[0].signedAmount == 12500, "Wide incoming amount is assigned by right edge to Credits")
let missingThenValid = amexHeader + [
    amexCell("08/04/2026", 0.06, 0.17), amexCell("Online Transfer: Credit", 0.17, 0.17),
    amexCell("08/05/2026", 0.06, 0.195), amexCell("Debit Card Purchase", 0.17, 0.195), amexCell("20.00", 0.70, 0.195)
]
let missingText = StatementParser.reconstructedRows(missingThenValid).joined(separator: "\n")
let missingEntries = StatementParser.parseText(missingText, account: "Checking", year: 2026).0
check(missingText.contains("UNRECOGNIZED_TRANSACTION 08/04/2026") && missingEntries.count == 1 && missingEntries[0].signedAmount == -20, "Missing transfer is flagged without borrowing the next transaction amount")
let conflicting = delayedCredit + [amexCell("10.00", 0.70, 0.185)]
let conflictingText = StatementParser.reconstructedRows(conflicting).joined(separator: "\n")
check(conflictingText.contains("UNRECOGNIZED_TRANSACTION") && StatementParser.parseText(conflictingText, account: "Checking", year: 2026).0.isEmpty, "Multiple debit and credit amounts in one row remain flagged rather than netted")
var categoryHousehold = Household()
let petsName = try categoryHousehold.addCategory("  Pet   care  ")
check(petsName == "Pet care" && categoryHousehold.customCategoryNames == ["Pet care"], "Create reusable category without any transactions")
_ = try categoryHousehold.addCategory("pet care")
check(categoryHousehold.savedCategories?.count == 1, "Duplicate category names are reused case-insensitively")
do { _ = try categoryHousehold.addCategory(" Utilities "); check(false, "Built-in category duplicate must fail") } catch { check(true, "Built-in category duplicate rejected") }
do { _ = try categoryHousehold.addCategory("   "); check(false, "Empty category must fail") } catch { check(true, "Empty category rejected") }
do { _ = try categoryHousehold.addCategory(String(repeating: "a", count: 41)); check(false, "Long category must fail") } catch { check(true, "Long category rejected") }
let savedHousehold = try JSONDecoder().decode(Household.self, from: JSONEncoder().encode(categoryHousehold))
check(savedHousehold.customCategoryNames == ["Pet care"], "Unused categories survive household persistence")
let remoteCategory = SavedCategory(name: "School")
categoryHousehold.mergeCategories([remoteCategory])
categoryHousehold.mergeCategories([remoteCategory])
categoryHousehold.mergeCategories([SavedCategory(name: "PET CARE")])
check(categoryHousehold.savedCategories?.count == 3 && categoryHousehold.customCategoryNames.count == 2, "Category sync merges IDs and collapses concurrent duplicate names in picker")
var oldHouseholdJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(categoryHousehold)) as! [String: Any]
oldHouseholdJSON.removeValue(forKey: "savedCategories")
let oldHousehold = try JSONDecoder().decode(Household.self, from: JSONSerialization.data(withJSONObject: oldHouseholdJSON))
check(oldHousehold.customCategoryNames.isEmpty, "Old household format remains readable")
var oldOther = a; oldOther.category = .other; oldOther.otherDescription = "Hobbies"
check(Household(entries: [oldOther]).customCategoryNames == ["Hobbies"], "Existing Other labels become reusable choices")
let remoteRoundTrip = try JSONDecoder().decode(SavedCategory.self, from: JSONEncoder().encode(remoteCategory))
check(remoteRoundTrip.id == remoteCategory.id && remoteRoundTrip.name == "School", "Cloud category payload preserves name and identity")
var monthCalendar = Calendar(identifier: .gregorian)
monthCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
func monthDate(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
    monthCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}
var januaryExpense = a; januaryExpense.date = monthDate(2026, 1, 15); januaryExpense.amount = 40
var januaryIncome = a; januaryIncome.id = UUID(); januaryIncome.date = monthDate(2026, 1, 20); januaryIncome.amount = -200
var lastYearExpense = a; lastYearExpense.id = UUID(); lastYearExpense.date = monthDate(2025, 1, 15); lastYearExpense.amount = 90
let january = SpendingMonth(monthDate(2026, 1, 31), entries: [januaryExpense, januaryIncome, lastYearExpense], calendar: monthCalendar)
check(january.entries.count == 2 && january.total == 40, "Selected month excludes other years and income from spending")
check(january.moved(by: -1) == monthDate(2025, 12) && january.moved(by: 1) == monthDate(2026, 2), "Month arrows cross year and month-end boundaries correctly")
check(SpendingMonth(monthDate(2024, 2), entries: [], calendar: monthCalendar).dayCount == 29 && SpendingMonth(monthDate(2025, 2), entries: [], calendar: monthCalendar).dayCount == 28, "Daily charts use correct February length")
check(SpendingMonth(monthDate(2026, 3), entries: [januaryExpense], calendar: monthCalendar).total == 0, "Empty selected month has zero spending")
var linkedHousehold = Household()
let sourceOne = UUID(), sourceTwo = UUID(), linkedCard = UUID()
check(linkedHousehold.importEntries([a], statementID: sourceOne, cardID: linkedCard) == 1, "Import attaches statement and stable card ID")
check(linkedHousehold.entries[0].sourceStatementIDs == [sourceOne] && linkedHousehold.entries[0].cardID == linkedCard, "Imported transaction retains provenance")
_ = linkedHousehold.importEntries([a], statementID: sourceTwo, cardID: linkedCard)
check(linkedHousehold.entries.count == 1 && Set(linkedHousehold.entries[0].sourceStatementIDs ?? []) == Set([sourceOne, sourceTwo]), "Reimport links existing activity to both statements without duplicating it")
_ = linkedHousehold.importEntries([a], statementID: sourceTwo, cardID: UUID())
check(linkedHousehold.entries.count == 2, "Identical activity on distinct cards stays separate")
let provenanceRoundTrip = try JSONDecoder().decode(Household.self, from: JSONEncoder().encode(linkedHousehold))
check(provenanceRoundTrip.entries[0].sourceStatementIDs?.count == 2 && provenanceRoundTrip.entries[0].cardID == linkedCard, "Statement and card links survive persistence and cloud encoding")
var legacyEntryJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
legacyEntryJSON.removeValue(forKey: "sourceStatementIDs"); legacyEntryJSON.removeValue(forKey: "cardID")
let unlinkedLegacy = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: legacyEntryJSON))
check(unlinkedLegacy.cardID == nil && unlinkedLegacy.sourceStatementIDs == nil, "Older activity loads without guessed statement or card links")
var excludedRecurring = a; excludedRecurring.recurringOverride = false
let recurringAfterOverride = Insights.recurring([excludedRecurring, b])
check(!recurringAfterOverride.contains(a.id) && recurringAfterOverride.contains(b.id), "Not recurring removes only the selected transaction label")
var manualRecurring = a; manualRecurring.recurringOverride = true
check(Insights.recurring([manualRecurring]).contains(a.id), "Manual recurring works without automatic history")
manualRecurring.recurringOverride = nil
check(!Insights.recurring([manualRecurring]).contains(a.id), "Automatic mode restores detection")
let overrideRoundTrip = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(excludedRecurring))
check(overrideRoundTrip.recurringOverride == false, "Recurring exclusion survives household sync encoding")
check((-2.0).formatted(.number.locale(Locale(identifier: "en_US")).precision(.fractionLength(2))) == "-2.00", "Editable dollar amount retains two decimal places")
var savingsHousehold = Household()
let savingsOne = SavingsAccount(name: "Emergency fund", balance: 2000)
let savingsTwo = SavingsAccount(name: "Vacation", balance: 350.50)
savingsHousehold.mergeSavings([savingsOne, savingsTwo])
check(savingsHousehold.totalSavings == 2350.50, "Savings total combines household accounts")
var newerSavings = savingsOne; newerSavings.balance = 2200; newerSavings.modified = savingsOne.modified.addingTimeInterval(10)
savingsHousehold.mergeSavings([newerSavings, savingsOne])
check(savingsHousehold.totalSavings == 2550.50 && savingsHousehold.savingsAccounts?.count == 2, "Savings sync keeps newer balance without duplicating account")
let savingsRoundTrip = try JSONDecoder().decode(Household.self, from: JSONEncoder().encode(savingsHousehold))
check(savingsRoundTrip.totalSavings == 2550.50, "Savings balances survive persistence")
check(!SavingsAccount(name: "", balance: 2).isValid && !SavingsAccount(name: "Savings", balance: -2).isValid && !SavingsAccount(name: "Savings", balance: .infinity).isValid, "Savings editor rejects invalid names and balances")
check(oldHousehold.totalSavings == 0, "Older household data defaults to empty savings")
check(january.moneyReceived == 200, "Monthly money received excludes spending and other months")
check(Household(entries: [januaryExpense, januaryIncome]).totalMoneyReceived == 200, "All-time money received includes incoming credits only")
var checkingHousehold = Household()
let checkingOne = CheckingAccount(name: "Everyday checking", balance: 1000.25)
let checkingTwo = CheckingAccount(name: "Joint checking", balance: 500)
let overdraft = CheckingAccount(name: "Other checking", balance: -20)
checkingHousehold.mergeChecking([checkingOne, checkingTwo, overdraft])
check(checkingHousehold.positiveCheckingBalance == 1500.25 && checkingHousehold.checkingAccounts?.count == 3, "Positive checking total excludes overdraft while retaining its account")
var updatedChecking = checkingOne; updatedChecking.balance = 1100.25; updatedChecking.modified = checkingOne.modified.addingTimeInterval(10)
checkingHousehold.mergeChecking([updatedChecking, checkingOne])
check(checkingHousehold.positiveCheckingBalance == 1600.25, "Checking sync retains newer balances")
let checkingRoundTrip = try JSONDecoder().decode(Household.self, from: JSONEncoder().encode(checkingHousehold))
check(checkingRoundTrip.positiveCheckingBalance == 1600.25 && checkingRoundTrip.checkingAccounts?.last?.balance == -20, "Checking balances survive persistence including overdrafts")
check(oldHousehold.positiveCheckingBalance == 0, "Older household data defaults to no checking balances")
check(overdraft.isValid && !CheckingAccount(name: " ", balance: 10).isValid && !CheckingAccount(name: "Checking", balance: .nan).isValid, "Checking accepts finite overdrafts and rejects invalid input")
check(CloudPayload.equivalent(Data(#"{"amount":2,"merchant":"Shop"}"#.utf8), Data(#"{"merchant":"Shop","amount":2}"#.utf8)), "Sync ignores JSON key ordering for unchanged records")
check(!CloudPayload.equivalent(Data(#"{"amount":2}"#.utf8), Data(#"{"amount":3}"#.utf8)), "Sync uploads changed payloads")
check(StatementParser.endingBalance("Beginning Balance $500.00\nEnding Balance: $1,234.56") == 1234.56, "Statement ending balance excludes beginning balance")
check(StatementParser.endingBalance("Closing Balance -$25.00") == -25, "Negative checking ending balance supported")
check(StatementParser.endingBalance("Available balance $500.00") == nil, "Available balance is not guessed as statement ending balance")
check(StatementParser.statementDate("Statement Date: 08/31/2026", year: 2026) == StatementParser.date("08/31/2026", year: 2026), "Statement date extracted for chronological updates")
var bankImports = Household()
let bankOne = UUID(), bankTwo = UUID(), savingsID = UUID()
bankImports.applyStatementBalance(kind: .checking, accountID: bankOne, name: "Joint", balance: 100, date: monthDate(2026, 8, 31))
bankImports.applyStatementBalance(kind: .checking, accountID: bankTwo, name: "Personal", balance: 200, date: monthDate(2026, 8, 31))
bankImports.applyStatementBalance(kind: .checking, accountID: bankOne, name: "Joint", balance: 10, date: monthDate(2026, 7, 31))
check(bankImports.positiveCheckingBalance == 300 && bankImports.checkingAccounts?.count == 2, "Statement balances update separate checking accounts and reject older statements")
bankImports.applyStatementBalance(kind: .checking, accountID: bankOne, name: "Joint", balance: 150, date: monthDate(2026, 9, 30))
check(bankImports.positiveCheckingBalance == 350, "Newer statement replaces the selected checking balance")
bankImports.applyStatementBalance(kind: .savings, accountID: savingsID, name: "Savings", balance: 900, date: monthDate(2026, 9, 30))
check(bankImports.totalSavings == 900 && bankImports.positiveCheckingBalance == 350, "Savings statement balance is isolated from checking")
var olderRemoteBank = bankImports.checkingAccounts![0]; olderRemoteBank.balance = 1; olderRemoteBank.balanceDate = monthDate(2026, 1); olderRemoteBank.modified = Date().addingTimeInterval(100)
bankImports.mergeChecking([olderRemoteBank])
check(bankImports.positiveCheckingBalance == 350, "Cloud merge prefers statement chronology over upload time")
var notedStatement = Statement(name: "Statement.pdf", count: 0, data: Data())
notedStatement.notes = "Shared household expenses"; notedStatement.accountKind = .checking; notedStatement.accountID = bankOne
let notedRoundTrip = try JSONDecoder().decode(Statement.self, from: JSONEncoder().encode(notedStatement))
check(notedRoundTrip.notes == notedStatement.notes && notedRoundTrip.accountID == bankOne, "Statement notes and account selection survive storage and sharing")
let detectedAmex = StatementParser.detectAccount("American Express Rewards Checking Statement\nAccount Ending: *4321 Account Name: Rewards Checking\nAccount Activity\nOnline transfer from Bank of America")
check(detectedAmex?.name(for: .checking) == "American Express Checking · 4321", "Account name auto-detected from statement header and masked suffix")
check(StatementParser.detectAccount("Account Activity\nAmerican Express transfer Account Number: 12345678") == nil, "Transfer details never identify the statement account")
check(StatementParser.detectAccount("American Express Statement\nRouting Number: 123456789") == nil, "Routing number is not treated as account number")
check(StatementParser.detectAccount("American Express Statement\nAccount Number: 123456789012")?.lastFour == "9012", "Only last four digits retained in detected account metadata")
var autodetectedHousehold = Household()
let detectedID = UUID()
autodetectedHousehold.applyStatementBalance(kind: .checking, accountID: detectedID, name: detectedAmex!.name(for: .checking), balance: 300, date: monthDate(2026, 8, 31), identity: detectedAmex!.identity(for: .checking))
check(autodetectedHousehold.matchingBankAccount(identity: detectedAmex!.identity(for: .checking), kind: .checking) == detectedID, "Future statements match auto-created account by stable identity")
check(autodetectedHousehold.matchingBankAccount(identity: detectedAmex!.identity(for: .savings), kind: .savings) == nil, "Savings and checking identities remain separate")
let detectedStored = try JSONDecoder().decode(Household.self, from: JSONEncoder().encode(autodetectedHousehold))
check(detectedStored.matchingBankAccount(identity: detectedAmex!.identity(for: .checking), kind: .checking) == detectedID, "Detected account identity survives household sharing")
print("\(checks) checks passed")
