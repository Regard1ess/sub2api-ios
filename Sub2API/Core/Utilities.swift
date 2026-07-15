import Foundation

enum AppFormatters {
    static func compactNumber(_ value: Double?) -> String {
        guard let value else { return "--" }
        let absValue = abs(value)
        if absValue >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    static func compactNumber(_ value: Int?) -> String {
        compactNumber(value.map(Double.init))
    }

    static func money(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "$%.2f", value)
    }

    static func dateTime(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "--" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) ?? fallbackFormatter.date(from: value) else {
            return value
        }
        return date.formatted(date: .numeric, time: .shortened)
    }
}

extension Error {
    var isRequestCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    var userFacingMessage: String? {
        if isRequestCancellation {
            return nil
        }

        let message = localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = message.lowercased()
        return ["cancelled", "canceled", "已取消"].contains(normalized) ? nil : message
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum FormParser {
    static func parseFlatJSONObject(_ raw: String, fieldName: String) throws -> [String: JSONValue]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8) else {
            throw APIError.requestFailed("\(fieldName) 必须是 JSON 对象。")
        }

        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let object = decoded as? [String: Any] else {
            throw APIError.requestFailed("\(fieldName) 必须是 JSON 对象。")
        }

        var result: [String: JSONValue] = [:]
        for (key, value) in object {
            switch value {
            case is NSNull:
                result[key] = .null
            case let bool as Bool:
                result[key] = .bool(bool)
            case let number as NSNumber:
                result[key] = .number(number.doubleValue)
            case let string as String:
                result[key] = .string(string)
            default:
                throw APIError.requestFailed("\(fieldName) 仅支持 string / number / boolean / null。")
            }
        }
        return result
    }
}

enum RangeKey: String, CaseIterable, Identifiable {
    case day = "24h"
    case week = "7d"
    case month = "30d"

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var granularity: String { self == .day ? "hour" : "day" }

    func dateRange(now: Date = Date()) -> DateRange {
        let calendar = Calendar.current
        let start: Date
        switch self {
        case .day:
            start = calendar.date(byAdding: .hour, value: -23, to: now) ?? now
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        case .month:
            start = calendar.date(byAdding: .day, value: -29, to: now) ?? now
        }
        return DateRange(start: start, end: now, granularity: granularity)
    }
}

struct DateRange {
    let start: Date
    let end: Date
    let granularity: String

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var startDate: String { Self.dayFormatter.string(from: start) }
    var endDate: String { Self.dayFormatter.string(from: end) }
}
