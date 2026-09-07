# Siri visual comparison demo

This is a native SwiftUI visual reproduction. Apple has not published the system effect source code; the demo does not embed a system Siri view.

## Reference implementations

- https://github.com/kopiro/siriwave/tree/744cb00235b7900733efff25dc73b4d1ab77c92d
- https://github.com/metasidd/Orb/tree/a48fc3382ad40905ca4aa9691c6b504004740ad1
- https://github.com/jacobamobin/AppleIntelligenceGlowEffect/tree/5f388f1c51322f62f2181693e125d955d9a45237

- ClassicWave.swift ports SiriWave's iOS 9 attenuation and random lobe lifecycle, RGB palette, mirrored filling and additive composition. Frame increments are normalized to elapsed time at 60 Hz. Samples use a 0.05 step instead of upstream's 0.02. One simulation is shared by the large and small previews; the 2 px respawn threshold uses a fixed reference size. Light mode uses a dark support line.
- Orb.swift adapts Orb's rotating crescent masks, Bezier blobs, additive core and shell. It replaces independent repeating animations with the shared clock, omits particles, and uses a darker shell with cyan, green and pink light to match the Apple reference. It is an approximation of the Apple orb.
- The production IntelligenceGlowBorder.swift (shared by the demo through EdgeGlow.swift) adapts IOS.swift's six-color palette and four sharp/blurred strokes, with an additional soft outer halo. It uses continuous color positions, scaling for the miniature screen/capsule, and a shared clock instead of independent random timers. It is an approximation of the Apple border.

## Apple visual references

- iOS 14 Siri: https://www.apple.com/newsroom/2020/06/apple-reimagines-the-iphone-experience-with-ios-14/
- Apple Intelligence: https://www.apple.com/newsroom/2024/06/introducing-apple-intelligence-for-iphone-ipad-and-mac/

## Run

From the project root:

```sh
sh Tools/build_voice_ribbon_demo.sh
open .build/demos/VoiceRibbonDemo.app
```

The app starts all three styles side by side. The top picker enlarges a style; bottom controls switch between constant amplitude and simulated speech, set level, or pause all three. No microphone or network access is used by the demo.

## Selected treatment

On 2026-09-07, the user selected the Apple Intelligence surround. The production recording capsule uses the same border renderer as the demo. The user subsequently preferred a quieter treatment: resting band thickness stays fixed, speech adds at most 28% thickness, and the diffuse/outer layers are subdued so they do not compete with the transcript. Processing uses the resting width. The controller explicitly pauses updates when the panel is hidden, and Reduce Motion fixes both the border position and its intensity. Live transcription replaces the listening label and timer inside a single capsule with optional cancel and finish controls. Long text follows its tail through a viewport with transparent edge fades, without truncation ellipses. Display-only line breaks become spaces, while accessibility retains the complete original text. Processing and status messages reuse the same surface.

The user requested clearer glass and stronger voice feedback. On macOS 26 the capsule uses clear Liquid Glass over a faint appearance-aware scrim for text contrast; earlier systems use ultra-thin material. Reduce Transparency retains the regular material. See Apple's guidance for [clear glass](https://developer.apple.com/documentation/swiftui/glass/clear).

Presentation uses a stable `GlassEffectContainer`, a namespaced `glassEffectID`, and the native `.materialize` transition on macOS 26. The custom colored border renders after the glass pass but shares its presentation state and animation transaction. Recording sessions retain the border through final/status messages, so it does not disappear before the capsule. The controller orders out the panel only after SwiftUI reports that removal animations have completed; a generation guard prevents an old dismissal from hiding a new presentation. Earlier systems use an opacity transition, and Reduce Motion disables the animation.

The user prefers prompt tool feedback: appearance uses a 0.14 s ease-out animation so it becomes readable quickly; dismissal uses a 0.18 s ease-in animation. Both replace the earlier 0.28 s smooth animation without changing the native glass effect or shared border lifetime.

The user operates dictation through keyboard shortcuts. Cancel and finish buttons are hidden by default; the capsule is 220 pt wide without them and 300 pt wide when they are enabled. Glass and border resize together, while the transparent hosting panel stays centered and stable; Settings > 常规 > 显示胶囊控制按钮 can restore them. This preference persists and updates an open capsule immediately. With buttons hidden, short transcripts are centered, long transcripts use the available width, and the panel lets mouse clicks pass through. The processing indicator remains visible while transcribing. Keyboard handling is independent of this setting.

Apple references: [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [materialize](https://developer.apple.com/documentation/swiftui/glasseffecttransition/materialize), and [withAnimation completion](https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)).
