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
print("\(checks) checks passed")
