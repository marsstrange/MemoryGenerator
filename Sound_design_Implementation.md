# Sound Design Implementation

## The idea

Sound reacts to two independent things at once:

- **Mood (continuous)** — the viewer's face emotion (`/valence`, `/arousal`, sent every frame) reshapes whichever soundscape is currently playing: pad brightness, chord tightness, note density/speed. It never changes *what* is playing, only how it behaves.
- **Painting style (discrete)** — every time a new painting is selected (`/painting/style`), its WikiArt style category is bucketed into one of a small number of "scapes," each with its own pad synth, texture bed, and one-shot voice. Only a handful of scapes exist (not one per style) so each one can be a deliberately distinct sound world instead of a minor variation.

Switching scapes crossfades: the outgoing pad fades out and its group is freed, the incoming pad fades in, driven by `~switchScape` in `SC_mood_reactive.scd`.

Implementation lives in:
- [`calm_synthdefs.scd`](calm_synthdefs.scd) — the SynthDefs (pads, one-shot voices, noise beds)
- [`SC_mood_reactive.scd`](SC_mood_reactive.scd) — the OSC receiver, mood state, style→scape lookup, and crossfade logic

## Styles → scapes

Grounded in the specific movement ("Category" column) in `painting_selector/data/WikiArt-Emotions/WikiArt-Emotions-All.tsv` — 22 base categories, mapped below. All 22 are mapped now; anything unrecognized still defaults to `classical` as a safety net.

**Data note:** that TSV also has a broader "Style" column (only 4 values: Modern Art / Post Renaissance Art / Renaissance Art / Contemporary Art). `precompute.py` originally read "Style" instead of "Category" when building `paintings.pkl`, so nearly every painting's style resolved to "Modern Art" and silently fell back to `classical` regardless of the actual movement. Fixed in `precompute.py` (now prefers "Category"), and the already-built pickle was corrected in place with `painting_selector/patch_painting_styles.py` (no CLIP/GPU recompute needed — only the `style` string field changes).

**Multi-label styles:** some paintings carry two categories, comma-joined (e.g. `"Cubism,Expressionism"`, `"Rococo,Romanticism"`) — 24 such combinations exist across the dataset, so `paintings.pkl` actually contains 46 distinct style strings (22 single + 24 combos), not just 22. `~resolveScape` in `SC_mood_reactive.scd` handles this by splitting on the comma and using only the first label — checked against all 24 combos, every one resolves to a sensible scape this way (e.g. `Cubism,Expressionism` → `Cubism` → expressionist).

| WikiArt style | Scape |
|---|---|
| Realism | classical |
| Northern Renaissance | classical |
| Early Renaissance | classical |
| High Renaissance | classical |
| Baroque | classical |
| Rococo | classical |
| Romanticism | classical |
| Neoclassicism | classical |
| Expressionism | expressionist |
| Neo-Expressionism | expressionist |
| Cubism | expressionist |
| Surrealism | expressionist |
| Abstract Art | abstract |
| Abstract Expressionism | abstract |
| Minimalism | abstract |
| Color Field Painting | abstract |
| Lyrical Abstraction | abstract |
| Art Informel | abstract |
| Impressionism | impressionist |
| Post-Impressionism | impressionist |
| Magic Realism | impressionist |
| Pop Art | pop |

## What each scape sounds like

**`classical`** — warm and tonal:
- `shimmerPad` — a granular cloud of short sine grains (`GrainSin`) scattered around a warm major 7/9 chord, floaty and event-based rather than a sustained drone
- `calmNoise` — soft, filtered pink-noise texture bed
- `calmPluck` / `calmBell` — tuned plucked-string and FM-bell one-shots, scale switches major/minor with valence

**`expressionist`** — dissonant and unstable, using a different synthesis technique at every layer, not just different pitches:
- `glitchPad` — unstable FM tone (carrier/modulator ratio randomly steps via `LFNoise0`, never settles) plus bitcrushed noise bursts
- `tenseNoise` — grittier texture bed with jumpy filter motion and random amplitude bursts
- `tenseHit` — inharmonic, metallic noise-hits (not tuned notes — `freq` sets a resonance center, not a scale degree)
- All four expressionist voices share a manual bitcrush pass (`.round()` quantization + `Latch`/`Impulse` sample-and-hold — `Decimator` needs the sc3-plugins extension, not vanilla SuperCollider) as a consistent sonic fingerprint

**`abstract`** — sparse and near-static, evoking Minimalism/Color Field Painting's stillness:
- `driftPad` — additive drone: independent sine partials, each fading in/out on its own random slow schedule, no chord/notes/rhythm
- `driftHum` — near-silent, extremely slow-drifting "room tone"
- `driftTone` — soft sine swells (no percussive attack) triggered very rarely — this scape is mostly silence

**`impressionist`** — blurred, shimmering wash, using a whole-tone scale (the classic musical-Impressionism harmonic color):
- `hazeBank` — a fixed bank of resonant filters (`Klank`) rung by soft noise clicks, like struck glass/wind chimes, blurred by a huge reverb
- `hazeShimmer` — sparse high-frequency "twinkle" blips instead of a continuous noise sweep, like light on water
- `hazeBell` — two nearly-unison detuned sines with a soft swell, a natural "beating" shimmer rather than a clang

**`pop`** — bright, punchy, and rhythmic — the only scape with a clear steady beat, matching Pop Art's bold graphic energy:
- `popPulse` — a quantized, sequenced pulse-wave bassline (`Impulse.kr`-driven, not random) instead of a drone
- `popHat` — a steady hi-hat-like tick instead of atmospheric noise
- `popStab` — bright detuned-pulse stabs on a major pentatonic scale, fast punchy envelope

## Status

All 5 planned scapes built (`classical`, `expressionist`, `abstract`, `impressionist`, `pop`), covering all 22 WikiArt style categories. Not yet tuned by ear in SuperCollider — levels, timings, and frequency choices are first-pass and likely need adjustment once heard.
