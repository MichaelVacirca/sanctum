import Foundation

struct Zone {
    let name: String
    let rect: (x: Float, y: Float, width: Float, height: Float)
    let effectIntensity: Float

    func contains(x: Float, y: Float) -> Bool {
        x >= rect.x && x <= rect.x + rect.width &&
        y >= rect.y && y <= rect.y + rect.height
    }

    static func center(canvasWidth: Float, canvasHeight: Float) -> Zone {
        let w = canvasWidth * 0.5
        let h = canvasHeight * 0.5
        return Zone(
            name: "center",
            rect: (x: canvasWidth * 0.25, y: canvasHeight * 0.25, width: w, height: h),
            effectIntensity: 1.0
        )
    }

    static func allZones(canvasWidth: Float, canvasHeight: Float) -> [Zone] {
        [
            center(canvasWidth: canvasWidth, canvasHeight: canvasHeight),
            Zone(name: "top", rect: (0, 0, canvasWidth, canvasHeight * 0.25), effectIntensity: 0.5),
            Zone(name: "bottom", rect: (0, canvasHeight * 0.75, canvasWidth, canvasHeight * 0.25), effectIntensity: 0.5),
            Zone(name: "left", rect: (0, canvasHeight * 0.25, canvasWidth * 0.25, canvasHeight * 0.5), effectIntensity: 0.6),
            Zone(name: "right", rect: (canvasWidth * 0.75, canvasHeight * 0.25, canvasWidth * 0.25, canvasHeight * 0.5), effectIntensity: 0.6),
        ]
    }
}
