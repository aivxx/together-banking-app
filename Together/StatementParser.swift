import Foundation
#if canImport(UIKit)
import PDFKit
import Vision
import UIKit
#endif

struct ImportDraft {
    var entries: [Entry]
    var name: String
    var data: Data
    var skipped: Int
    var suggestedBalance: Double? = nil
    var unrecognizedTransactions: Int = 0
}
enum ImportError: LocalizedError {
    case unreadable, empty, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: "This document could not be read. Try an unlocked PDF, CSV, or text file."
        case .empty: "No transactions were recognized. Balance summaries are not transactions. Try a CSV with Date, Description, Amount columns, or a PDF that includes transaction details."
        case .tooLarge: "Please choose a statement smaller than 15 MB."
        }
    }
}
enum StatementParser {
    #if canImport(UIKit)
    static func parse(url: URL, account: String, year: Int) throws -> ImportDraft {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 15_000_000 else { throw ImportError.tooLarge }
        var text = ""
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(data: data), !pdf.isLocked else { throw ImportError.unreadable }
            for index in 0..<min(pdf.pageCount, 50) {
                guard let page = pdf.page(at: index) else { continue }
                let extracted = page.string ?? ""
                // PDF text order can be column-first even when its text layer is readable.
                // OCR provides positions so dates, descriptions and amounts stay on one row.
                let image = page.thumbnail(of: CGSize(width: 2200, height: 3000), for: .mediaBox)
                var positioned = ""
                if let cg = image.cgImage {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    do {
                        try VNImageRequestHandler(cgImage: cg).perform([request])
                        let fragments = (request.results ?? []).flatMap { observation -> [TextFragment] in
                            guard let candidate = observation.topCandidates(1).first else { return [] }
                            let value = candidate.string
                            // Word bounds retain empty credit/debit cells even when Vision
                            // recognizes the entire table row as a single text observation.
                            let words = try! NSRegularExpression(pattern: #"\S+"#)
                            return words.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
                                guard let range = Range(match.range, in: value),
                                      let box = try? candidate.boundingBox(for: range) else { return nil }
                                return TextFragment(text: String(value[range]), x: Double(box.boundingBox.minX),
                                                    y: Double(1 - box.boundingBox.midY),
                                                    height: Double(box.boundingBox.height), width: Double(box.boundingBox.width))
                            }
                        }
                        positioned = reconstructedRows(fragments).joined(separator: "\n")
                    } catch {
                        if extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw error }
                    }
                }
                // Prefer recovered descriptions when both representations find the same rows.
                // Choose one representation per page so charges are never duplicated.
                text += preferredText(native: extracted, positioned: positioned, account: account, year: year) + "\n"

            }
        } else { guard let string = String(data: data, encoding: .utf8) else { throw ImportError.unreadable }; text = string }
        let parsed = parseText(text, account: account, year: year)
        guard !parsed.0.isEmpty else { throw ImportError.empty }
        return ImportDraft(entries: parsed.0, name: url.lastPathComponent, data: data, skipped: parsed.1, suggestedBalance: statementBalance(text), unrecognizedTransactions: text.components(separatedBy: "UNRECOGNIZED_TRANSACTION").count - 1)
    }
    #endif
    struct TextFragment {
        var text: String
        var x: Double
        var y: Double
        var height: Double
        var width: Double = 0
    }
    static func reconstructedRows(_ fragments: [TextFragment]) -> [String] {
        var rows: [[TextFragment]] = []
        for fragment in fragments.sorted(by: { $0.y < $1.y }) {
            if let index = rows.lastIndex(where: { row in
                guard let anchor = row.first else { return false }
                return abs(anchor.y - fragment.y) <= min(anchor.height, fragment.height) * 0.45
            }) {
                rows[index].append(fragment)
            } else { rows.append([fragment]) }
        }
        if let table = bankTableRows(rows) { return ["Date,Description,Amount"] + table }
        var output: [String] = []
        var descriptionX: Double?
        var descriptionEnd = 1.0
        var previousY: Double?
        var previousHeight = 0.0
        var activeRow: Int?
        for row in rows {
            let sorted = row.sorted { $0.x < $1.x }
            let line = sorted.map(\.text).joined(separator: "  ")
            let y = row.map(\.y).min() ?? 0
            let height = row.map(\.height).min() ?? 0
            if let header = sorted.firstIndex(where: {
                ["description", "transaction description", "details", "transaction details", "particulars"].contains($0.text.lowercased())
            }) {
                descriptionX = sorted[header].x
                descriptionEnd = header + 1 < sorted.count ? sorted[header + 1].x - 0.015 : 1.0
                activeRow = nil
            }
            let dated = line.range(of: #"^(?:\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?|[A-Za-z]{3,9}\s+\d{1,2})\s"#, options: .regularExpression) != nil
            if dated {
                activeRow = isBalanceSummary(line) ? nil : output.count
            } else if let index = activeRow, let start = descriptionX, let lastY = previousY,
                      y - lastY <= max(height, previousHeight) * 1.8,
                      sorted.allSatisfy({ $0.x >= start - 0.015 && $0.x < descriptionEnd }),
                      isDescriptionContinuation(line),
                      let suffix = output[index].range(of: #"\s+[-+($]*[\d,]+\.\d{2}.*$"#, options: .regularExpression) {
                // Only join nearby text inside the statement's description column.
                // Stop at dates, headings, amounts and page boundaries.
                output[index].insert(contentsOf: "  " + line, at: suffix.lowerBound)
                previousY = y; previousHeight = height
                continue
            } else {
                activeRow = nil
            }
            output.append(line)
            previousY = y; previousHeight = height
        }
        return output
    }
    // Amex checking and similar tables: a blank credit/debit cell is meaningful.
    // Resolve columns before flattening text; the running balance is never an amount.
    static func bankTableRows(_ rows: [[TextFragment]]) -> [String]? {
        var columns: (description: Double, credit: Double, debit: Double, balance: Double)?
        var output: [String] = []
        var pending: (date: String, details: [String], amounts: [(Int, Double)])?
        var lastY: Double?
        var lastHeight = 0.0
        func flush() {
            if let item = pending, item.amounts.count == 1, !item.details.isEmpty {
                let amount = item.amounts[0].0 == 0 ? -abs(item.amounts[0].1) : abs(item.amounts[0].1)
                let details = item.details.count > 1 && isGenericDescription(item.details[0]) ? Array(item.details.dropFirst()) : item.details
                let escaped = details.joined(separator: " · ").replacingOccurrences(of: "\"", with: "'")
                output.append("\(item.date),\"\(escaped)\",\(amount)")
            } else if let item = pending {
                output.append("UNRECOGNIZED_TRANSACTION " + item.date)
            }
            pending = nil
        }
        for rawRow in rows {
            let row = rawRow.sorted { $0.x < $1.x }
            func heading(_ names: [String]) -> TextFragment? { row.first { names.contains($0.text.lowercased()) } }
            if let description = heading(["description"]), let credit = heading(["credits"]),
               let debit = heading(["debits"]), let balance = heading(["balance"]) {
                flush()
                columns = (description.x, credit.x + credit.width, debit.x + debit.width, balance.x + balance.width)
                lastY = nil
                continue
            }
            guard let columns else { continue }
            let y = row.map(\.y).min() ?? 0
            let height = row.map(\.height).max() ?? 0
            let dateCell = row.first { $0.x < columns.description - 0.01 && date($0.text, year: 2000) != nil }
            let descriptionEnd = columns.credit - (columns.debit - columns.credit) * 0.5
            func moneyCell(_ cell: TextFragment) -> (Int, Double)? {
                // Use the right edge: long credit amounts can start left of the
                // description boundary while still ending inside the Credits column.
                let edge = cell.x + cell.width
                guard edge >= descriptionEnd,
                      cell.text.range(of: #"^(?:[-+]?\$?[\d,]+\.\d{2}(?:CR)?|\(\$?[\d,]+\.\d{2}\))$"#, options: [.regularExpression, .caseInsensitive]) != nil,
                      let value = amount(cell.text) else { return nil }
                let edges = [columns.credit, columns.debit, columns.balance]
                let nearest = edges.indices.min { abs(edges[$0] - edge) < abs(edges[$1] - edge) }!
                return (nearest, value)
            }
            let descriptionCells = row.filter {
                $0.x >= columns.description - 0.015 && $0.x < descriptionEnd && moneyCell($0) == nil
            }
            let description = descriptionCells.map(\.text).joined(separator: " ")
            let amounts = row.compactMap(moneyCell).filter { $0.0 != 2 }
            if let dateCell {
                flush()
                if isBalanceSummary(description) { lastY = nil; continue }
                pending = (dateCell.text, description.isEmpty ? [] : [description], amounts)
            } else if pending != nil, let lastY, y - lastY <= max(height, lastHeight) * 2.2,
                      (description.isEmpty || isDescriptionContinuation(description)),
                      row.allSatisfy({ cell in descriptionCells.contains(where: { $0.x == cell.x && $0.text == cell.text }) || moneyCell(cell) != nil }) {
                if !description.isEmpty { pending?.details.append(description) }
                pending?.amounts.append(contentsOf: amounts)
            } else {
                flush()
            }
            lastY = y; lastHeight = height
        }
        flush()
        return columns == nil ? nil : output
    }
    static func isDescriptionContinuation(_ text: String) -> Bool {
        guard text.rangeOfCharacter(from: .letters) != nil,
              text.range(of: #"\d+\.\d{2}"#, options: .regularExpression) == nil else { return false }
        let lower = text.lowercased()
        return !["balance", "total", "page ", "continued", "statement", "customer service", "important", "date", "description", "credit", "debit"].contains(where: { lower == $0 || lower.hasPrefix($0 + " ") })
    }
    static func isGenericDescription(_ text: String) -> Bool {
        ["credit", "debit", "cr", "dr", "debit card purchase", "online transfer: credit", "online transfer / payment: debit"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    static func preferredText(native: String, positioned: String, account: String, year: Int) -> String {
        // A recognized credit/debit table is authoritative even if some rows have
        // missing amounts. Falling back could turn their balances into charges.
        if positioned == "Date,Description,Amount" || positioned.hasPrefix("Date,Description,Amount\n") { return positioned }
        let nativeEntries = parseText(native, account: account, year: year).0
        let positionedEntries = parseText(positioned, account: account, year: year).0
        if positionedEntries.count != nativeEntries.count { return positionedEntries.count > nativeEntries.count ? positioned : native }
        let nativeDetails = nativeEntries.filter { !isGenericDescription($0.merchant) }.count
        let positionedDetails = positionedEntries.filter { !isGenericDescription($0.merchant) }.count
        if positionedDetails != nativeDetails { return positionedDetails > nativeDetails ? positioned : native }
        let sameRows = zip(nativeEntries, positionedEntries).allSatisfy { $0.date == $1.date && abs(abs($0.amount) - abs($1.amount)) < 0.005 }
        if sameRows && positionedEntries.reduce(0, { $0 + $1.merchant.count }) > nativeEntries.reduce(0, { $0 + $1.merchant.count }) { return positioned }
        return native
    }
    static func parseText(_ text: String, account: String, year: Int) -> ([Entry], Int) {
        let lines = text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        var entries: [Entry] = []; var skipped = 0
        let dateToken = #"(?:\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?|[A-Za-z]{3,9}\s+\d{1,2}(?:,?\s+\d{4})?)"#
        let moneyToken = #"(?:[-+]?\$?[\d,]+\.\d{2}(?:\s*CR)?|\(\$?[\d,]+\.\d{2}\))"#
        let regex = try! NSRegularExpression(pattern: "^(" + dateToken + ")\\s+(?:" + dateToken + "\\s+)?(.+?)\\s+(" + moneyToken + "(?:\\s+" + moneyToken + ")*)$", options: .caseInsensitive)
        let moneyRegex = try! NSRegularExpression(pattern: moneyToken, options: .caseInsensitive)
        var runningBalanceColumn = false
        var previousBalance: Double?
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("balance") && ["date", "description", "transaction", "withdrawals"].contains(where: lower.contains) {
                runningBalanceColumn = true
            }
            // A dated balance summary is not a purchase or deposit.
            if isBalanceSummary(line) {
                if let match = moneyRegex.matches(in: line, range: NSRange(line.startIndex..., in: line)).last,
                   let range = Range(match.range, in: line) { previousBalance = amount(String(line[range])) }
                skipped += 1; continue
            }
            var dateText = ""; var merchant = ""; var amountText = ""
            var rowBalance: Double?
            let columns = csv(line)
            if columns.count >= 3, date(columns[0], year: year) != nil {
                dateText = columns[0]; merchant = columns[1]; amountText = columns[2]
            } else if let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                func capture(_ n: Int) -> String { Range(match.range(at: n), in: line).map { String(line[$0]) } ?? "" }
                dateText = capture(1); merchant = capture(2)
                let values = capture(3)
                let amounts = moneyRegex.matches(in: values, range: NSRange(values.startIndex..., in: values)).compactMap {
                    Range($0.range, in: values).map { String(values[$0]) }
                }
                // Without a balance heading, multiple numeric columns are ambiguous.
                guard amounts.count == 1 || (runningBalanceColumn && amounts.count == 2) else { skipped += 1; continue }
                amountText = amounts[0]
                if amounts.count == 2 { rowBalance = amount(amounts[1]) }
            } else { skipped += 1; continue }
            guard let date = date(dateText, year: year), var value = amount(amountText), !merchant.isEmpty else { skipped += 1; continue }
            let type = merchant.split(whereSeparator: { $0.isWhitespace }).first?.lowercased()
            if merchant.range(of: #"^(credit|debit)(?:\s{2,}|$)"#, options: [.regularExpression, .caseInsensitive]) != nil {
                value = type == "credit" ? -abs(value) : abs(value)
                let detail = merchant.dropFirst(type!.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !detail.isEmpty { merchant = detail }
            }
            if let balance = rowBalance {
                if let previous = previousBalance, abs(abs(previous - balance) - abs(value)) < 0.005 {
                    value = previous - balance
                }
                previousBalance = balance
            }
            entries.append(Entry(date: date, merchant: merchant, amount: value, category: value < 0 ? .income : .suggest(merchant), account: account))
        }
        return (entries, skipped)
    }
    static func isBalanceSummary(_ line: String) -> Bool {
        line.range(of: #"^(?:(?:\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?)\s+)?(?:(?:beginning|ending|opening|closing|previous|new|statement|total|available|daily|running)\s+balance|balance\s+(?:forward|brought|carried))(?:\s*:?\s*[-+$\d(]|\s*$)"#,
                   options: .regularExpression.union(.caseInsensitive)) != nil
    }
    static func statementBalance(_ text: String) -> Double? {
        let pattern = #"(?im)(?:new balance|statement balance|total balance)\s*:?\s*\$?([\d,]+\.\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return amount(String(text[range]))
    }
    static func amount(_ value: String) -> Double? {
        let negative = value.contains("(") || value.uppercased().contains("CR")
        let clean = value.replacingOccurrences(of: "[^0-9.+-]", with: "", options: .regularExpression)
        guard let amount = Double(clean), amount.isFinite else { return nil }
        return negative ? -abs(amount) : amount
    }
    static func date(_ value: String, year: Int) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.isLenient = false
        for format in ["yyyy-MM-dd", "M/d/yyyy", "M/d/yy", "MMM d yyyy", "MMM d, yyyy", "MMMM d yyyy", "MMMM d, yyyy"] {
            formatter.dateFormat = format
            if let result = formatter.date(from: value) { return result }
        }
        if value.split(separator: "/").count == 2 { formatter.dateFormat = "M/d/yyyy"; return formatter.date(from: "\(value)/\(year)") }
        for format in ["MMM d yyyy", "MMMM d yyyy"] {
            formatter.dateFormat = format
            if let result = formatter.date(from: "\(value) \(year)") { return result }
        }
        return nil
    }
    static func csv(_ line: String) -> [String] {
        var fields: [String] = []; var current = ""; var quoted = false
        var iterator = line.makeIterator()
        while let char = iterator.next() {
            if char == "\"" { quoted.toggle() }
            else if char == "," && !quoted { fields.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
            else { current.append(char) }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces)); return fields
    }
}
