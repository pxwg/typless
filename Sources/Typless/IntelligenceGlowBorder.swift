import SwiftUI

// Layered sharp/blurred strokes and the six-color palette are adapted from
// jacobamobin/AppleIntelligenceGlowEffect (MIT), IOS.swift. Color positions use
// the supplied clock instead of a random timer. See THIRD_PARTY_NOTICES.txt.
struct IntelligenceGlowBorder: View {
  let time: Double
  let level: Double
  let cornerRadius: CGFloat
  private let colors: [Color] = [
    Color(red: 0xBC / 255, green: 0x82 / 255, blue: 0xF3 / 255),
    Color(red: 0xF5 / 255, green: 0xB9 / 255, blue: 0xEA / 255),
    Color(red: 0x8D / 255, green: 0x9F / 255, blue: 0xFF / 255),
    Color(red: 0xFF / 255, green: 0x67 / 255, blue: 0x78 / 255),
    Color(red: 0xFF / 255, green: 0xBA / 255, blue: 0x71 / 255),
    Color(red: 0xC6 / 255, green: 0x86 / 255, blue: 0xFF / 255),
  ]
  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.height < 80
      // Keep the resting width fixed and give speech a restrained expansion.
      // The capsule itself stays still while speaking.
      let response = pow(max(0, min(1, level)), 0.7)
      let scale = (compact ? 0.30 : 0.4) * (1 + 0.28 * response)
      let pulse = 0.60 + 0.06 * response
      let stops = colors.enumerated().map { index, color in
        Gradient.Stop(color: color, location: Double(index) / 6 + sin(time * 0.65 + Double(index) * 1.7) * 0.055)
      }
      let gradient = AngularGradient(gradient: Gradient(stops:
        [.init(color: colors[0], location: 0)] + stops.map {
          .init(color: $0.color, location: min(0.98, max(0.01, $0.location)))
        }.sorted { $0.location < $1.location } + [.init(color: colors[0], location: 1)]),
        center: .center, angle: .degrees(time * 24))
      let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      ZStack {
        // Keep a little light outside the glass; clipping every layer made
        // the original treatment read as a thin inset border.
        shape.stroke(gradient, lineWidth: 6 * scale)
          .blur(radius: 8 * scale)
          .opacity(0.10 + 0.06 * response)
        ZStack {
          shape.strokeBorder(gradient, lineWidth: 6 * scale).opacity(pulse)
          shape.strokeBorder(gradient, lineWidth: 9 * scale).blur(radius: 4 * scale).opacity(pulse * 0.65)
          shape.strokeBorder(gradient, lineWidth: 11 * scale).blur(radius: 12 * scale).opacity(pulse * 0.42)
          shape.strokeBorder(gradient, lineWidth: 15 * scale).blur(radius: 15 * scale).opacity(pulse * 0.28)
        }.compositingGroup().clipShape(shape)
      }.compositingGroup()
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}
