import SwiftUI
import SceneKit

private let bronze = Color(red: 0.72, green: 0.56, blue: 0.30)

struct GameScreen: View {
    @StateObject private var world = GameWorld()
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: GamePanel?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SceneCanvas(world: world).ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        playerHUD
                        Spacer(minLength: 0)
                        if world.targetHP > 0 { targetHUD }
                        Spacer(minLength: 0)
                        radar
                    }
                    Spacer(minLength: 0)
                    Text(world.notice)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.black.opacity(0.65), in: Capsule())
                        .lineLimit(2).allowsHitTesting(false)
                    controls
                    HStack(spacing: 8) {
                        Text("EXP").foregroundColor(bronze)
                        ProgressView(value: Double(world.xp), total: Double(world.level * 100))
                            .tint(bronze)
                        Text("\(world.xp)/\(world.level * 100)").monospacedDigit()
                    }.font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .disabled(panel != nil || world.hp == 0)

                if world.hp == 0 && panel == nil {
                    VStack(spacing: 12) {
                        Text("BẠN ĐÃ GỤC NGÃ").font(.title3.bold()).foregroundColor(bronze)
                        Text("Hồi sinh để trở lại quảng trường.").font(.caption)
                        Button("HỒI SINH") { world.revive() }.buttonStyle(MetalButton())
                    }.padding(24).background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                }
                if let panel = panel {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    panelView(panel)
                        .frame(width: min(520, geometry.size.width - 24), height: max(180, geometry.size.height - 20))
                }
            }
        }
        .onAppear { resumeIfReady() }
        .onDisappear { world.stop() }
        .onChange(of: scenePhase) { _ in resumeIfReady() }
        .onChange(of: panel) { _ in resumeIfReady() }
    }

    private func resumeIfReady() {
        if scenePhase == .active && panel == nil { world.start() } else { world.stop() }
    }

    private var playerHUD: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "shield.lefthalf.filled").foregroundColor(bronze)
                Text("THANH THAN").font(.system(size: 13, weight: .black, design: .serif))
                Spacer()
                Text("Lv.\(world.level)").foregroundColor(bronze)
            }
            meter("HP", value: world.hp, maximum: 100, color: .red)
            meter("MP", value: world.mp, maximum: 100, color: .blue)
            HStack {
                Text("\(world.gold) vàng").foregroundColor(.yellow)
                Spacer()
                Text("OFFLINE").foregroundColor(.white.opacity(0.6))
            }.font(.system(size: 10, weight: .bold))
        }.font(.caption.bold()).padding(9).frame(width: 220).modifier(MetalPanel())
    }

    private var targetHUD: some View {
        VStack(spacing: 4) {
            Text("Assassin · \(world.targetIndex + 1)").font(.caption.bold())
            meter("HP", value: world.targetHP, maximum: world.targetMaxHP, color: .red)
        }.padding(8).frame(width: 170).modifier(MetalPanel()).allowsHitTesting(false)
    }

    private var radar: some View {
        VStack(spacing: 4) {
            Text("KHU LUYỆN TẬP").font(.system(size: 9, weight: .bold)).foregroundColor(bronze)
            Canvas { context, size in
                for line in 1..<4 {
                    let p = CGFloat(line) / 4
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * p, y: 0))
                    path.addLine(to: CGPoint(x: size.width * p, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height * p))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * p))
                    context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 1)
                }
                for point in world.radarPoints {
                    let r: CGFloat = point.isPlayer ? 3.5 : 2.5
                    let x = CGFloat((point.x + 15) / 30) * size.width
                    let y = CGFloat((point.z + 15) / 30) * size.height
                    context.fill(Path(ellipseIn: CGRect(x: x-r, y: y-r, width: r*2, height: r*2)),
                                 with: .color(point.isPlayer ? .cyan : .red))
                }
            }.frame(width: 100, height: 60)
            Text("\(world.nearbyEnemies) quái ở gần").font(.system(size: 9))
        }.padding(7).modifier(MetalPanel()).allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VirtualJoystick { x, z in world.move(x: Float(x), z: Float(z)) }
                .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 6) {
                Button { panel = .inventory } label: { Label("Túi đồ", systemImage: "bag") }
                Button { panel = .help } label: { Label("Hướng dẫn", systemImage: "questionmark.circle") }
            }.font(.system(size: 11, weight: .bold)).buttonStyle(MetalButton())
            Spacer(minLength: 0)
            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    action("MÁU ×\(world.potions)", icon: "cross.vial.fill", color: .red,
                           enabled: world.potions > 0 && world.hp < 100) { world.drinkPotion() }
                    action(world.autoCombat ? "AUTO BẬT" : "AUTO TẮT", icon: "arrow.triangle.2.circlepath",
                           color: world.autoCombat ? .green : bronze) { world.toggleAuto() }
                    action("MỤC TIÊU", icon: "scope", color: bronze) { world.cycleTarget() }
                }
                HStack(spacing: 9) {
                    action(world.skillRemaining > 0 ? String(format: "%.1fs", world.skillRemaining) : "KỸ NĂNG · 22 MP",
                           icon: "bolt.fill", color: .cyan,
                           enabled: world.mp >= 22 && world.skillRemaining == 0, width: 116) { world.castSkill() }
                    action("TẤN CÔNG", icon: "burst.fill", color: .orange, width: 116) { world.normalAttack() }
                }
            }
        }
    }

    private func action(_ title: String, icon: String, color: Color, enabled: Bool = true,
                        width: CGFloat = 75, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundColor(color)
                Text(title).font(.system(size: 9, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(width: width, height: 46)
        }.buttonStyle(MetalButton()).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }

    private func meter(_ label: String, value: Int, maximum: Int, color: Color) -> some View {
        ZStack {
            GeometryReader { proxy in
                Rectangle().fill(color.opacity(0.85))
                    .frame(width: proxy.size.width * min(1, max(0, CGFloat(value) / CGFloat(max(1, maximum)))))
            }
            Text("\(label)  \(value)/\(maximum)").font(.system(size: 10, weight: .bold)).monospacedDigit()
        }.frame(height: 14).background(.black.opacity(0.6))
            .overlay(Rectangle().stroke(bronze.opacity(0.5), lineWidth: 0.5))
    }

    private func panelView(_ panel: GamePanel) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(panel == .inventory ? "TÚI ĐỒ" : "HƯỚNG DẪN").font(.headline).foregroundColor(bronze)
                Spacer()
                Text("Đã tạm dừng").font(.caption).foregroundColor(.secondary)
                Button("Đóng") { self.panel = nil }.buttonStyle(MetalButton())
            }
            ScrollView {
                if panel == .inventory {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Vàng: \(world.gold)   •   Đã hạ: \(world.kills) quái")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(0..<15) { index in
                                ZStack {
                                    Rectangle().fill(.black.opacity(0.7))
                                    if index == 0 {
                                        VStack {
                                            Image(systemName: "cross.vial.fill").foregroundColor(.red)
                                            Text("×\(world.potions)").font(.caption)
                                        }
                                    }
                                }.frame(height: 48).overlay(Rectangle().stroke(bronze.opacity(0.45)))
                            }
                        }
                        Text("Bình máu hồi 45 HP. Dùng bằng nút MÁU khi chiến đấu.").font(.caption)
                        HStack {
                            Image(uiImage: UIImage(named: "gem.png") ?? UIImage())
                                .resizable().interpolation(.none).frame(width: 32, height: 32)
                            Text("Texture mẫu từ PC — chưa phải vật phẩm đã sở hữu.").font(.caption).foregroundColor(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kéo joystick để di chuyển. Nhấn quái trên màn hình hoặc MỤC TIÊU để chọn quái.")
                        Text("TẤN CÔNG đánh mục tiêu trong tầm. KỸ NĂNG tiêu hao 22 MP, hồi chiêu 1,8 giây và đánh tối đa 4 quái.")
                        Text("AUTO tự đánh quái trong tầm, không tự chạy tới quái. Nhấn lần nữa để tắt.")
                        Text("Mở túi đồ hoặc rời ứng dụng sẽ tạm dừng trận đấu.")
                        Text("Bản native offline. Đã nạp mô hình quái GLB từ PC; nhân vật, địa hình và chỉ số chiến đấu còn là mẫu thử. Chưa kết nối máy chủ ThanhThan.")
                            .foregroundColor(bronze)
                    }.font(.callout)
                }
            }
        }.padding(16).background(Color(red: 0.07, green: 0.07, blue: 0.08)).modifier(MetalPanel())
    }
}

private enum GamePanel { case inventory, help }

private struct MetalPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(bronze.opacity(0.7), lineWidth: 1))
    }
}

private struct MetalButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundColor(.white).padding(7)
            .background(LinearGradient(colors: [Color(white: configuration.isPressed ? 0.25 : 0.16), .black],
                                       startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(bronze, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct SceneCanvas: UIViewRepresentable {
    @ObservedObject var world: GameWorld
    func makeCoordinator() -> Coordinator { Coordinator(world: world) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = world.scene
        view.pointOfView = world.camera
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectTarget(_:))))
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) { view.isPlaying = world.isRunning }
    final class Coordinator: NSObject {
        let world: GameWorld
        init(world: GameWorld) { self.world = world }
        @objc func selectTarget(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            for hit in view.hitTest(gesture.location(in: view), options: nil) {
                if world.selectEnemy(node: hit.node) { break }
            }
        }
    }
}

private struct VirtualJoystick: View {
    let onMove: (CGFloat, CGFloat) -> Void
    @State private var delta = CGSize.zero
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    private let radius: CGFloat = 35
    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.55))
            Circle().stroke(bronze.opacity(0.8), lineWidth: 2)
            Circle().stroke(bronze.opacity(0.25)).padding(17)
            Image(systemName: "plus").font(.system(size: 48, weight: .ultraLight)).foregroundColor(bronze.opacity(0.3))
            Circle().fill(LinearGradient(colors: [bronze, Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(bronze)).frame(width: 42, height: 42).offset(delta)
        }.contentShape(Circle())
        .accessibilityLabel("Cần điều khiển di chuyển")
        .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
            let dx = gesture.location.x - 56
            let dy = gesture.location.y - 56
            let scale = min(1, radius / max(1, sqrt(dx * dx + dy * dy)))
            delta = CGSize(width: dx * scale, height: dy * scale)
            onMove(delta.width / radius, delta.height / radius)
        }.onEnded { _ in reset() })
        .onChange(of: isEnabled) { if !$0 { reset() } }
        .onChange(of: scenePhase) { if $0 != .active { reset() } }
        .onDisappear { reset() }
    }
    private func reset() { delta = .zero; onMove(0, 0) }
}
