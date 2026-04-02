import XCTest
@testable import Sanctum

final class SceneGraphTests: XCTestCase {
    func testAddAndRemoveNodes() {
        let graph = SceneGraph()
        let node = SceneNode(id: "panel-1", type: .panel, textureName: "test")
        graph.addNode(node)
        XCTAssertEqual(graph.nodeCount, 1)
        graph.removeNode(id: "panel-1")
        XCTAssertEqual(graph.nodeCount, 0)
    }

    func testNodesOrderedByZIndex() {
        let graph = SceneGraph()
        let back = SceneNode(id: "bg", type: .panel, textureName: "bg", zIndex: 0)
        let front = SceneNode(id: "icon", type: .icon, textureName: "saint", zIndex: 10)
        graph.addNode(front)
        graph.addNode(back)
        let ordered = graph.orderedNodes
        XCTAssertEqual(ordered[0].id, "bg")
        XCTAssertEqual(ordered[1].id, "icon")
    }

    func testNodeTransformUpdate() {
        let graph = SceneGraph()
        var node = SceneNode(id: "p1", type: .panel, textureName: "test")
        node.position = (100, 200)
        node.scale = 1.5
        node.opacity = 0.8
        graph.addNode(node)

        let retrieved = graph.node(id: "p1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.position.x, 100)
        XCTAssertEqual(retrieved?.scale, 1.5)
        XCTAssertEqual(retrieved?.opacity, 0.8)
    }
}
