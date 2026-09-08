import SwiftUI

struct AppIconView: View {
    // MARK: - 配色
    private let bgColor1 = Color(red: 0.08, green: 0.04, blue: 0.20)
    private let bgColor2 = Color(red: 0.14, green: 0.07, blue: 0.30)
    private let bgColor3 = Color(red: 0.06, green: 0.03, blue: 0.16)
    
    private let figureLightTop = Color(red: 0.84, green: 0.75, blue: 0.96)
    private let figureMid = Color(red: 0.68, green: 0.56, blue: 0.88)
    private let figureDarkBottom = Color(red: 0.48, green: 0.36, blue: 0.72)
    
    var body: some View {
        ZStack {
            // === 深紫色渐变背景 ===
            RoundedRectangle(cornerRadius: 180)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: bgColor1, location: 0),
                            .init(color: bgColor2, location: 0.45),
                            .init(color: bgColor3, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // === 背景微光环（营造深度感）===
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.35, green: 0.22, blue: 0.58).opacity(0.30),
                            Color(red: 0.20, green: 0.12, blue: 0.40).opacity(0.10),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 60,
                        endRadius: 420
                    )
                )
                .frame(width: 840, height: 840)
                .offset(y: 0)
            
            // === 人形剪影 ===
            // 头部
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: figureLightTop.opacity(0.98), location: 0),
                            .init(color: figureMid.opacity(0.92), location: 0.6),
                            .init(color: figureDarkBottom.opacity(0.85), location: 1)
                        ],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 15,
                        endRadius: 170
                    )
                )
                .frame(width: 290, height: 290)
                .offset(y: -170)
            
            // 肩膀/上身（径向渐变，模拟球体立体感）
            Ellipse()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: figureLightTop.opacity(0.95), location: 0),
                            .init(color: figureMid.opacity(0.90), location: 0.45),
                            .init(color: figureDarkBottom.opacity(0.82), location: 0.75),
                            .init(color: Color(red: 0.38, green: 0.28, blue: 0.62).opacity(0.75), location: 1)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.25),
                        startRadius: 20,
                        endRadius: 340
                    )
                )
                .frame(width: 640, height: 580)
                .offset(y: 180)
            
            // === 光泽质感 ===
            // 头部高光（左上方，模拟 3D 光源）
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 5,
                        endRadius: 100
                    )
                )
                .frame(width: 180, height: 150)
                .offset(x: -45, y: -210)
            
            // 肩部柔光条
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.03),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.45, y: 0.20),
                        startRadius: 10,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 200)
                .offset(x: -30, y: 40)
            
            // 顶部玻璃质感弧光
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 600, height: 300)
                .offset(y: -300)
            
            // 底部边缘微光（增加立体感）
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.55, green: 0.40, blue: 0.80).opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 150)
                .offset(y: 380)
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 180))
    }
}

#Preview {
    AppIconView()
        .padding()
        .background(Color.gray.opacity(0.1))
}
