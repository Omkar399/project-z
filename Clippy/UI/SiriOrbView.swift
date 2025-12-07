import SwiftUI

struct SiriOrbView: View {
    let state: ProjectZAnimationState
    
    // Independent rotation states for layered complexity
    @State private var rotation1: Double = 0
    @State private var rotation2: Double = 0
    @State private var rotation3: Double = 0
    
    // Pulsing and scale states
    @State private var coreScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.5
    
    // Timer is used for continuous, non-autoreversing rotation updates if needed,
    // though explicit animations handle most of this. Keeping it simple.
    
    var body: some View {
        ZStack {
            // LAYER 1: Ambient Glow (Base)
            // Large, heavily blurred, slow rotation. Sets the "mood" color.
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: getBaseColors(for: state)),
                        center: .center
                    )
                )
                .blur(radius: 20)
                .scaleEffect(1.3)
                .opacity(0.4)
                .rotationEffect(.degrees(rotation3))
            
            // LAYER 2: Outer Swirl
            // Medium speed, additive blend. Creates the "fluid" edge.
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: getPrimaryColors(for: state)),
                        center: .center
                    )
                )
                .blendMode(.screen) // Additive blending for "light" effect
                .blur(radius: 12)
                .rotationEffect(.degrees(rotation2))
                .scaleEffect(coreScale * 1.05)
            
            // LAYER 3: Core Swirl
            // Fast speed, distinct colors. The "active" part of the mind.
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: getSecondaryColors(for: state)),
                        center: .center
                    )
                )
                .blendMode(.plusLighter) // Intense center brightness
                .blur(radius: 8)
                .rotationEffect(.degrees(rotation1))
                .scaleEffect(coreScale)
                .overlay(
                    // Subtle white rim for definition
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [.white.opacity(0.6), .clear, .white.opacity(0.2)]),
                                center: .center
                            ),
                            lineWidth: 1
                        )
                        .rotationEffect(.degrees(-rotation1)) // Counter-rotate
                        .blur(radius: 2)
                )
        }
        .frame(width: 80, height: 80)
        .background(Color.clear) // Ensure view background is clear
        // Ensure animations start immediately
        .onAppear {
            startAnimations()
        }
        // Retrigger animations when state changes
        .onChange(of: state) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                // Reset or adjust params if needed for transition
                // but mainly we just let the colors change smoothly
                adjustAnimationParams()
            }
        }
    }
    
    private func startAnimations() {
        // Continuous Rotations (different speeds for organic feel)
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            rotation1 = 360
        }
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
            rotation2 = -360 // Counter-rotate
        }
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            rotation3 = 360
        }
        
        // Initial breathe
        adjustAnimationParams()
    }
    
    private func adjustAnimationParams() {
        // Customize pulsing/breathing per state
        switch state {
        case .idle:
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                coreScale = 1.05
                glowOpacity = 0.4
            }
        case .thinking:
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                coreScale = 1.15
                glowOpacity = 0.8
            }
        case .writing:
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                coreScale = 1.1
                glowOpacity = 0.6
            }
        case .done:
            // One-shot expansion
            coreScale = 1.2
            glowOpacity = 1.0
            withAnimation(.easeOut(duration: 0.8)) {
                coreScale = 1.0
                glowOpacity = 0.5
            }
        case .error:
            // Jittery pulse
            withAnimation(.spring(response: 0.2, dampingFraction: 0.2).repeatCount(3)) {
                coreScale = 0.9
            }
        case .incognito:
            coreScale = 0.95
            glowOpacity = 0.2
        }
    }
    
    // MARK: - Color Palettes
    
    // 1. Base Glow (Background/Ambient)
    private func getBaseColors(for state: ProjectZAnimationState) -> [Color] {
        switch state {
        case .idle:      return [.blue.opacity(0.5), .purple.opacity(0.5), .cyan.opacity(0.5), .blue.opacity(0.5)]
        case .thinking:  return [.orange.opacity(0.6), .pink.opacity(0.6), .purple.opacity(0.6), .orange.opacity(0.6)]
        case .writing:   return [.green.opacity(0.5), .mint.opacity(0.5), .blue.opacity(0.5), .green.opacity(0.5)]
        case .done:      return [.green, .mint, .white.opacity(0.5), .green]
        case .error:     return [.red.opacity(0.8), .orange.opacity(0.6), .red.opacity(0.8)]
        case .incognito: return [.black, .gray.opacity(0.5), .black]
        }
    }
    
    // 2. Primary Swirl (Outer, Liquid)
    private func getPrimaryColors(for state: ProjectZAnimationState) -> [Color] {
        switch state {
        case .idle:      return [.cyan, .clear, .blue, .clear, .purple, .clear, .cyan]
        case .thinking:  return [.yellow, .clear, .orange, .clear, .pink, .clear, .yellow]
        case .writing:   return [.mint, .clear, .teal, .clear, .blue, .clear, .mint]
        case .done:      return [.mint, .white, .green, .white, .mint]
        case .error:     return [.orange, .clear, .red, .clear, .orange]
        case .incognito: return [.gray, .clear, .white.opacity(0.2), .clear, .gray]
        }
    }
    
    // 3. Secondary Core (Inner, Intense)
    private func getSecondaryColors(for state: ProjectZAnimationState) -> [Color] {
        switch state {
        case .idle:      return [.white.opacity(0.8), .cyan, .blue.opacity(0.5), .white.opacity(0.8)]
        case .thinking:  return [.white.opacity(0.9), .purple, .orange, .white.opacity(0.9)]
        case .writing:   return [.white.opacity(0.8), .green, .teal, .white.opacity(0.8)]
        case .done:      return [.white, .green, .white]
        case .error:     return [.white, .red, .orange, .white]
        case .incognito: return [.white.opacity(0.4), .black, .white.opacity(0.4)]
        }
    }
}
