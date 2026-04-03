import Foundation

struct SanctumConfig: Codable {
    var canvasWidth: Int = 3840
    var canvasHeight: Int = 2160
    var targetFPS: Int = 60
    var corruptionWindowHours: Double = 5.0
    var audioBufferSize: Int = 4096
    var debugOverlay: Bool = true
    var audioSource: String = "line-in" // "line-in" or path to WAV/AIFF file

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
