import SwiftUI

// Adapted from metasidd/Orb (MIT): rotating crescent masks, two six-point
// Bezier blobs, additive core glows, and a circular shell. The shared demo
// clock replaces repeatForever animations so pause works across all styles.
struct SiriOrb: View {
  let time: Double
  let level: Double

  var body: some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      ZStack {
        LinearGradient(colors: [Color(red: 0.27, green: 0.03, blue: 0.16),
          Color(red: 0.025, green: 0.12, blue: 0.25), Color(red: 0.025, green: 0.14, blue: 0.32)],
          startPoint: .bottom, endPoint: .top)
        OrbCrescent(color: .cyan, angle: time * -24 + 160)
          .padding(size * 0.02).blur(radius: size * 0.045)
        OrbCrescent(color: .pink, angle: time * 18 + 15)
          .padding(size * 0.035).blur(radius: size * 0.032)
        OrbCrescent(color: Color(red: 0.15, green: 1, blue: 0.62), angle: time * -17 + 255)
          .padding(size * 0.08).blur(radius: size * 0.035).opacity(0.7)
        OrbCrescent(color: .white.opacity(0.85), angle: time * 60 * 1.5)
          .mask {
            OrbBlob(time: time, duration: 1.75)
              .frame(width: size * 1.875, height: size).offset(y: size * 0.31)
          }
          .blur(radius: max(0.3, size / 190)).blendMode(.plusLighter).opacity(0.45)
        OrbCrescent(color: .white, angle: time * -60 * 0.75)
          .mask {
            OrbBlob(time: time, duration: 2.25)
              .frame(width: size * 1.25, height: size)
              .rotationEffect(.degrees(90)).offset(y: size * -0.31)
          }
          .opacity(0.25).blur(radius: max(0.3, size / 190)).blendMode(.plusLighter)
        OrbLightPetals(time: time, level: level)
          .blendMode(.plusLighter)
        OrbCrescent(color: .white, angle: time * 60 * 3)
          .padding(size * 0.08).blur(radius: size * 0.08).opacity(0.08 + level * 0.15)
        OrbCrescent(color: .white, angle: time * 60 * 2.3)
          .padding(size * 0.08).blur(radius: size * 0.06).blendMode(.plusLighter)
          .opacity(0.08 + level * 0.18)
      }
      .overlay {
        let outline = LinearGradient(colors: [.white.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top)
        ZStack {
          Circle().stroke(outline, lineWidth: size * 0.04).blur(radius: size * 0.1)
          Circle().stroke(outline, lineWidth: size * 0.012).blur(radius: size * 0.025)
          Circle().stroke(outline, lineWidth: size * 0.005).blur(radius: size * 0.006)
        }.blendMode(.plusLighter)
      }
      .compositingGroup().clipShape(Circle())
      .shadow(color: .cyan.opacity(0.12 + level * 0.1), radius: size * 0.065, y: -size * 0.02)
      .shadow(color: .pink.opacity(0.15 + level * 0.1), radius: size * 0.09, y: size * 0.035)
      .scaleEffect(0.94 + level * 0.06)
    }.accessibilityLabel("Siri 彩色球体")
  }
}

// The Apple iOS 14 reference has distinct colored light petals meeting at a
// bright core. These Bezier surfaces supplement the upstream crescent shell;
// they are a visual reconstruction, not an Apple shader or a source port.
private struct OrbLightPetals: View {
  let time: Double
  let level: Double

  var body: some View {
    Canvas { context, size in
      let s = min(size.width, size.height)
      context.translateBy(x: size.width / 2, y: size.height * 0.55)
      context.scaleBy(x: s, y: s)
      let motion = sin(time * 1.4) * (0.025 + level * 0.025)
      let core = CGPoint(x: motion * 0.5, y: 0.045)
      let definitions: [(Color, CGPoint, CGPoint, CGPoint, CGPoint, CGPoint)] = [
        (.cyan, CGPoint(x: 0.115 + motion, y: -0.25),
         CGPoint(x: -0.16, y: -0.015), CGPoint(x: -0.07, y: -0.39),
         CGPoint(x: 0.28, y: -0.34), CGPoint(x: 0.1, y: -0.055)),
        (Color(red: 0.15, green: 1, blue: 0.65), CGPoint(x: 0.40, y: -0.12 + motion),
         CGPoint(x: 0.14, y: 0.03), CGPoint(x: 0.3, y: -0.23),
         CGPoint(x: 0.47, y: 0.10), CGPoint(x: 0.20, y: 0.21)),
        (Color(red: 1, green: 0.16, blue: 0.44), CGPoint(x: -0.405, y: -0.065 - motion),
         CGPoint(x: -0.12, y: 0.13), CGPoint(x: -0.43, y: 0.10),
         CGPoint(x: -0.40, y: -0.30), CGPoint(x: -0.12, y: -0.025)),
      ]
      context.blendMode = .plusLighter
      context.opacity = 0.65 + level * 0.25
      for (index, definition) in definitions.enumerated() {
        let (color, tip, c1, c2, c3, c4) = definition
        var petal = Path()
        petal.move(to: core)
        petal.addCurve(to: tip, control1: c1, control2: c2)
        petal.addCurve(to: core, control1: c3, control2: c4)
        petal.closeSubpath()
        var layer = context
        layer.rotate(by: .degrees(sin(time * (0.8 + Double(index) * 0.2) + Double(index)) * 13))
        layer.fill(petal, with: .linearGradient(Gradient(stops: [
          .init(color: .white, location: 0), .init(color: color.opacity(0.95), location: 0.57),
          .init(color: color.opacity(0.5), location: 1)
        ]), startPoint: core, endPoint: tip))
      }
      let centerGlow = Path(ellipseIn: CGRect(x: core.x - 0.12, y: core.y - 0.07, width: 0.24, height: 0.14))
      context.fill(centerGlow, with: .radialGradient(Gradient(colors: [.white.opacity(0.85), .clear]),
        center: core, startRadius: 0, endRadius: 0.12))
    }
  }
}

private struct OrbCrescent: View {
  let color: Color
  let angle: Double
  var body: some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      Circle().fill(color)
        .mask {
          ZStack {
            Circle().frame(width: size, height: size).blur(radius: size * 0.16)
            Circle().frame(width: size * 1.31, height: size * 1.31)
              .offset(y: size * 0.31).blur(radius: size * 0.16).blendMode(.destinationOut)
          }.compositingGroup()
        }
        .rotationEffect(.degrees(angle))
    }
  }
}

private struct OrbBlob: View {
  let time: Double
  let duration: Double
  var body: some View {
    Canvas { context, size in
      let angle = time.truncatingRemainder(dividingBy: duration) / duration * 2 * .pi
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = min(size.width, size.height) * 0.45
      let points = (0..<6).map { index in
        let phase = Double(index) * .pi / 3
        return CGPoint(x: (cos(phase) * 0.9 + sin(angle + phase) * 0.15) * radius + center.x,
          y: (sin(phase) * 0.9 + cos(angle + phase) * 0.15) * radius + center.y)
      }
      var path = Path()
      path.move(to: points[0])
      for index in points.indices {
        let next = (index + 1) % points.count
        let firstAngle = atan2(points[index].y - center.y, points[index].x - center.x)
        let secondAngle = atan2(points[next].y - center.y, points[next].x - center.x)
        let handle = radius * 0.33
        path.addCurve(to: points[next],
          control1: CGPoint(x: points[index].x + cos(firstAngle + .pi / 2) * handle,
            y: points[index].y + sin(firstAngle + .pi / 2) * handle),
          control2: CGPoint(x: points[next].x + cos(secondAngle - .pi / 2) * handle,
            y: points[next].y + sin(secondAngle - .pi / 2) * handle))
      }
      path.closeSubpath()
      context.fill(path, with: .color(.white))
    }
  }
}
