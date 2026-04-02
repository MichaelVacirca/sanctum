import Foundation

enum NodeType {
    case panel
    case icon
    case texture
}

struct SceneNode {
    let id: String
    let type: NodeType
    let textureName: String
    var position: (x: Float, y: Float) = (0, 0)
    var scale: Float = 1.0
    var rotation: Float = 0
    var opacity: Float = 1.0
    var zIndex: Int = 0
    var zoneName: String? = nil
    var targetPosition: (x: Float, y: Float)?
    var targetScale: Float?
    var targetOpacity: Float?
}

final class SceneGraph {
    private var nodes: [String: SceneNode] = [:]

    var nodeCount: Int { nodes.count }

    var orderedNodes: [SceneNode] {
        nodes.values.sorted { $0.zIndex < $1.zIndex }
    }

    func addNode(_ node: SceneNode) { nodes[node.id] = node }
    func removeNode(id: String) { nodes.removeValue(forKey: id) }
    func node(id: String) -> SceneNode? { nodes[id] }

    func updateNode(id: String, _ transform: (inout SceneNode) -> Void) {
        guard var node = nodes[id] else { return }
        transform(&node)
        nodes[id] = node
    }

    func animate(deltaTime: Float, speed: Float = 2.0) {
        let t = min(1.0, deltaTime * speed)
        for (id, node) in nodes {
            var n = node
            if let target = n.targetPosition {
                n.position.x += (target.x - n.position.x) * t
                n.position.y += (target.y - n.position.y) * t
            }
            if let target = n.targetScale { n.scale += (target - n.scale) * t }
            if let target = n.targetOpacity { n.opacity += (target - n.opacity) * t }
            nodes[id] = n
        }
    }

    func allNodes(ofType type: NodeType) -> [SceneNode] {
        nodes.values.filter { $0.type == type }
    }
}
