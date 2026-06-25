# Painting Selector

Selects paintings based on face emotion using WikiArt Emotions dataset.
Matches using 20-dim emotion vectors + CLIP visual diversity.

## Setup

### 1. Download the WikiArt Emotions dataset
Go to https://saifmohammad.com/WebPages/wikiartemotions.html and download the annotations.
Place the files so the structure looks like:

```
painting_selector/data/WikiArt-Emotions/
    WikiArt-Emotions-All.tsv
    WikiArt-info.tsv
    WikiArt-annotations.csv
    README.txt
```

### 2. Download painting images
```bash
python download_images.py
```
Downloads ~4000 paintings from WikiArt (~1-2 GB). Takes a few minutes.

### 3. Precompute embeddings
```bash
pip install transformers
python precompute.py
```
Computes 20-dim emotion vectors and CLIP embeddings for all paintings.
Saves to `data/paintings.pkl`. Takes ~10-15 min on Apple Silicon.

### 4. Run
```bash
cd ../emotion_recognition
python camera.py
```

## How it works

- Every 20 seconds, face emotion probabilities (7 classes) are averaged over the window and mapped to WikiArt's 20-dim emotion space
- Top-20 emotionally matching paintings are found via cosine similarity
- A CLIP diversity penalty removes paintings visually similar to recently shown ones
- Paintings are weighted by aesthetic quality (`Ave. art rating`) + personal score from gesture feedback

## Gesture controls

| Gesture | Effect |
|---|---|
| thumbs_up | +score for current painting |
| thumbs_down | -score for current painting |
| ok | small +score |
| swipe_up | next art style |
| swipe_down | previous style |

Personal scores persist in `data/personal_scores.json`.
