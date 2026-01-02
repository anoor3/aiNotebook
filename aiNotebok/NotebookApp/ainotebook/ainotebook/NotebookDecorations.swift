import SwiftUI

struct SpiralBinding: View {
    var holeCount: Int = 10
    var spineColor: Color = Color.black.opacity(0.2)
    var holeColor: Color = Color.white.opacity(0.9)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [spineColor.opacity(0.8), spineColor],
                                     startPoint: .top,
                                     endPoint: .bottom))

            VStack(spacing: 12) {
                ForEach(0..<holeCount, id: \.self) { _ in
                    Capsule()
                        .fill(holeColor)
                        .frame(width: 20, height: 8)
                        .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                }
            }
            .padding(.vertical, 18)
        }
        .frame(width: 38)
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 2, y: 2)
    }
}
