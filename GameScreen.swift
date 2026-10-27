import SwiftUI
import SceneKit

struct GameScreen: View {
    @StateObject private var world = GameWorld()
    @State private var showingHelp = false
    @State private var showingInventory = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SceneCanvas(world: world)
                    .ignoresSafeArea()

                LinearGradient(colors: [Color.black.opacity(0.72), .clear, .clear, .black.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topHud
                    HStack {
                        Spacer()
                        VStack(spacing: 9) {
                            Button { showingHelp = true } label: {
                                Label("HƯỚNG DẪN", systemImage: "questionmark.circle")
                            }
                            Button { showingInventory = true } label: {
                                Label("TÚI ĐỒ", systemImage: "bag")
                            }
                        }
                        .font(.caption2.bold())
                        .buttonStyle(HudButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer(minLength: 10)
                    if world.hp == 0 {
                        Button("HỒI SINH") { world.revive() }
                            .font(.headline.bold())
                            .buttonStyle(ActionButtonStyle(color: Color(red: 0.95, green: 0.5, blue: 0.14)))
                            .padding(.bottom, 16)
                    }
                    Text(world.notice)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.53), in: Capsule())
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 13)
                    bottomControls
                }
                .padding(.top, max(12, geometry.safeAreaInsets.top))
                .padding(.bottom, max(12, geometry.safeAreaInsets.bottom))
            }
        }
        .onAppear { world.start() }
        .onDisappear { world.stop() }
        .sheet(isPresented: $showingHelp) { helpSheet }
        .sheet(isPresented: $showingInventory) { inventorySheet }
    }

    private var topHud: some View {
        VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THANH THAN")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                    Text("NATIVE iOS · DEMO OFFLINE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Text("LV \(world.level)")
                    .font(.subheadline.bold())
                    .foregroundColor(.yellow)
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
                Text("Chưa kết nối server")
                    .font(.system(size: 10, weight: .medium))
            }
            HStack(spacing: 10) {
                StatBar(symbol: "heart.fill", value: world.hp, maxValue: 100,
                        fill: Color.red, label: "HP")
                StatBar(symbol: "sparkles", value: world.mp, maxValue: 100,
                        fill: Color.cyan, label: "MP")
            }
            HStack(spacing: 10) {
                Label("\(world.gold) vàng", systemImage: "circle.hexagongrid.fill")
                Label("\(world.kills) quái", systemImage: "shield.lefthalf.filled")
                Label("\(world.nearbyEnemies) gần", systemImage: "scope")
                Spacer()
                Text("EXP \(world.xp)/\(world.level * 100)")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.95))
        }
        .padding(12)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
        .padding(.horizontal, 12)
    }

    private var bottomControls: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(spacing: 4) {
                VirtualJoystick { x, z in world.move(x: Float(x), z: Float(z)) }
                Text("DI CHUYỂN")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.82))
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 9) {
                    Button { world.drinkPotion() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "cross.vial.fill")
                            Text("MÁU \(world.potions)")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .frame(width: 67, height: 63)
                    }
                    .buttonStyle(ActionButtonStyle(color: .pink))
                    Button { world.toggleAuto() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: world.autoCombat ? "pause.circle.fill" : "arrow.triangle.2.circlepath")
                            Text(world.autoCombat ? "AUTO ON" : "AUTO OFF")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .frame(width: 67, height: 63)
                    }
                    .buttonStyle(ActionButtonStyle(color: world.autoCombat ? .green : .gray))
                }
                HStack(spacing: 9) {
                    Button { world.castSkill() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                            Text("KỸ NĂNG")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .frame(width: 76, height: 72)
                    }
                    .buttonStyle(ActionButtonStyle(color: .blue))
                    Button { world.normalAttack() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                            Text("TẤN CÔNG")
                                .font(.system(size: 11, weight: .heavy))
                        }
                        .frame(width: 85, height: 81)
                    }
                    .buttonStyle(ActionButtonStyle(color: .orange))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }

    private var inventorySheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image("GemTexture")
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text("Texture mẫu từ ThanhThan PC")
                    .font(.headline)
                Text("Tệp 1_1diem.ozj đã chuyển đổi thành PNG. Đây là tài nguyên thực từ bộ cài PC bạn cung cấp.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Label("\(world.gold) vàng", systemImage: "circle.hexagongrid.fill")
                Label("\(world.potions) bình máu", systemImage: "cross.vial.fill")
                Spacer()
            }
            .padding(24)
            .navigationTitle("TÚI ĐỒ – DEMO")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Đóng") { showingInventory = false }
            } }
        }
    }

    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Đây là bản thử nghiệm game 3D native cho iOS, không phải client ThanhThan PC đã được chuyển hoàn chỉnh.")
                        .font(.headline)
                    Label("Dùng cần điều khiển bên trái để di chuyển nhân vật", systemImage: "gamecontroller")
                    Label("Tiến đến quái, nhấn TẤN CÔNG để đánh thường", systemImage: "flame")
                    Label("Nhấn KỸ NĂNG để gây sát thương diện rộng (22 MP)", systemImage: "bolt")
                    Label("AUTO tự đánh quái ở gần; MÁU dùng bình hồi phục", systemImage: "cross.vial")
                    Text("Có: bản đồ 3D, nhân vật và quái 3D tạo mẫu, di chuyển, chiến đấu, EXP, cấp độ, vàng, hồi sinh, texture chuyển từ OZJ.")
                    Text("Chưa có: mô hình BMD hoàn chỉnh, tài khoản thật, máy chủ ThanhThan, giao thức mạng, dữ liệu nhiệm vụ và gameplay MU đầy đủ.")
                        .foregroundStyle(.orange)
                }
                .padding(22)
            }
            .navigationTitle("Bản thử nghiệm 0.1")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Đóng") { showingHelp = false }
            } }
        }
    }
}

private struct SceneCanvas: UIViewRepresentable {
    @ObservedObject var world: GameWorld
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = world.scene
        view.pointOfView = world.camera
        view.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        // SceneKit renders and updates the existing scene graph.
    }
}

private struct VirtualJoystick: View {
    let onMove: (CGFloat, CGFloat) -> Void
    @State private var delta = CGSize.zero
    private let outer: CGFloat = 126
    private let radius: CGFloat = 43
    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.46))
            Circle().stroke(Color.cyan.opacity(0.55), lineWidth: 2)
            Circle().stroke(Color.white.opacity(0.13), lineWidth: 1)
                .frame(width: 91, height: 91)
            Circle()
                .fill(LinearGradient(colors: [Color.cyan.opacity(0.88), Color.blue.opacity(0.8)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                .frame(width: 55, height: 55)
                .offset(delta)
        }
        .frame(width: outer, height: outer)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let dx = gesture.location.x - outer / 2
                let dy = gesture.location.y - outer / 2
                let length = max(1, sqrt(dx * dx + dy * dy))
                let scale = min(1, radius / length)
                let x = dx * scale
                let y = dy * scale
                delta = CGSize(width: x, height: y)
                onMove(x / radius, y / radius)
            }
            .onEnded { _ in
                delta = .zero
                onMove(0, 0)
            })
    }
}

private struct StatBar: View {
    let symbol: String
    let value: Int
    let maxValue: Int
    let fill: Color
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(fill)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                GeometryReader { proxy in
                    Capsule().fill(fill)
                        .frame(width: max(0, proxy.size.width * CGFloat(value) / CGFloat(maxValue)))
                }
            }
            .frame(height: 9)
            Text("\(label) \(value)")
                .font(.system(size: 10, weight: .heavy))
                .monospacedDigit()
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HudButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(.black.opacity(configuration.isPressed ? 0.75 : 0.53),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.24)))
    }
}

private struct ActionButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .foregroundStyle(.white)
            .background(color.opacity(configuration.isPressed ? 0.62 : 0.89), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.48), lineWidth: 2))
            .shadow(color: color.opacity(0.45), radius: 8)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
