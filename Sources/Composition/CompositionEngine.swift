import Foundation

final class CompositionEngine {
    let sceneGraph = SceneGraph()
    private let canvasWidth: Float
    private let canvasHeight: Float
    private var panelNames: [String] = []
    private var iconNames: [String] = []

    // Phase-based panel mapping
    private var phasePanels: [String] = []
    private(set) var currentPanelIndex: Int = 0
    private(set) var nextPanelIndex: Int = 0
    private(set) var crossfade: Float = 0.0
    private var lastPhaseIndex: Int = 0

    // Panel names for each corruption phase
    // Sacred (0-0.2) → Awakening (0.2-0.4) → Fracture (0.4-0.6) → Profane (0.6-0.8) → Abyss (0.8-1.0)
    private static let phaseOrder = [
        "panel-sacred-blue",
        "panel-golden-amber",
        "panel-ruby-red",
        "panel-emerald-purple",
        "panel-corrupted",
        "panel-fire"
    ]

    init(canvasWidth: Float = 3840, canvasHeight: Float = 2160) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    func setPanels(_ names: [String]) {
        self.panelNames = names
        // Map phase order to available panels
        phasePanels = Self.phaseOrder.filter { names.contains($0) }
        // If we don't have all phases, pad with whatever we have
        if phasePanels.isEmpty {
            phasePanels = names
        }
        currentPanelIndex = 0
        nextPanelIndex = min(1, phasePanels.count - 1)
    }

    func setIcons(_ names: [String]) {
        self.iconNames = names
        for (i, name) in names.prefix(6).enumerated() {
            let node = SceneNode(
                id: "icon-\(i)", type: .icon, textureName: name,
                position: (
                    Float.random(in: canvasWidth * 0.2...canvasWidth * 0.8),
                    Float.random(in: canvasHeight * 0.2...canvasHeight * 0.8)
                ),
                scale: 0.3, opacity: 0.9, zIndex: 10 + i
            )
            sceneGraph.addNode(node)
        }
    }

    var currentPanelName: String {
        guard !phasePanels.isEmpty else { return "" }
        return phasePanels[currentPanelIndex % phasePanels.count]
    }

    var nextPanelName: String {
        guard !phasePanels.isEmpty else { return "" }
        return phasePanels[nextPanelIndex % phasePanels.count]
    }

    func update(audioState: AudioState, deltaTime: Float) {
        sceneGraph.animate(deltaTime: deltaTime)

        let cw = self.canvasWidth
        let ch = self.canvasHeight

        // Move icons
        for node in sceneGraph.allNodes(ofType: .icon) {
            sceneGraph.updateNode(id: node.id) { n in
                n.position.x += sin(n.position.y * 0.01) * deltaTime * 20
                n.position.y += cos(n.position.x * 0.01) * deltaTime * 10
                if n.position.x < -200 { n.position.x = cw + 100 }
                if n.position.x > cw + 200 { n.position.x = -100 }
                if n.position.y < -200 { n.position.y = ch + 100 }
                if n.position.y > ch + 200 { n.position.y = -100 }
            }
        }

        // Beat pulse on icons
        if audioState.isBeat {
            for node in sceneGraph.allNodes(ofType: .icon) {
                sceneGraph.updateNode(id: node.id) { n in
                    n.scale = 0.4
                    n.targetScale = 0.3
                }
            }
        }

        // Phase-based panel selection
        guard !phasePanels.isEmpty else { return }
        let corruption = audioState.corruptionIndex
        let panelCount = phasePanels.count

        // Map corruption (0-1) to panel index with crossfade
        let scaledPos = corruption * Float(panelCount - 1)
        let phaseIndex = min(Int(scaledPos), panelCount - 1)
        let phaseFraction = scaledPos - Float(phaseIndex)

        currentPanelIndex = phaseIndex
        nextPanelIndex = min(phaseIndex + 1, panelCount - 1)
        crossfade = phaseFraction
    }
}
