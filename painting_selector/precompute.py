"""
Run once after downloading images.
Builds data/paintings.pkl — emotion vectors + CLIP embeddings for all paintings.
Usage: python precompute.py
"""

import os
import pickle
import numpy as np
import pandas as pd
import torch
from PIL import Image
from tqdm import tqdm
from transformers import CLIPProcessor, CLIPModel

_HERE        = os.path.dirname(os.path.abspath(__file__))
EMOTIONS_TSV = os.path.join(_HERE, "data", "WikiArt-Emotions", "WikiArt-Emotions-All.tsv")
INFO_TSV     = os.path.join(_HERE, "data", "WikiArt-Emotions", "WikiArt-info.tsv")
IMG_DIR      = os.path.join(_HERE, "data", "images")
OUT_FILE     = os.path.join(_HERE, "data", "paintings.pkl")
CLIP_MODEL   = "openai/clip-vit-base-patch32"
BATCH_SIZE   = 32

EMOTION_COLS = [
    "ImageOnly: agreeableness", "ImageOnly: anger", "ImageOnly: anticipation",
    "ImageOnly: arrogance",     "ImageOnly: disagreeableness", "ImageOnly: disgust",
    "ImageOnly: fear",          "ImageOnly: gratitude",        "ImageOnly: happiness",
    "ImageOnly: humility",      "ImageOnly: love",             "ImageOnly: optimism",
    "ImageOnly: pessimism",     "ImageOnly: regret",           "ImageOnly: sadness",
    "ImageOnly: shame",         "ImageOnly: shyness",          "ImageOnly: surprise",
    "ImageOnly: trust",         "ImageOnly: neutral",
]


def main():
    if torch.backends.mps.is_available():
        device = torch.device("mps")
    elif torch.cuda.is_available():
        device = torch.device("cuda")
    else:
        device = torch.device("cpu")

    print(f"Device: {device}")
    print("Loading CLIP model...")
    clip_model = CLIPModel.from_pretrained(CLIP_MODEL).to(device)
    processor  = CLIPProcessor.from_pretrained(CLIP_MODEL)
    clip_model.eval()

    df = pd.read_csv(EMOTIONS_TSV, sep="\t")

    # Normalise art rating to [0, 1]
    df["ave_art_rating"] = pd.to_numeric(df["Ave. art rating"], errors="coerce").fillna(3.0)
    rmin, rmax = df["ave_art_rating"].min(), df["ave_art_rating"].max()
    df["ave_art_rating"] = (df["ave_art_rating"] - rmin) / (rmax - rmin + 1e-6)

    # Keep only rows with downloaded images
    df = df[df["ID"].apply(lambda x: os.path.exists(os.path.join(IMG_DIR, x + ".jpg")))]
    print(f"Found {len(df)} paintings with images")

    paintings = {}

    # Process in batches for CLIP efficiency
    rows  = list(df.iterrows())
    for batch_start in tqdm(range(0, len(rows), BATCH_SIZE), desc="Embedding"):
        batch = rows[batch_start: batch_start + BATCH_SIZE]
        imgs, valid_rows = [], []

        for _, row in batch:
            path = os.path.join(IMG_DIR, row["ID"] + ".jpg")
            try:
                imgs.append(Image.open(path).convert("RGB"))
                valid_rows.append(row)
            except Exception:
                continue

        if not imgs:
            continue

        inputs = processor(images=imgs, return_tensors="pt", padding=True).to(device)
        with torch.no_grad():
            vision_out = clip_model.vision_model(pixel_values=inputs["pixel_values"])
            feats      = clip_model.visual_projection(vision_out.pooler_output)
            feats      = feats / feats.norm(dim=-1, keepdim=True)
            feats      = feats.cpu().numpy()

        for i, row in enumerate(valid_rows):
            emo_vec = np.array([float(row[c]) for c in EMOTION_COLS], dtype=np.float32)
            norm    = np.linalg.norm(emo_vec)
            emo_vec = emo_vec / norm if norm > 1e-6 else emo_vec

            paintings[row["ID"]] = {
                "path":           os.path.join(IMG_DIR, row["ID"] + ".jpg"),
                "style":          str(row.get("Style", row.get("Category", ""))),
                "artist":         str(row.get("Artist", "")),
                "title":          str(row.get("Title",  "")),
                "year":           str(row.get("Year",   "")),
                "ave_art_rating": float(row["ave_art_rating"]),
                "emotion_vec":    emo_vec,
                "clip_emb":       feats[i].astype(np.float32),
            }

    with open(OUT_FILE, "wb") as f:
        pickle.dump(paintings, f)

    print(f"\nSaved {len(paintings)} paintings → {OUT_FILE}")
    styles = sorted(set(p["style"] for p in paintings.values() if p["style"]))
    print(f"Styles ({len(styles)}): {', '.join(styles)}")


if __name__ == "__main__":
    main()
