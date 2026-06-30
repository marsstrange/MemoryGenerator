# MemoryGenerator — Sound Design Brief

## What the project does

The system watches a person through a webcam in real time.  
It detects their **face emotion** and **hand gestures**, and every 20 seconds selects a **WikiArt painting** that emotionally matches what the person has been feeling.  
Everything is sent over **OSC** so the sound system can react to all of it live.

---

## Setup (first time only)

### 1. Clone the repo
```
git clone https://github.com/marsstrange/MemoryGenerator.git
cd MemoryGenerator
```

### 2. Create Python environment
```
conda create -n uni python=3.11
conda activate uni
pip install -r requirements.txt
```
Alternative with pyenv: 

```
pyenv local 3.11.9
python -m venv uni
.\uni\Scripts\Activate.ps1
pip install -r requirements.txt
```

### 3. Download the WikiArt Emotions dataset
Go to https://saifmohammad.com/WebPages/wikiartemotions.html and download the annotations.  
Unzip and place so the folder looks like this:
```
painting_selector/data/WikiArt-Emotions/
    WikiArt-Emotions-All.tsv
    WikiArt-info.tsv
    WikiArt-annotations.csv
    ...
```

### 4. Download painting images (~1–2 GB, takes a few minutes)
```
cd painting_selector
python3 download_images.py
cd ..
```

For Windows: use $python$ instead od $python3$


### 5. Precompute emotion + CLIP embeddings (~10–15 min, runs on GPU/MPS if available) - NOT NEEDED ANYMORE (the result is already uploaded to the repo, paintings.pkg file)
```
cd painting_selector
python3 precompute.py
cd ..
```

### 6. Train the face emotion model (~20–30 min on Apple Silicon)
```
cd emotion_recognition
python3 train.py
cd ..
```
This saves `emotion_recognition/checkpoints/best_model.pth`.  
If Onur shares the `.pth` file directly, skip this step and place it at that path.

### 7. (Optional) Install Processing for visuals
Download Processing from https://processing.org/download  
Open `painting_visualizer/painting_visualizer.pde`  
Go to **Sketch → Import Library → Add Library** → search **oscP5** → Install  
Run the sketch.

---

## How to run it

```
conda activate uni
cd emotion_recognition
python3 camera.py
```

Two windows open:
- **Emotion Recognizer** — live camera with face/gesture overlay
- **Painting** — the currently selected painting (changes every 20 seconds)

The Processing sketch (`painting_visualizer/`) can also run alongside for generative visuals.  
The sound system connects to the same OSC stream.

---

## OSC — all messages

Everything is sent to **127.0.0.1 : 12000**.

---

### Face emotion

| Address | Type | Range / Values | Rate |
|---|---|---|---|
| `/emotion` | string | `angry` `disgust` `fear` `happy` `neutral` `sad` `surprise` | every frame |
| `/valence` | float | −1.0 → +1.0 | every frame |
| `/arousal` | float | −1.0 → +1.0 | every frame |

**Valence** = how positive or negative the emotion feels  
**Arousal** = how activated or calm the emotion feels

Emotion circumplex — where each label sits in V/A space:

| Emotion | Valence | Arousal | Character |
|---|---|---|---|
| `happy` | +0.9 | +0.5 | positive, moderately energetic |
| `surprise` | +0.1 | +0.9 | near-neutral, very high energy |
| `angry` | −0.8 | +0.8 | negative, high energy |
| `fear` | −0.7 | +0.7 | negative, high energy |
| `disgust` | −0.7 | +0.2 | negative, low-moderate energy |
| `sad` | −0.6 | −0.6 | negative, low energy |
| `neutral` | 0.0 | 0.0 | centre of the space |

Emotion is only sent when a face is detected in frame.

---

### Hand — continuous parameters

Sent every frame the hand is visible.

| Address | Type | Range | What it measures |
|---|---|---|---|
| `/palm_x` | float | 0.0 (left edge) → 1.0 (right edge) | horizontal hand position in frame |
| `/palm_y` | float | 0.0 (top edge) → 1.0 (bottom edge) | vertical hand position in frame |
| `/hand_size` | float | ~0.1 – 0.4 | how close the hand is to the camera |
| `/spread` | float | 0.0 – 1.0 | how spread out / open the fingers are |
| `/wrist_angle` | float | degrees | rotation of the wrist |

---

### Hand — static gestures

`/gesture` — sent every frame the hand is visible.

| Value | How to make it | Visual / system effect |
|---|---|---|
| `open` | all four fingers extended | used to start dynamic gestures |
| `fist` | all fingers curled | no system effect |
| `thumbs_up` | thumb pointing up, others curled | **+1.0 to painting score** (5 s cooldown) |
| `thumbs_down` | thumb pointing down, others curled | **−1.5 to painting score** (5 s cooldown) |
| `ok` | middle+ring+pinky up, thumb+index pinching | **+0.5 to painting score** (5 s cooldown) |
| `point` | index only extended | no system effect |
| `peace` | index + middle extended | no system effect |
| `unknown` | unrecognised pose | no system effect |

---

### Hand — dynamic gestures

`/dynamic` — fires briefly when the gesture is detected (open hand only, must start from the center of the frame).

| Value | Motion | Visual / system effect |
|---|---|---|
| `swipe_left` | fast move leftward | no default effect (free to use) |
| `swipe_right` | fast move rightward | no default effect (free to use) |
| `swipe_up` | fast move upward | **cycles to next art style** → new style name sent on `/style` |
| `swipe_down` | fast move downward | **cycles to previous art style** → new style name sent on `/style` |
| `wave` | hand oscillates left-right | no default effect (free to use) |
| `push` | hand moves quickly toward camera | no default effect (free to use) |

---

### Painting feedback

| Address | Type | Values | What triggered it |
|---|---|---|---|
| `/feedback` | string | `thumbs_up` `thumbs_down` `ok` | person reacted to the current painting |

Score is clamped to **−3.0 → +3.0** and resets to 0 each session.  
High-scored paintings are more likely to be selected again. Low-scored ones are avoided.

---

### Painting selection (fires every 20 seconds)

| Address | Type | What it contains |
|---|---|---|
| `/painting/path` | string | absolute file path to the painting image |
| `/painting/style` | string | art style e.g. `Impressionism`, `Surrealism` |
| `/painting/artist` | string | artist name |
| `/painting/title` | string | painting title |
| `/style` | string | fires immediately when person swipes up/down to change style |

The painting is chosen by matching the **average face emotion over the last 20 seconds** to the WikiArt emotion database. The last 20 shown paintings are excluded to prevent repeats. Paintings with higher personal score are ranked higher.

---

## What the visuals do (Processing sketch)

- **Painting window** — shows the selected painting as a full image, updates every 20 seconds
- **Processing sketch** — generative particle flow field over the painting:
  - Particles sample color directly from the painting pixels
  - `/arousal` controls particle speed and flow tightness
  - `/valence` controls flow direction — positive = smooth swirl, negative = chaotic
  - `/emotion` adds a color-tinted vignette glow (e.g. red for angry, yellow for happy, blue for sad)
- **Camera window overlay** — shows current artist/title, art style, score, and countdown to next painting

---

## Suggested mappings for sound

| Parameter | Sound idea |
|---|---|
| `/valence` + `/arousal` | overall mood of the soundscape — V/A maps directly to Russell's emotion circumplex |
| `/emotion` | switch between sound layers or timbres per emotion label |
| `/painting/style` | change musical mode or texture when a new painting style loads |
| `/painting/path` | trigger a new ambient layer when painting changes |
| `/feedback thumbs_up` | positive reinforcement sound |
| `/feedback thumbs_down` | negative / rejection sound |
| `/dynamic swipe_left` / `swipe_right` | trigger one-shot sound events |
| `/dynamic wave` | long textural sweep |
| `/dynamic push` | impact / accent sound |
| `/palm_x` | stereo panning |
| `/palm_y` | filter cutoff or pitch |
| `/hand_size` | reverb size / distance |
| `/spread` | harmonic richness / chord spread |
| `/wrist_angle` | LFO rate or modulation depth |