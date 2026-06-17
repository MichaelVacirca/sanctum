import Foundation

struct SanctumConfig: Codable {
    var canvasWidth: Int = 3840
    var canvasHeight: Int = 2160
    var targetFPS: Int = 60
    var corruptionWindowHours: Double = 5.0
    var audioBufferSize: Int = 4096
    var debugOverlay: Bool = true
    var audioSource: String = "line-in" // "line-in" or path to WAV/AIFF file
    var theme: String = "cathedral" // visual theme id: "cathedral" or "beach"

    init() {}

    // Decode every key as optional, falling back to the property default when a
    // key is absent. This keeps hand-edited config files forward/backward
    // compatible — adding a single key (e.g. `theme`) never invalidates the
    // rest of the file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SanctumConfig()
        canvasWidth = try c.decodeIfPresent(Int.self, forKey: .canvasWidth) ?? d.canvasWidth
        canvasHeight = try c.decodeIfPresent(Int.self, forKey: .canvasHeight) ?? d.canvasHeight
        targetFPS = try c.decodeIfPresent(Int.self, forKey: .targetFPS) ?? d.targetFPS
        corruptionWindowHours = try c.decodeIfPresent(Double.self, forKey: .corruptionWindowHours) ?? d.corruptionWindowHours
        audioBufferSize = try c.decodeIfPresent(Int.self, forKey: .audioBufferSize) ?? d.audioBufferSize
        debugOverlay = try c.decodeIfPresent(Bool.self, forKey: .debugOverlay) ?? d.debugOverlay
        audioSource = try c.decodeIfPresent(String.self, forKey: .audioSource) ?? d.audioSource
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? d.theme
    }

    static func load() -> SanctumConfig {
        let configURL = Bundle.main.url(forResource: "sanctum-config", withExtension: "json")
            ?? URL(fileURLWithPath: "sanctum-config.json")

        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(SanctumConfig.self, from: data) else {
            return SanctumConfig()
        }
        return config
    }
}
