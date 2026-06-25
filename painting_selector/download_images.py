"""
Downloads WikiArt painting images listed in WikiArt-info.tsv.
Images are saved to data/images/<ID>.jpg
Run once before training.
"""

import os
import time
import requests
import pandas as pd
from tqdm import tqdm

INFO_FILE = "./data/WikiArt-Emotions/WikiArt-info.tsv"
OUT_DIR   = "./data/images"

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    df = pd.read_csv(INFO_FILE, sep="\t")
    print(f"{len(df)} paintings to download")

    session = requests.Session()
    session.headers.update({"User-Agent": "Mozilla/5.0"})

    failed = []
    for _, row in tqdm(df.iterrows(), total=len(df)):
        img_id  = row["ID"]
        url     = row["Image URL"]
        out_path = os.path.join(OUT_DIR, f"{img_id}.jpg")

        if os.path.exists(out_path):
            continue

        try:
            r = session.get(url, timeout=15)
            if r.status_code == 200:
                with open(out_path, "wb") as f:
                    f.write(r.content)
            else:
                failed.append((img_id, url, r.status_code))
            time.sleep(0.1)  # be polite
        except Exception as e:
            failed.append((img_id, url, str(e)))

    print(f"\nDone. Downloaded to {OUT_DIR}")
    if failed:
        print(f"{len(failed)} failed:")
        for item in failed[:10]:
            print(" ", item)

if __name__ == "__main__":
    main()
