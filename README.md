# Swift Gradient Kit

Grainy, non-generic gradient wallpapers, rendered on the GPU from a small
`Codable` scene. **Headless**: no UI frameworks, no network. A `GradientKitUI`
target adds one SwiftUI view for live previews.

```
Wallpaper (Codable value) → WallpaperRenderer (Metal) → CGImage → PNG / JPEG / HEIC
```

The look it is built for — a black disc with a bright rim decaying into
navy, a pastel sky cut by a dark diagonal with a glowing seam, a soft sphere
sitting in its own light, all under fine film grain — does not come from
stacking blurred ellipses. It comes from one idea:

> **colour is a function of signed distance to an edge.**

Every layer is a shape (circle, ellipse, half-plane, wave, ring, crescent)
whose signed-distance field is mapped through a colour ramp: negative
positions are inside, zero is the edge, positive is the glow outside. A thin
bright stop just outside zero *is* the rim; a wide fade *is* the halo. Blend
in OKLab, warp the coordinate space with simplex noise, add grain, dither.

## Usage

```swift
import GradientKit

// A seeded composition: same seed, same pixels, on any machine.
let wallpaper = Wallpaper.generate(.eclipse, palette: .eclipse, seed: 7919)

let renderer = try WallpaperRenderer()
let image = try renderer.render(wallpaper, resolution: .studioDisplay)   // 5120 × 2880
try ImageExport.write(image, to: url, format: .png)
```

Or build a scene by hand:

```swift
var scene = Wallpaper(background: .linear([.init(hex: "#F2A6DE")!, .init(hex: "#3DE8F2")!], angle: -30))
scene.layers = [
    Layer(name: "Horizon",
          shape: .line(through: [0.62, 0.72], angle: -135, bend: 0.08),
          spread: 0.5,
          ramp: [
              RampStop(-1.0, .black),                                  // deep inside
              RampStop(-0.1, RGBA(hex: "#3A0A12")!),                   // maroon shoulder
              RampStop(0.16, RGBA(hex: "#FF4553")!),                   // the seam
              RampStop(0.9,  RGBA(hex: "#F2A6DE")!.with(alpha: 0)),    // fades into the sky
          ])
]
scene.effects.grain = Grain(intensity: 0.07, size: 1.2, chroma: 0.25)
scene.effects.aberration = 1.5
```

Everything is a value: `Wallpaper` round-trips through JSON, so a scene is a
file and a seed is a permanent address for a generated one.

## Styles it covers

Soft rims and eclipses; planet-edge glows; pastel horizons; warped mesh
gradients; noise fields (nebulae) and their contour lines (topographic
maps); flowing ribbons; holographic hue sweeps; colour ladders and retro
diagonal stripes (stepped ramps); palette swatch cards; and — with relief
lighting, which turns the distance field into a lit height map — extruded
chevron ridges, bevelled keycap tiles and glossy liquid blobs. A liquify
brush (`Effects.smears`) pushes, swirls, pinches or bloats the picture like
wet paint, and because the scene is analytic the strokes export at any size.
Emoji (or a word) are shapes too: rasterised with CoreText, turned into an
exact distance field, and tiled with per-cell jitter — so they take drop
shadows, glows and 3-D relief like everything else (`glyph`, `glyphPattern`).

## What's in the box

- **Model** — `Wallpaper`, `Background` (solid / linear / radial / mesh,
  optionally stepped), `Layer` with a `Shape` (circle, ellipse, line, wave,
  ring, crescent, polygon, rect, capsule, stripes, chevrons, tiles, blob,
  noise field), a signed-distance `ramp` (optionally stepped, repeating, or
  hue-swept), `spread`, blend mode, opacity, noise `distortion`, one-sided
  `lighting` and `relief` (height profile + directional light + specular);
  `Effects` (grain, vignette, domain warp, chromatic aberration, tone,
  liquify `smears`). Positions are canvas-normalised so one scene
  re-composes itself for any aspect ratio; lengths are in units of the
  shorter side. Older scene JSON keeps decoding as fields are added.
- **Renderer** — a single Metal compute kernel compiled at first use (plain
  `swift build`, no metallib step). OKLab interpolation between stops,
  linear-light compositing with normal / add / screen / multiply / soft-light
  / overlay, 2-D simplex noise for warp and distortion, film grain applied
  in gamma space so it survives in the shadows, triangular dither, 8- or
  16-bit output. A 5K frame renders in a few milliseconds; PNG encoding is
  the slow part.
- **Colour** — `RGBA` with hex, OKLab and OKLCH in and out, gamut mapping by
  chroma reduction (hue never shifts), OKLab mixing and adjustment.
- **Palettes** — six roles (`base`, `baseAlt`, `accent`, `secondary`,
  `highlight`, `deep`) every recipe is written against; twelve curated
  palettes lifted from reference wallpapers; OKLCH generation from a seed
  with split-complement / analogous-clash / triad harmonies.
- **Generator** — 21 motifs, each a seeded recipe: `eclipse`, `orb`,
  `horizon`, `hill`, `crescent`, `halo`, `glow`, `classic`, `aurora`,
  `mesh`, `nebula`, `topo`, `holo`, `ribbons`, `chevron`, `keycaps`,
  `liquid`, `prism`, `ladder`, `retro`, `swatches`. Every position, radius,
  spread, ramp and effect is jittered from the seed, so a motif is a family
  and a seed picks one member. `SeededRandom` is SplitMix64 with its own
  distributions, so seeds are stable across Swift versions.
- **Library** — `PaletteStore` / `GradientStore`: built-in defaults plus a
  folder of JSON files (one item or an array per file), `reload()`,
  `save`, `delete`, `importFile`; custom items override defaults by name.
  `GradientPreset` carries stops + stepped + angle and applies to a
  background or a layer; `Layer.starter(kind, palette:)` gives an editor a
  palette-matched layer of any shape.
- **Resolutions** — native pixel presets for Macs, iPhones, iPads, Watch,
  and social sizes.
- **Export** — PNG (16-bit preserved), JPEG, HEIC via ImageIO.
- **GradientKitUI** — `WallpaperMetalView(wallpaper)` is a zero-copy live
  preview: the kernel writes straight into the MTKView drawable (no
  readback), so edits are one dispatch even on a 5K-backed view.
  `WallpaperView` is the CGImage-backed alternative for thumbnails;
  `SharedRenderer` is the process-wide actor behind it.

## Samples

```
swift run -c release gradientkit-samples out --seeds 6            # every motif, six seeds, plus a contact sheet
swift run -c release gradientkit-samples out --width 5120 --height 2880 \
    --picks eclipse:7919,horizon:17838                            # specific seeds at 5K
```

## Requirements

- macOS 15+ / iOS 18+ (Metal), Swift 6.2
- A Metal device; there is no CPU fallback.

## License

MIT — see [LICENSE](LICENSE).
