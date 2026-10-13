// Festivals: on the day, the buddy dresses up and says hello. Add your own
// (birthdays, team days, other festivals) with "festivals" in the config.
import Foundation

/// What the buddy wears or brings out.
enum Costume: String, Codable, CaseIterable {
    case partyHat, santaHat, witchHat, diya, holi, flag
}

struct Festival: Codable, Equatable {
    var date: String        // "MM-dd" every year, or "yyyy-MM-dd" for one year only
    var name: String
    var greeting: String?
    var costume: Costume?
    var days: Int?          // how many days it lasts (default 1)

    static let builtIn: [Festival] = [
        Festival(date: "12-31", name: "New Year", greeting: "🎉 Happy New Year!", costume: .partyHat, days: 2),
        Festival(date: "01-26", name: "Republic Day", greeting: "🇮🇳 Happy Republic Day!", costume: .flag),
        Festival(date: "08-15", name: "Independence Day", greeting: "🇮🇳 Happy Independence Day!", costume: .flag),
        Festival(date: "10-31", name: "Halloween", greeting: "🎃 Happy Halloween!", costume: .witchHat),
        Festival(date: "12-24", name: "Christmas", greeting: "🎄 Merry Christmas!", costume: .santaHat, days: 3),
    ]
    // Holi and Diwali follow the lunar calendar.
    + ["2026-03-04", "2027-03-22", "2028-03-11", "2029-03-01", "2030-03-20"].map {
        Festival(date: $0, name: "Holi", greeting: "🌈 Happy Holi!", costume: .holi)
    }
    + ["2026-11-08", "2027-10-29", "2028-10-17", "2029-11-05", "2030-10-26"].map {
        Festival(date: $0, name: "Diwali", greeting: "🪔 Happy Diwali!", costume: .diya, days: 2)
    }

    /// True if `date` falls within this festival.
    func covers(_ date: Date) -> Bool {
        let f = DateFormatter()
        let cal = Calendar.current
        for back in 0..<max(1, days ?? 1) {
            guard let d = cal.date(byAdding: .day, value: -back, to: date) else { continue }
            f.dateFormat = self.date.count == 5 ? "MM-dd" : "yyyy-MM-dd"
            if f.string(from: d) == self.date { return true }
        }
        return false
    }

    /// Today's festival, if any: yours from the config first, then the built-in ones.
    static func on(_ date: Date, extra: [Festival]) -> Festival? {
        (extra + builtIn).first { $0.covers(date) }
    }
}
