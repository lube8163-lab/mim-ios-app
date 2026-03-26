import Foundation

enum ServerDate {
    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let sqliteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func decodeDate<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Date {
        if let seconds = try? container.decode(Double.self, forKey: key) {
            return seconds > 10_000_000_000
                ? Date(timeIntervalSince1970: seconds / 1000)
                : Date(timeIntervalSince1970: seconds)
        }

        if let string = try? container.decode(String.self, forKey: key),
           let parsed = parse(string: string) {
            return parsed
        }

        return Date()
    }

    static func parse(string: String) -> Date? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if let iso8601Date = iso8601FractionalFormatter.date(from: normalized) {
            return iso8601Date
        }

        if let iso8601Date = iso8601Formatter.date(from: normalized) {
            return iso8601Date
        }

        if let sqliteDate = sqliteFormatter.date(from: normalized) {
            return sqliteDate
        }

        return nil
    }

    static func relativeString(
        from date: Date,
        relativeTo referenceDate: Date = Date(),
        languageCode: String
    ) -> String {
        let clampedDate: Date
        let offset = date.timeIntervalSince(referenceDate)
        if offset > 0, offset < 300 {
            clampedDate = referenceDate
        } else {
            clampedDate = date
        }

        if abs(clampedDate.timeIntervalSince(referenceDate)) < 5 {
            return localizedText(
                languageCode: languageCode,
                ja: "たった今",
                en: "just now",
                zh: "刚刚"
            )
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: languageCode)
        return formatter.localizedString(for: clampedDate, relativeTo: referenceDate)
    }
}
