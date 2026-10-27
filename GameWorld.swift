import Foundation
import SceneKit
import GLTFSceneKit
import SwiftUI

// OFFLINE prototype only. This is not the original PC game client.
// Player and terrain are placeholders; enemies use the converted PC GLB when available.
final class GameWorld: NSObject, ObservableObject {
    // Converted MU monster asset. Kept separate from gameplay/network systems.
    private lazy var assassinTemplate: SCNNode? = {
        guard let url = Bundle.main.url(forResource: "assassin_dier", withExtension: "glb") else {
            print("ThanhThan: assassin_dier.glb missing from app resources")
            return nil
        }
        do {
            let importedScene = try GLTFSceneSource(url: url).scene()
            let root = importedScene.rootNode
            let (minCorner, maxCorner) = root.boundingBox
            let dx = maxCorner.x - minCorner.x
            let dy = maxCorner.y - minCorner.y
            let dz = maxCorner.z - minCorner.z
            let longestSide = max(dx, max(dy, dz))
            if longestSide.isFinite && longestSide > 0.001 {
                let factor: Float = min(2.2 / longestSide, 100.0)
                root.scale = SCNVector3(factor, factor, factor)
                root.position = SCNVector3(
                    -(minCorner.x + maxCorner.x) * factor * 0.5,
                    -minCorner.y * factor,
                    -(minCorner.z + maxCorner.z) * factor * 0.5
                )
            }
            return root
        } catch {
            print("ThanhThan: failed to load GLB: \(error)")
            return nil
        }
    }()

    let scene = SCNScene()
    let camera = SCNNode()
    private let player = SCNNode()
    private var enemies: [Enemy] = []
    private var timer: Timer?
    private var lastTick: Date?
    private var input = SIMD2<Float>(repeating: 0)
    private var clock: TimeInterval = 0
    private var nextAutoStrike: TimeInterval = 0
    private var nextNormalStrike: TimeInterval = 0
    private var nextSkillStrike: TimeInterval = 0
    private var nextManaRegen: TimeInterval = 0
    private var nextHUDUpdate: TimeInterval = 0
    private var selectedEnemy: Enemy?
    @Published private(set) var isRunning = false
    @Published private(set) var skillRemaining: Double = 0
    @Published private(set) var targetHP = 0
    @Published private(set) var targetMaxHP = 1
    @Published private(set) var targetIndex = 0
    @Published private(set) var radarPoints: [RadarPoint] = []

    @Published private(set) var hp = 100
    @Published private(set) var mp = 100
    @Published private(set) var level = 1
    @Published private(set) var xp = 0
    @Published private(set) var gold = 0
    @Published private(set) var kills = 0
    @Published private(set) var potions = 5
    @Published private(set) var nearbyEnemies = 0
    @Published private(set) var autoCombat = false
    @Published private(set) var notice = "Thử cần điều khiển để di chuyển"

    private let worldSize: Float = 15
    private let maxHP = 100
    private let maxMP = 100

    override init() {
        super.init()
        setupScene()
    }

    private func material(_ color: UIColor, roughness: CGFloat = 0.78) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .physicallyBased
        mat.roughness.contents = roughness
        return mat
    }

    private func addShape(_ geometry: SCNGeometry, color: UIColor,
                          at position: SCNVector3, to parent: SCNNode) -> SCNNode {
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry)
        node.position = position
        parent.addChildNode(node)
        return node
    }

    private func setupScene() {
        scene.background.contents = UIColor(red: 0.025, green: 0.038, blue: 0.06, alpha: 1)
        let ground = SCNPlane(width: 32, height: 32)
        let groundMat = material(UIColor(red: 0.16, green: 0.19, blue: 0.18, alpha: 1))
        groundMat.diffuse.contents = UIColor(red: 0.16, green: 0.19, blue: 0.18, alpha: 1)
        ground.materials = [groundMat]
        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles.x = -.pi / 2
        groundNode.position.y = -0.025
        scene.rootNode.addChildNode(groundNode)

        // Grid stones and decorative ruins help visualize the native 3D world.
        for i in -8...8 {
            let p = Float(i) * 2
            addShape(SCNBox(width: 0.035, height: 0.012, length: 32, chamferRadius: 0),
                     color: UIColor(white: 0.35, alpha: 1),
                     at: SCNVector3(p, 0.002, 0), to: scene.rootNode)
            addShape(SCNBox(width: 32, height: 0.012, length: 0.035, chamferRadius: 0),
                     color: UIColor(white: 0.35, alpha: 1),
                     at: SCNVector3(0, 0.002, p), to: scene.rootNode)
        }
        for i in 0..<12 {
            let a = Float(i) * (2 * .pi / 12)
            let radius: Float = i.isMultiple(of: 2) ? 13 : 11
            let x = sin(a) * radius
            let z = cos(a) * radius
            addShape(SCNCylinder(radius: 0.38, height: 2.3),
                     color: UIColor(red: 0.38, green: 0.36, blue: 0.3, alpha: 1),
                     at: SCNVector3(x, 1.15, z), to: scene.rootNode)
            addShape(SCNCone(topRadius: 0, bottomRadius: 0.82, height: 1.8),
                     color: UIColor(red: 0.14, green: 0.32, blue: 0.19, alpha: 1),
                     at: SCNVector3(x, 2.95, z), to: scene.rootNode)
        }

        scene.rootNode.addChildNode(player)
        createPlayer()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 59
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 85
        camera.position = SCNVector3(0, 11, 15)
        let follow = SCNLookAtConstraint(target: player)
        follow.isGimbalLockEnabled = true
        camera.constraints = [follow]
        scene.rootNode.addChildNode(camera)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 600
        ambient.color = UIColor(white: 0.72, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1150
        sun.castsShadow = true
        sun.shadowRadius = 4
        sun.shadowColor = UIColor(white: 0, alpha: 0.28)
        let lightNode = SCNNode()
        lightNode.light = sun
        lightNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(lightNode)

        let spawns: [(Float, Float)] = [(-5,-4), (4,-6), (7,4), (-7,5),
                                        (0,-8), (-9,-2), (8,-8), (2,9)]
        for (index, coord) in spawns.enumerated() {
            createEnemy(index: index, x: coord.0, z: coord.1)
        }
        countNearby()
        updateHUD()
    }

    private func createPlayer() {
        addShape(SCNCapsule(capRadius: 0.42, height: 1.35),
                 color: UIColor(red: 0.19, green: 0.46, blue: 0.76, alpha: 1),
                 at: SCNVector3(0, 1.05, 0), to: player)
        addShape(SCNSphere(radius: 0.36),
                 color: UIColor(red: 0.9, green: 0.73, blue: 0.54, alpha: 1),
                 at: SCNVector3(0, 1.95, 0), to: player)
        addShape(SCNCone(topRadius: 0.18, bottomRadius: 0.52, height: 0.42),
                 color: UIColor(red: 0.15, green: 0.25, blue: 0.47, alpha: 1),
                 at: SCNVector3(0, 2.22, 0), to: player)
        for x: Float in [-0.25, 0.25] {
            addShape(SCNCylinder(radius: 0.17, height: 0.55),
                     color: UIColor(red: 0.12, green: 0.18, blue: 0.28, alpha: 1),
                     at: SCNVector3(x, 0.26, 0), to: player)
        }
        let sword = addShape(SCNBox(width: 0.11, height: 1.45, length: 0.13, chamferRadius: 0.025),
                             color: UIColor(red: 0.75, green: 0.86, blue: 0.92, alpha: 1),
                             at: SCNVector3(0.75, 1.02, 0.05), to: player)
        sword.name = "sword"
        addShape(SCNBox(width: 0.65, height: 0.14, length: 0.18, chamferRadius: 0.02),
                 color: UIColor(red: 0.81, green: 0.65, blue: 0.25, alpha: 1),
                 at: SCNVector3(0.75, 0.52, 0.05), to: player)
        addShape(SCNCylinder(radius: 0.43, height: 0.1),
                 color: UIColor(red: 0.96, green: 0.77, blue: 0.26, alpha: 1),
                 at: SCNVector3(0, 0.02, 0), to: player)
    }

    private func createEnemy(index: Int, x: Float, z: Float) {
        let node = SCNNode()
        node.position = SCNVector3(x, 0, z)

        if let monster = assassinTemplate?.clone() {
            node.addChildNode(monster)
        } else {
            // Visible placeholder only when the real converted asset cannot load.
            let shade = index.isMultiple(of: 2)
                ? UIColor(red: 0.62, green: 0.19, blue: 0.20, alpha: 1)
                : UIColor(red: 0.49, green: 0.27, blue: 0.64, alpha: 1)
            addShape(SCNCapsule(capRadius: 0.51, height: 1.5),
                     color: shade, at: SCNVector3(0, 0.91, 0), to: node)
            addShape(SCNSphere(radius: 0.41), color: shade,
                     at: SCNVector3(0, 1.78, 0), to: node)
        }

        scene.rootNode.addChildNode(node)
        enemies.append(Enemy(node: node, home: SCNVector3(x, 0, z), health: 65 + index * 5))
    }

    private func SCConeCompat(height: CGFloat) -> SCNCone {
        SCNCone(topRadius: 0, bottomRadius: 0.16, height: height)
    }

    func start() {
        guard timer == nil else { return }
        isRunning = true
        lastTick = Date()
        let newTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        lastTick = nil
        input = .zero
    }

    func move(x: Float, z: Float) {
        input = SIMD2<Float>(x, z)
    }

    private func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return sqrt(dx * dx + dz * dz)
    }

    private func tick() {
        let now = Date()
        let dt = min(max(now.timeIntervalSince(lastTick ?? now), 0), 0.06)
        lastTick = now
        guard hp > 0 else { return }
        clock += dt
        if clock >= nextHUDUpdate {
            nextHUDUpdate = clock + 0.1
            updateHUD()
        }

        var direction = input
        let magnitude = sqrt(direction.x * direction.x + direction.y * direction.y)
        if magnitude > 1 { direction /= magnitude }
        if magnitude > 0.045 {
            let speed: Float = 4.7
            player.position.x = max(-worldSize, min(worldSize, player.position.x + direction.x * speed * Float(dt)))
            player.position.z = max(-worldSize, min(worldSize, player.position.z + direction.y * speed * Float(dt)))
            player.eulerAngles.y = atan2(direction.x, direction.y)
        }

        // Smooth camera follow, at a fixed isometric angle.
        let desired = SCNVector3(player.position.x, 11, player.position.z + 15)
        let factor = min(Float(dt) * 5.5, 1)
        camera.position.x += (desired.x - camera.position.x) * factor
        camera.position.y += (desired.y - camera.position.y) * factor
        camera.position.z += (desired.z - camera.position.z) * factor

        for enemy in enemies {
            if !enemy.alive {
                enemy.respawnAfter -= dt
                if enemy.respawnAfter <= 0 {
                    enemy.alive = true
                    enemy.health = enemy.maxHealth
                    enemy.node.position = enemy.home
                    enemy.node.isHidden = false
                }
                continue
            }
            let dist = distance(player.position, enemy.node.position)
            if dist < 6 && dist > 1.5 {
                let dx = player.position.x - enemy.node.position.x
                let dz = player.position.z - enemy.node.position.z
                let step = Float(dt) * 1.15 / max(dist, 0.01)
                enemy.node.position.x += dx * step
                enemy.node.position.z += dz * step
            }
            enemy.attackAfter = max(0, enemy.attackAfter - dt)
            if dist < 1.85 && enemy.attackAfter <= 0 {
                enemy.attackAfter = 2.4
                hp = max(0, hp - 5)
                if hp == 0 {
                    notice = "Nhân vật gục ngã. Nhấn Hồi sinh."
                    autoCombat = false
                    input = .zero
                }
            }
        }
        if clock >= nextManaRegen {
            nextManaRegen = clock + 0.75
            if mp < maxMP { mp += 1 }
        }
        if autoCombat && clock >= nextAutoStrike {
            nextAutoStrike = clock + 0.65
            strike(skill: false, silent: true)
        }
        countNearby()
    }

    private func countNearby() {
        let count = enemies.filter { $0.alive && distance(player.position, $0.node.position) < 7 }.count
        if count != nearbyEnemies { nearbyEnemies = count }
    }

    func normalAttack() { strike(skill: false, silent: false); updateHUD() }
    func castSkill() { strike(skill: true, silent: false); updateHUD() }

    private func strike(skill: Bool, silent: Bool) {
        guard hp > 0 else { return }
        if skill {
            guard clock >= nextSkillStrike else { return }
            guard mp >= 22 else { notice = "Không đủ năng lượng"; return }
        } else {
            guard clock >= nextNormalStrike else { return }
        }
        let maxRange: Float = skill ? 4.4 : 2.7
        var targets = enemies
            .filter { $0.alive && distance(player.position, $0.node.position) <= maxRange }
            .sorted { distance(player.position, $0.node.position) < distance(player.position, $1.node.position) }
        if !skill, let selected = selectedEnemy, selected.alive {
            guard targets.contains(where: { $0 === selected }) else {
                if !silent { notice = "Mục tiêu ngoài tầm đánh" }
                return
            }
            targets = [selected]
        }
        guard !targets.isEmpty else {
            if !silent { notice = "Tiến lại gần quái để tấn công" }
            return
        }
        if let first = targets.first {
            selectedEnemy = first
            player.eulerAngles.y = atan2(first.node.position.x - player.position.x,
                                          first.node.position.z - player.position.z)
        }
        if skill {
            mp -= 22
            nextSkillStrike = clock + 1.8
            createSkillEffect()
        } else {
            nextNormalStrike = clock + 0.48
            let tilt = SCNAction.rotateBy(x: 0, y: 0, z: -.pi / 2.6, duration: 0.12)
            let returnTilt = SCNAction.rotateBy(x: 0, y: 0, z: .pi / 2.6, duration: 0.2)
            player.childNodes.first(where: { $0.name == "sword" })?.runAction(.sequence([tilt, returnTilt]))
        }
        let hits = skill ? Array(targets.prefix(4)) : Array(targets.prefix(1))
        for mob in hits {
            let damage = skill ? 43 + level * 3 : 26 + level * 2
            mob.health -= damage
            showDamage(damage, at: mob.node.position)
            mob.node.runAction(.sequence([.scale(to: 1.16, duration: 0.09), .scale(to: 1, duration: 0.14)]))
            if mob.health <= 0 {
                mob.alive = false
                mob.node.isHidden = true
                mob.respawnAfter = 8
                kills += 1
                gold += 10 + level * 3
                xp += 24
                if xp >= level * 100 {
                    xp -= level * 100
                    level += 1
                    hp = maxHP
                    mp = maxMP
                    notice = "Lên cấp \(level)!"
                } else if !silent {
                    notice = "+24 EXP · +\(10 + level * 3) vàng"
                }
            }
        }
    }

    private func showDamage(_ damage: Int, at position: SCNVector3) {
        let text = SCNText(string: "−\(damage)", extrusionDepth: 0)
        text.font = UIFont.boldSystemFont(ofSize: 1)
        text.firstMaterial?.diffuse.contents = UIColor.yellow
        text.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: text)
        node.scale = SCNVector3(0.6, 0.6, 0.6)
        node.position = SCNVector3(position.x, position.y + 2.5, position.z)
        node.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([.group([.moveBy(x: 0, y: 1.2, z: 0, duration: 0.7),
                                         .fadeOut(duration: 0.7)]), .removeFromParentNode()]))
    }

    @discardableResult
    func selectEnemy(node: SCNNode) -> Bool {
        guard isRunning, hp > 0 else { return false }
        var ancestor: SCNNode? = node
        while let current = ancestor {
            if let enemy = enemies.first(where: { $0.alive && $0.node === current }) {
                selectedEnemy = enemy
                updateHUD()
                return true
            }
            ancestor = current.parent
        }
        return false
    }

    func cycleTarget() {
        let alive = enemies.filter { $0.alive }
        guard !alive.isEmpty else { selectedEnemy = nil; updateHUD(); return }
        if let current = selectedEnemy, let index = alive.firstIndex(where: { $0 === current }) {
            selectedEnemy = alive[(index + 1) % alive.count]
        } else {
            selectedEnemy = alive.min { distance(player.position, $0.node.position) < distance(player.position, $1.node.position) }
        }
        updateHUD()
    }

    private func updateHUD() {
        skillRemaining = max(0, nextSkillStrike - clock)
        if selectedEnemy?.alive == false { selectedEnemy = nil }
        targetHP = max(0, selectedEnemy?.health ?? 0)
        targetMaxHP = selectedEnemy?.maxHealth ?? 1
        targetIndex = enemies.firstIndex(where: { $0 === selectedEnemy }) ?? 0
        radarPoints = [RadarPoint(x: player.position.x, z: player.position.z, isPlayer: true)] +
            enemies.filter { $0.alive }.map { RadarPoint(x: $0.node.position.x, z: $0.node.position.z, isPlayer: false) }
        for enemy in enemies {
            if enemy.node.childNode(withName: "selection-ring", recursively: false) == nil {
                let ring = SCNTorus(ringRadius: 0.8, pipeRadius: 0.04)
                ring.firstMaterial?.diffuse.contents = UIColor.yellow
                ring.firstMaterial?.lightingModel = .constant
                let marker = SCNNode(geometry: ring)
                marker.name = "selection-ring"
                marker.position.y = 0.08
                enemy.node.addChildNode(marker)
            }
            enemy.node.childNode(withName: "selection-ring", recursively: false)?.isHidden = enemy !== selectedEnemy
        }
    }

    private func createSkillEffect() {
        let geo = SCNSphere(radius: 1)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.2, green: 0.72, blue: 1, alpha: 0.28)
        mat.emission.contents = UIColor(red: 0.08, green: 0.35, blue: 0.7, alpha: 1)
        mat.transparency = 0.32
        geo.materials = [mat]
        let blast = SCNNode(geometry: geo)
        blast.position = SCNVector3(player.position.x, 0.8, player.position.z)
        blast.scale = SCNVector3(0.15, 0.15, 0.15)
        scene.rootNode.addChildNode(blast)
        blast.runAction(.sequence([.scale(to: 4.2, duration: 0.32), .removeFromParentNode()]))
    }

    func drinkPotion() {
        guard hp > 0 else { return }
        guard potions > 0 else { notice = "Đã hết bình máu"; return }
        guard hp < maxHP else { notice = "Máu đã đầy"; return }
        potions -= 1
        hp = min(maxHP, hp + 45)
        notice = "Đã dùng bình máu (+45 HP)"
    }

    func toggleAuto() {
        guard hp > 0 else { return }
        autoCombat.toggle()
        notice = autoCombat ? "Tự đánh: BẬT" : "Tự đánh: TẮT"
    }

    func revive() {
        guard hp == 0 else { return }
        hp = maxHP
        mp = maxMP
        input = .zero
        selectedEnemy = nil
        autoCombat = false
        for enemy in enemies {
            enemy.node.position = enemy.home
            enemy.attackAfter = 2.4
        }
        player.position = SCNVector3(0, 0, 0)
        updateHUD()
        notice = "Hồi sinh tại quảng trường"
    }
}

private final class Enemy {
    let node: SCNNode
    let home: SCNVector3
    let maxHealth: Int
    var health: Int
    var alive = true
    var respawnAfter: TimeInterval = 0
    var attackAfter: TimeInterval = 0

    init(node: SCNNode, home: SCNVector3, health: Int) {
        self.node = node
        self.home = home
        self.health = health
        self.maxHealth = health
    }
}

struct RadarPoint {
    let x: Float
    let z: Float
    let isPlayer: Bool
}
