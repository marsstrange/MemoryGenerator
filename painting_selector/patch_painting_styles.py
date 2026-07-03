"""
One-off fix for paintings.pkl generated before precompute.py's Style/Category bug fix.
Re-reads the specific movement ("Category") from the TSV and overwrites each painting's
"style" field in the existing pickle — no CLIP/GPU recompute needed.
Usage: python patch_painting_styles.py
"""

import os
import pickle
import pandas as pd

_HERE         = os.path.dirname(os.path.abspath(__file__))
EMOTIONS_TSV  = os.path.join(_HERE, "data", "WikiArt-Emotions", "WikiArt-Emotions-All.tsv")
PAINTINGS_PKL = os.path.join(_HERE, "data", "paintings.pkl")


def main():
    df = pd.read_csv(EMOTIONS_TSV, sep="\t")
    category_by_id = dict(zip(df["ID"], df["Category"]))

    with open(PAINTINGS_PKL, "rb") as f:
        paintings = pickle.load(f)

    patched = 0
    for pid, painting in paintings.items():
        category = category_by_id.get(pid)
        if category and painting["style"] != str(category):
            painting["style"] = str(category)
            patched += 1

    with open(PAINTINGS_PKL, "wb") as f:
        pickle.dump(paintings, f)

    styles = sorted(set(p["style"] for p in paintings.values() if p["style"]))
    print(f"Patched {patched} of {len(paintings)} paintings.")
    print(f"Styles ({len(styles)}): {', '.join(styles)}")


if __name__ == "__main__":
    main()
