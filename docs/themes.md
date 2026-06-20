# Sanctum Themes

Sanctum's audio engine produces one signal that matters for the visuals: an
**energy arc** (`corruptionIndex`, 0→1) that climbs as cumulative audio energy
builds over the night. A **theme** decides what that build *looks and feels*
like. Themes are data — defined in [`Sources/App/Theme.swift`](../Sources/App/Theme.swift) —
so dressing the room for the next party is a content change, not an engine rewrite.

## Built-in themes

| Theme | id | Arc | Character |
|---|---|---|---|
| **Cathedral** | `cathedral` | sacred → awakening → fracture → profane → abyss | The original gothic stained glass that *corrupts* from sacred to profane as energy climbs. Cracks, melting, Escher folding, toxic neon. Edgy and dark. |
| **Beach Resort** | `beach` | sunset → golden hour → tropical dusk → neon night → midnight | A feel-good resort night. The same build adds vibrance, glow, shimmer and color instead of decay. Stays bright and fun all night. |

The beach theme centers its reactivity on its two motifs (gated by the
`shimmer` knob, off for cathedral): a **beating sun** that blooms and throws
rays on the kick (pulsing with the bass), **ocean waves** that roll and surge
in time with the beat while foam crests catch the light, and a **warm→neon
shift** that cycles cyan/magenta as the night peaks. The sun's position is set
per theme (`Theme.sunPosition`).

A theme defines, per phase, a color grade (`tint`) and a display name, plus a
panel crossfade order, a drifting icon set, an **effect profile** (how strongly
the audio-reactive effects distort vs. glow), and a composite **energy tint**
(cathedral drains toward dark; beach stays bright and warm).

## Choosing a theme

**Config (persists):** set `theme` in `sanctum-config.json`:

```json
{
  "theme": "beach",
  "audioSource": "line-in",
  "corruptionWindowHours": 5.0
}
```

Unknown / missing values fall back to sensible defaults (`theme` → `cathedral`),
and a config file missing some keys still loads fine — only the keys you set are
applied.

**Live (during an event):** press **`T`** to cycle themes on the fly. Other keys:
`D` toggles the debug overlay (now shows the active theme + phase), `R` resets
the energy arc, `Esc` quits.

## Generating the art

Stained-glass art lives under `Assets/` (git-ignored — generated per machine).
The beach generators are pure Python (no dependencies) and write full-res
1920×1080 panels and 512×512 icons:

```sh
python3 scripts/generate-beach-panels.py
python3 scripts/generate-beach-icons.py
```

Override resolution/output for a quick preview:

```sh
SANCTUM_PANEL_W=640 SANCTUM_PANEL_H=360 python3 scripts/generate-beach-panels.py
SANCTUM_ICON_SIZE=256 python3 scripts/generate-beach-icons.py
SANCTUM_ASSETS=/tmp/preview python3 scripts/generate-beach-panels.py
```

If the art for a theme isn't present, Sanctum falls back to solid color
placeholders derived from each phase's tint, so the arc is still visible.

**Panels** (one per phase, crossfaded as energy builds): each is the beach
framed as the view through an arched resort window (cream Palladian frame,
sunburst arch, glazed panes). The window stays put while the view beyond it
transitions sunset → midnight:
`panel-beach-sunset`, `panel-beach-goldenhour`, `panel-beach-dusk`,
`panel-beach-neonnight`, `panel-beach-midnight`.

**Icons** (drift across the wall): sun, palm, wave, cocktail, flamingo, shell,
starfish, pineapple.

## Adding a theme for the next party

1. Add a `Theme` value in `Theme.swift` and include it in `Theme.all`.
2. Pick five phase tints + names, a panel order, and an icon set.
3. Tune the `EffectProfile` (e.g. cracks/fold at 0 and shimmer up for a fun
   vibe; crank them for something darker).
4. Add `generate-<theme>-panels.py` / `-icons.py` producing assets whose names
   match `panelOrder` / `icons`.
5. Set `theme` in the config (or cycle to it with `T`).

New Swift/test files are picked up by XcodeGen — run `xcodegen generate` after
adding them.
