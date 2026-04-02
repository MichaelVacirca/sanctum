import Foundation

final class CompositionEngine {
    let sceneGraph = SceneGraph()
    private let zones: [Zone]
    private let canvasWidth: Float
    private let canvasHeight: Float
    private var panelNames: [String] = []
    private var iconNames: [String] = []
    private var activePanelIndices: [Int] = []
    private var lastTransitionEnergy: Float = 0

    init(canvasWidth: Float = 3840, canvasHeight: Float = 2160) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.zones = Zone.allZones(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    }

    func setPanels(_ names: [String]) {
        self.panelNames = names
        let initialPanels = Array(names.prefix(4))
        for (i, name) in initialPanels.enumerated() {
            let col = Float(i % 2)
            let row = Float(i / 2)
            let node = SceneNode(
                id: "panel-\(i)", type: .panel, textureName: name,
                position: (col * canvasWidth / 2, row * canvasHeight / 2),
                scale: 1.0, opacity: 1.0, zIndex: 0
            )
            sceneGraph.addNode(node)
            activePanelIndices.append(i)
        }
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

    func update(audioState: AudioState, deltaTime: Float) {
        sceneGraph.animate(deltaTime: deltaTime)

        let cw = self.canvasWidth
        let ch = self.canvasHeight

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

        let energyDelta = abs(audioState.overallEnergy - lastTransitionEnergy)
        if energyDelta > 0.3 && panelNames.count > 4 {
            let slotIndex = Int.random(in: 0..<4)
            sceneGraph.updateNode(id: "panel-\(slotIndex)") { n in
                n.targetOpacity = 0
            }
            lastTransitionEnergy = audioState.overallEnergy
        }

        if audioState.isBeat {
            for node in sceneGraph.allNodes(ofType: .icon) {
                sceneGraph.updateNode(id: node.id) { n in
                    n.scale = 0.35
                    n.targetScale = 0.3
                }
            }
        }
    }
}
