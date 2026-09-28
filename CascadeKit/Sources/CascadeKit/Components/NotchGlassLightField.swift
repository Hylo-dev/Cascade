import CascadeContracts
import SwiftUI

/// A single bounded draw beneath native glass. Gradients provide diffusion
/// without layer blur, another display link, or rerendering the widget controls.
struct NotchGlassLightField: View {
    let lights: [GlassLight]

    var body: some View {
        Canvas { context, size in
            context.blendMode = .plusLighter
            let bounds = CGRect(origin: .zero, size: size)
            for light in lights.prefix(GlassLight.maximumCount) where light.intensity > 0 {
                let color = Color(red: light.red, green: light.green, blue: light.blue)
                let center = CGPoint(x: light.x * size.width, y: light.y * size.height)
                context.fill(Path(bounds), with: .radialGradient(
                    Gradient(stops: [
                        .init(color: color.opacity(light.intensity), location: 0),
                        .init(color: color.opacity(light.intensity * 0.55), location: 0.25),
                        .init(color: color.opacity(light.intensity * 0.12), location: 0.65),
                        .init(color: color.opacity(0), location: 1)
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: light.radius * size.width
                ))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
