import Foundation

struct GridConfig: Codable {
    let columns: Int
    let rows: Int
    let displays: [DisplaySlot]

    struct DisplaySlot: Codable {
        let column: Int
        let row: Int
        let displayID: UInt32?
    }

    static let defaultConfig = GridConfig(
        columns: 2, rows: 2,
        displays: [
            DisplaySlot(column: 0, row: 0, displayID: nil),
            DisplaySlot(column: 1, row: 0, displayID: nil),
            DisplaySlot(column: 0, row: 1, displayID: nil),
            DisplaySlot(column: 1, row: 1, displayID: nil),
        ]
    )

    static func load(from url: URL) throws -> GridConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GridConfig.self, from: data)
    }
}
