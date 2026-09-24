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
let original = Household.demo
let encoded = try JSONEncoder().encode(original)
let decoded = try JSONDecoder().decode(Household.self, from: encoded)
check(decoded.entries.count == original.entries.count && decoded.cards.count == 2, "Persistence round trip")
check(StatementParser.statementBalance("New Balance: $1,248.62") == 1248.62, "Statement balance extracted")
check(StatementParser.statementBalance("Available credit $4,000.00") == nil, "Available credit not confused with debt")
print("\(checks) checks passed")
