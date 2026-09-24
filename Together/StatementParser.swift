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
}
enum ImportError: LocalizedError {
    case unreadable, empty, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: "This document could not be read. Try an unlocked PDF, CSV, or text file."
        case .empty: "No transactions were recognized. Use a CSV with Date, Description, Amount columns, or a statement with a date and amount on each transaction line."
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
                if let extracted = page.string, extracted.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 { text += extracted + "\n" }
                else {
                    let image = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
                    guard let cg = image.cgImage else { continue }
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    try VNImageRequestHandler(cgImage: cg).perform([request])
                    text += (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") + "\n"
                }
            }
        } else { guard let string = String(data: data, encoding: .utf8) else { throw ImportError.unreadable }; text = string }
        let parsed = parseText(text, account: account, year: year)
        guard !parsed.0.isEmpty else { throw ImportError.empty }
        return ImportDraft(entries: parsed.0, name: url.lastPathComponent, data: data, skipped: parsed.1, suggestedBalance: statementBalance(text))
    }
    #endif
    static func parseText(_ text: String, account: String, year: Int) -> ([Entry], Int) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var entries: [Entry] = []; var skipped = 0
        let datePattern = #"^(\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?)\s+(.+?)\s+([-+]?\$?[\d,]+\.\d{2}\s*(?:CR)?|\([\$\d,]+\.\d{2}\))\s*$"#
        let regex = try! NSRegularExpression(pattern: datePattern, options: .caseInsensitive)
        for line in lines {
            var dateText = ""; var merchant = ""; var amountText = ""
            let columns = csv(line)
            if columns.count >= 3, date(columns[0], year: year) != nil {
                dateText = columns[0]; merchant = columns[1]; amountText = columns[2]
            } else if let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                func capture(_ n: Int) -> String { Range(match.range(at: n), in: line).map { String(line[$0]) } ?? "" }
                dateText = capture(1); merchant = capture(2); amountText = capture(3)
            } else { skipped += 1; continue }
            guard let date = date(dateText, year: year), let amount = amount(amountText), !merchant.isEmpty else { skipped += 1; continue }
            entries.append(Entry(date: date, merchant: merchant, amount: amount, category: amount < 0 ? .income : .suggest(merchant), account: account))
        }
        return (entries, skipped)
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
        for format in ["yyyy-MM-dd", "M/d/yyyy", "M/d/yy"] {
            formatter.dateFormat = format
            if let result = formatter.date(from: value) { return result }
        }
        if value.split(separator: "/").count == 2 { formatter.dateFormat = "M/d/yyyy"; return formatter.date(from: "\(value)/\(year)") }
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
