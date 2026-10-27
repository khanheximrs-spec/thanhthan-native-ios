import XCTest
import SceneKit
@testable import ThanhThanNative

final class GameWorldTests: XCTestCase {
    func testSelectingEnemyUpdatesTargetAndSkillCooldown() throws {
        let world = GameWorld()
        world.start()
        defer { world.stop() }
        let enemy = try XCTUnwrap(world.scene.rootNode.childNodes.first { world.selectEnemy(node: $0) })
        enemy.position = SCNVector3(1.5, 0, 0)
        world.castSkill()
        XCTAssertEqual(world.mp, 78)
        XCTAssertGreaterThan(world.skillRemaining, 0)
        XCTAssertEqual(world.targetHP, 19) // 65 HP minus 43 + level * 3.
        world.castSkill()
        XCTAssertEqual(world.mp, 78, "Cooldown must prevent a second charge")
        XCTAssertEqual(world.targetHP, 19)
    }

    func testOutOfRangeTargetDoesNotTakeDamage() throws {
        let world = GameWorld()
        world.start()
        defer { world.stop() }
        let enemy = try XCTUnwrap(world.scene.rootNode.childNodes.first { world.selectEnemy(node: $0) })
        enemy.position = SCNVector3(14, 0, 14)
        let health = world.targetHP
        world.normalAttack()
        XCTAssertEqual(world.targetHP, health)
        XCTAssertEqual(world.notice, "Mục tiêu ngoài tầm đánh")
    }

    func testFullHealthDoesNotConsumePotion() {
        let world = GameWorld()
        world.drinkPotion()
        XCTAssertEqual(world.potions, 5)
        XCTAssertEqual(world.hp, 100)
    }

    func testStopDisablesSelectionAndPreservesRadar() {
        let world = GameWorld()
        world.start()
        world.stop()
        XCTAssertFalse(world.isRunning)
        XCTAssertFalse(world.scene.rootNode.childNodes.contains { world.selectEnemy(node: $0) })
        XCTAssertEqual(world.radarPoints.count, 9)
        XCTAssertEqual(world.radarPoints.filter { $0.isPlayer }.count, 1)
    }
}
