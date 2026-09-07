import SwiftUI

// Native port of kopiro/siriwave src/ios9-curve.ts (MIT).
// See THIRD_PARTY_NOTICES.txt and REFERENCES.md for upstream revisions.
// Retains attenuation, spawn ranges, mirrored lobes, RGB fills, additive blend.
struct ClassicWaveSnapshot {
  var samples: [[Double]]
}

final class ClassicWaveEngine {
  private struct Lobe {
    var phase = 0.0
    var amplitude = 0.0
    var lifetime: Double
    var offset: Double
    var speed: Double
    var target: Double
    var width: Double
    var direction: Double
  }
  private struct Group {
    var spawnedAt = -1.0
    var previousPeak = 0.0
    var lobes: [Lobe] = []
  }
  private var groups = Array(repeating: Group(), count: 3)
  private var randomState: UInt64 = 0x51A1_2026
  private var lastTime: Double?
  private var simulatedTime = 0.0

  private func random(_ lower: Double, _ upper: Double) -> Double {
    randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
    let unit = Double(randomState >> 11) / Double(UInt64(1) << 53)
    return lower + unit * (upper - lower)
  }
  private func spawn(at time: Double) -> Group {
    let count = Int(random(2, 5))
    let lobes = (0..<count).map { _ in
      Lobe(lifetime: random(0.5, 2), offset: random(-3, 3), speed: random(0.5, 1),
        target: random(0.3, 1), width: random(1, 3), direction: random(-1, 1))
    }
    return Group(spawnedAt: time, lobes: lobes)
  }
  private func attenuation(_ x: Double) -> Double { pow(4 / (4 + x * x), 4) }

  private func relativeY(_ x: Double, group: Group) -> Double {
    var y = 0.0
    for (index, lobe) in group.lobes.enumerated() {
      let separation = 4 * (-1 + Double(index) / Double(group.lobes.count - 1) * 2) + lobe.offset
      let localX = x / lobe.width - separation
      y += abs(lobe.amplitude * sin(lobe.direction * localX - lobe.phase) * attenuation(localX))
    }
    return y / Double(group.lobes.count) * attenuation(x / 25 * 2)
  }

  func snapshot(at time: Double, level: Double) -> ClassicWaveSnapshot {
    // Normalize upstream's frame increments to 60 Hz and cap catch-up after
    // occlusion. All preview sizes receive the same immutable wave snapshot.
    let delta = min(0.1, max(0, time - (lastTime ?? (time - 1.0 / 60))))
    lastTime = time
    simulatedTime += delta
    let frames = delta * 60
    var output: [[Double]] = []
    for index in groups.indices {
      if groups[index].spawnedAt < 0 { groups[index] = spawn(at: simulatedTime) }
      var group = groups[index]
      for lobeIndex in group.lobes.indices {
        let fading = simulatedTime >= group.spawnedAt + group.lobes[lobeIndex].lifetime
        group.lobes[lobeIndex].amplitude += (fading ? -0.02 : 0.02) * frames
        group.lobes[lobeIndex].amplitude = min(group.lobes[lobeIndex].target,
          max(0, group.lobes[lobeIndex].amplitude))
        group.lobes[lobeIndex].phase = (group.lobes[lobeIndex].phase + 0.2 * group.lobes[lobeIndex].speed * frames)
          .truncatingRemainder(dividingBy: 2 * .pi)
      }
      let samples = (0...1000).map { relativeY(-25 + Double($0) * 0.05, group: group) }
      let peak = (samples.max() ?? 0) * 0.8 * 160 * level
      if peak < 2 && group.previousPeak > peak { group.spawnedAt = -1 }
      group.previousPeak = peak
      groups[index] = group
      output.append(samples)
    }
    return ClassicWaveSnapshot(samples: output)
  }
}

struct ClassicSiriWave: View {
  let snapshot: ClassicWaveSnapshot
  let level: Double
  let dark: Bool
  private let colors = [Color(red: 15 / 255, green: 82 / 255, blue: 169 / 255),
    Color(red: 173 / 255, green: 57 / 255, blue: 76 / 255),
    Color(red: 48 / 255, green: 220 / 255, blue: 155 / 255)]

  var body: some View {
    Canvas { context, size in
      let center = size.height / 2
      let support = dark ? Color.white : Color.black
      context.opacity = 0.7
      context.fill(Path(CGRect(x: 0, y: center, width: size.width, height: 0.5)),
        with: .linearGradient(Gradient(stops: [
          .init(color: .clear, location: 0), .init(color: support.opacity(0.5), location: 0.1),
          .init(color: support.opacity(0.5), location: 0.8), .init(color: .clear, location: 1)
        ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
      // Isolate addition from the background, so light mode remains legible.
      context.opacity = 1
      context.drawLayer { bands in
        bands.opacity = 1
        bands.blendMode = .plusLighter
        for (index, samples) in snapshot.samples.enumerated() {
          var path = Path()
          for (sampleIndex, sample) in samples.enumerated() {
            let point = CGPoint(x: Double(sampleIndex) / Double(samples.count - 1) * size.width,
              y: center - sample * 0.8 * max(1, center - 3) * level)
            if sampleIndex == 0 { path.move(to: point) } else { path.addLine(to: point) }
          }
          for sampleIndex in samples.indices.reversed() {
            path.addLine(to: CGPoint(x: Double(sampleIndex) / Double(samples.count - 1) * size.width,
              y: center + samples[sampleIndex] * 0.8 * max(1, center - 3) * level))
          }
          path.closeSubpath()
          bands.fill(path, with: .color(colors[index].opacity(0.7)))
        }
      }
    }.accessibilityLabel("经典 Siri 横向波形")
  }
}
