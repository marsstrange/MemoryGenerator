# ParticlArt

An interactive installation where your face and your hands compose the room around a painting.
---

## What it is

A single webcam reads a visitor's facial expression and hand gestures in real time. Those
signals decide which painting from a 4,000+ work archive appears, how its pixels dissolve into
a living field of particles, and what generative soundscape fills the space around it — no
screen, no wall text, no controller.

It's designed for a gallery or museum context: a way to make a painting notice you back, and to
offer a small emotional journey through art history instead of a wall label.

- **Emotion in → painting out.** A 7-class facial emotion model (with continuous valence/arousal)
  is projected into the WikiArt Emotions dataset's 20-dimensional affective space, and the
  closest-matching, still-fresh, aesthetically-strong painting is selected via cosine similarity.
- **Gesture in → interaction out.** Swipes browse paintings and styles; thumbs up/down teach the
  system your taste (persisted across sessions); an "OK" sign toggles a mode where your hand
  stirs the painting into a particle cloud, scattering it on a push and pulling it back together
  on a retreat.
- **Everything out → sound + visuals.** The painting's style picks one of five fully distinct
  synthesised soundscapes; gestures and mood continuously shape both the sound and the particle
  system live, so the image and the audio move as one.

---

## How it works

Three programs run at once, talking only to each other over OSC on the loopback interface
(`127.0.0.1`) — nothing leaves the machine.

<img width="651" height="371" alt="diagram" src="https://github.com/user-attachments/assets/e3c3da8c-775d-4fd3-8550-a5d74146e7f0" />


1. **Sensing** — a webcam frame is captured (`emotion_recognition/camera.py`).
2. **Interpreting** — a Haar Cascade locates the primary face; a ResNet50-based two-head network
   (`emotion_recognition/train.py`) classifies 7 emotions and regresses continuous
   valence/arousal. MediaPipe's Hand Landmarker tracks 21 hand keypoints; hand-authored geometric
   rules turn those into static poses, swipes/waves/pushes, and continuous streams
   (`emotion_recognition/hand_gesture.py`).
3. **Deciding** — the averaged emotion probabilities are mapped into WikiArt's 20-dim emotion
   space and matched against the painting archive by cosine similarity, weighted by aesthetic
   rating, personal taste score, and a CLIP-embedding diversity penalty so paintings don't repeat
   or look too similar back-to-back (`painting_selector/selector.py`).
4. **Expressing** — every signal (emotion, valence/arousal, gestures, palm position, hand
   distance, painting metadata) streams out over OSC to Processing and SuperCollider, which react
   continuously and independently — see the module breakdown below.

### Emotion recognition

- ResNet50 backbone pretrained on ImageNet; only the last residual block and two new output
  heads are fine-tuned, keeping ImageNet's general visual features intact.
- Two heads share one 2048-d feature vector: a 7-class classifier (angry, disgust, fear, happy,
  neutral, sad, surprise) and a `Tanh`-bounded regression head for valence/arousal, trained
  against a fixed per-class target coordinate on the circumplex model of affect — so it learns to
  interpolate continuously between categories rather than only ever outputting one of seven fixed
  points.
- Trained on FER-2013-style data (`emotion_recognition/train.py`); the shipped checkpoint lives
  at `emotion_recognition/checkpoints/best_model.pth`.

### Gesture recognition

MediaPipe's pretrained Hand Landmarker is used off the shelf — no gesture-specific training.
Everything past the 21 keypoints it returns is hand-authored geometry: joint angles and
distances classify static poses; a short rolling window of palm position/hand size classifies
swipes, waves and pushes.

| Static poses | Dynamic gestures | Continuous streams |
| :--- | :--- | :--- |
| open, fist, thumbs up, thumbs down, OK, point, peace | swipe left/right/up/down, wave, push | palm X/Y, hand size, windowed hand-size delta, pinch, spread, wrist angle |

### Visuals — Processing (`painting_visualizer/painting_visualizer.pde`)

The selected painting is resampled into a field of colored particles, each carrying its source
pixel color and its own origin point. Idle, particles drift gently along the painting's own
brightness-gradient field plus a touch of Perlin-noise wander and Brownian jitter, so the image
never looks perfectly frozen. While particle-follow mode is on (toggled with the OK sign), the
palm steers particle direction, hand distance zooms the canvas, a fast approach scatters the
particles outward, and a fast retreat magnetizes them back into place.

### Sound — SuperCollider (`audio_playback/SC_mood_reactive.scd` + `calm_synthdefs.scd`)

Every synthesis path is generated, not sampled. Each painting style resolves to one of five
soundscapes, each with a genuinely different synthesis technique — not just a different scale on
the same patch:

| Style family | Synthesis approach |
| :--- | :--- |
| Classical | granular sine-grain cloud |
| Expressionist | unstable FM + bitcrush |
| Abstract | additive drone of independent partials |
| Impressionist | modal/resonant filter bank |
| Pop | rhythmic subtractive pulse bass |

Hand position and mood shape the sound continuously (palm height opens/closes a filter, hand
distance controls reverb size, valence/arousal steer the pad), and in particle mode, a push
triggers a synthesised "shatter" while a retreat triggers its literal time-reverse — a
synthesised "re-forming" sound, sustained for as long as the palm stays in that retreated
position.

---

## Setup

### 1. Python environment

```bash
pip install -r requirements.txt
```

Runs on CPU by default. If you have an NVIDIA GPU, install the CUDA build instead for a big
speedup — see the comment at the top of `requirements.txt`.

### 2. Emotion model

Either train your own or use the shipped checkpoint at
`emotion_recognition/checkpoints/best_model.pth`. To train from scratch:

1. Download [FER-2013](https://www.kaggle.com/datasets/msambare/fer2013) and unzip it into
   `emotion_recognition/data/` (see `emotion_recognition/README.md` for the expected folder
   layout).
2. `python emotion_recognition/train.py`
3. Best checkpoint is written to `emotion_recognition/checkpoints/best_model.pth`.

### 3. Painting archive

1. Download the [WikiArt Emotions](https://saifmohammad.com/WebPages/wikiartemotions.html)
   annotations into `painting_selector/data/WikiArt-Emotions/` (see
   `painting_selector/README.md` for the exact file layout expected).
2. `python painting_selector/download_images.py` — pulls ~4,000 paintings (~1–2 GB, a few
   minutes).
3. `python painting_selector/precompute.py` — computes each painting's 20-dim emotion vector and
   CLIP embedding, saving to `painting_selector/data/paintings.pkl` (~10–15 min).

### 4. SuperCollider and Processing

Both need to be installed (SuperCollider for the sound engine, Processing with the `oscP5`
library for the visuals — Sketch → Import Library → Add Library → search "oscP5"). You don't
need to launch either by hand: see **Running it** below.

---

## Running it

```bash
cd emotion_recognition
python camera.py
```

This single command:

- auto-launches SuperCollider in the background and boots `SC_mood_reactive.scd` (skipped if SC
  is already running);
- opens `painting_visualizer.pde` in the Processing IDE for you — **press Run inside Processing
  once it opens** (it isn't started automatically, to leave you in control of when the visual
  window appears);
- opens a debug camera window showing your face/hand tracking, current gesture, mode, and the
  selected painting's info.

### Keyboard controls (debug window)

| Key | Effect |
| :--- | :--- |
| `q` | Quit |
| `r` | Reset your learned taste profile (personal scores) |
| `d` | Toggle the debug overlay window |

### Gesture controls

| Gesture | Effect |
| :--- | :--- |
| thumbs up / thumbs down | Score the current painting up/down (5 s cooldown per gesture) |
| OK (held briefly) | Toggle particle-follow mode |
| swipe left / right | Previous / next painting *(swipe mode only)* |
| swipe up / down | Next / previous style — always lands on a different soundscape family too *(swipe mode only)* |
| push toward camera *(particle mode)* | Scatter the particles + synthesised "shatter" sound |
| retreat *(particle mode)* | Magnetize particles back together + the shatter sound's time-reverse |
| fist *(particle mode)* | Snap particles straight back to their origin |

Swipes are disabled while particle-follow mode is active, so the two gesture vocabularies never
collide.

---

## Project structure

```
MemoryGenerator/
├── emotion_recognition/    Python: webcam capture, emotion model, gesture recognition, OSC hub
├── painting_selector/      Painting archive + emotion-matching / diversity logic
├── painting_visualizer/    Processing sketch: painting → particle system
├── audio_playback/         SuperCollider: soundscape engine + SynthDefs
├── scripts/                Auto-launch scripts for SuperCollider / Processing
└── resources/              Diagrams and reference material
```

---

## Technology

- PyTorch (ResNet50-based emotion model with valence/arousal regression)
- OpenCV (face detection)
- MediaPipe (hand tracking)
- CLIP / HuggingFace Transformers (visual diversity embeddings)
- NumPy / pandas · WikiArt Emotions dataset
- SuperCollider (real-time generative synthesis)
- Processing + oscP5 (particle-system visuals)
- OSC via python-osc

**Concepts:** real-time computer vision, facial emotion recognition, gesture recognition,
content-based retrieval and cosine similarity, embedding-based diversity, audio–visual
synchronization, generative sound design, particle systems.

---

## Known limitations & possible next steps

- `wave`, `peace` and `point` are recognised but not yet mapped to any behaviour.
- Wrist rotation, pinch, and spread are broadcast over OSC but currently unused — free
  parameters for a future soundscape or visual layer.
- Gesture thresholds are hand-tuned; a per-visitor or per-lighting calibration pass would make
  recognition more robust across different rooms/cameras.
- The installation currently listens to one visitor at a time — multi-hand or multi-visitor
  input is the natural next step.

---

## Lessons learned

The hardest part was making four distinct tools — computer vision, a PyTorch emotion model,
SuperCollider, and Processing — behave as one coherent, real-time system over OSC. Designing
generative audio that doesn't feel chaotic, and mapping facial emotion into WikiArt's affective
space in a way that stays coherent, were the two toughest design problems. Continuous signals
(valence/arousal, windowed motion) turned out to make the installation feel far more alive than
discrete on/off states — and a large share of the eventual result came down to mapping and
tuning, not the underlying models themselves.
