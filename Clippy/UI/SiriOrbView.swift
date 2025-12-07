import SwiftUI

struct SiriOrbView: View {
    let state: ProjectZAnimationState
    
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    // Timer to drive continuous animations
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: getColors(for: state)),
                        center: .center
                    )
                )
                .blur(radius: 20)
                .scaleEffect(scale * 1.1)
                .opacity(0.5)
            
            // Core orb
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: getColors(for: state)),
                        center: .center
                    )
                )
                .blur(radius: 10)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .blur(radius: 4)
                )
        }
        .frame(width: 80, height: 80)
        .onAppear {
            updateAnimations()
        }
        .onChange(of: state) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                updateAnimations()
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.linear(duration: 0.1)) {
                // Continuous rotation logic could go here if not using explicit animations
                // But for smooth rotation, we use .repeatForever in updateAnimations
            }
        }
    }
    
    private func updateAnimations() {
        // Reset
        rotation = 0
        
        switch state {
        case .idle:
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                scale = 1.05
            }
            
        case .thinking:
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                scale = 1.15
            }
            
        case .writing:
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                scale = 1.1
            }
            
        case .done:
            rotation = 0
            scale = 1.2
            withAnimation(.easeOut(duration: 0.5)) {
                scale = 1.0
            }
            
        case .error:
            rotation = 0
            withAnimation(.spring(response: 0.3, dampingFraction: 0.2)) {
                scale = 0.9
            }
            
        case .incognito:
            rotation = 0
            scale = 0.95
        }
    }
    
    private func getColors(for state: ProjectZAnimationState) -> [Color] {
        switch state {
        case .idle:
            return [.cyan, .blue, .purple, .cyan]
        case .thinking:
            return [.purple, .pink, .orange, .yellow, .purple]
        case .writing:
            return [.blue, .green, .mint, .blue]
        case .done:
            return [.green, .mint, .white, .green]
        case .error:
            return [.red, .orange, .pink, .red]
        case .incognito:
            return [.gray, .black, .blue.opacity(0.3), .gray]
        }
    }
}
