import os
import json
import pickle
import numpy as np

_HERE          = os.path.dirname(os.path.abspath(__file__))
PAINTINGS_FILE = os.path.join(_HERE, "data", "paintings.pkl")
SCORES_FILE    = os.path.join(_HERE, "data", "personal_scores.json")

FACE_EMOTIONS = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]

EMOTIONS_20 = [
    "agreeableness", "anger", "anticipation", "arrogance", "disagreeableness",
    "disgust", "fear", "gratitude", "happiness", "humility", "love", "optimism",
    "pessimism", "regret", "sadness", "shame", "shyness", "surprise", "trust", "neutral",
]

# Maps each of the 7 face emotions to weighted contributions in the 20-dim WikiArt space
FACE_TO_WIKI = {
    "angry":    {"anger": 1.0, "disagreeableness": 0.3},
    "disgust":  {"disgust": 1.0, "disagreeableness": 0.5},
    "fear":     {"fear": 1.0, "anticipation": 0.2},
    "happy":    {"happiness": 1.0, "optimism": 0.4, "love": 0.2, "gratitude": 0.2},
    "neutral":  {"neutral": 1.0, "trust": 0.1},
    "sad":      {"sadness": 1.0, "pessimism": 0.4, "regret": 0.3},
    "surprise": {"surprise": 1.0, "anticipation": 0.5},
}

DIVERSITY_WEIGHT       = 0.3   # how much to penalise visually similar recent paintings
STYLE_DIVERSITY_WEIGHT = 0.4   # how much to penalise repeating a recently-shown style
HISTORY_SIZE     = 20    # how many recent paintings to exclude
TOP_K            = 50    # candidates from emotion matching before diversity re-rank
TEMPERATURE      = 0.3   # sampling temperature: lower = closer to argmax, higher = more random


class PaintingSelector:

    def __init__(self):
        print("Loading painting database...")
        with open(PAINTINGS_FILE, "rb") as f:
            self.paintings = pickle.load(f)

        self.ids = list(self.paintings.keys())

        # Pre-stack matrices for fast numpy ops
        self.emo_matrix  = np.stack([self.paintings[i]["emotion_vec"] for i in self.ids])  # (N, 20)
        self.clip_matrix = np.stack([self.paintings[i]["clip_emb"]    for i in self.ids])  # (N, 512)
        self.art_ratings = np.array([self.paintings[i]["ave_art_rating"] for i in self.ids])

        # Style list — "All" + sorted unique styles
        self.styles    = ["All"] + sorted(set(p["style"] for p in self.paintings.values() if p["style"]))
        self.style_idx = 0

        self.personal_scores = {}

        self.history          = []   # recently shown painting IDs
        self.current_painting = None

        print(f"Loaded {len(self.ids)} paintings, {len(self.styles)-1} styles")

    # ── style navigation ──────────────────────────────────────────────────────

    @property
    def current_style(self):
        return self.styles[self.style_idx]

    def next_style(self):
        self.style_idx = (self.style_idx + 1) % len(self.styles)
        return self.current_style

    def prev_style(self):
        self.style_idx = (self.style_idx - 1) % len(self.styles)
        return self.current_style

    # ── face probs → 20-dim emotion vector ───────────────────────────────────

    def face_to_vector(self, probs):
        """probs: 7-element array (softmax over angry/disgust/fear/happy/neutral/sad/surprise)"""
        vec = np.zeros(20, dtype=np.float32)
        for i, emotion in enumerate(FACE_EMOTIONS):
            for wiki_emo, weight in FACE_TO_WIKI[emotion].items():
                vec[EMOTIONS_20.index(wiki_emo)] += probs[i] * weight
        norm = np.linalg.norm(vec)
        return vec / norm if norm > 1e-6 else vec

    # ── selection ─────────────────────────────────────────────────────────────

    def select(self, face_probs):
        """
        face_probs: 7-element array from face model softmax
        Returns a dict with id, path, style, artist, title, year
        """
        face_vec = self.face_to_vector(face_probs)

        # Style mask
        if self.current_style == "All":
            mask = np.ones(len(self.ids), dtype=bool)
        else:
            mask = np.array([self.paintings[i]["style"] == self.current_style for i in self.ids])

        # Exclude recently shown paintings
        recent = set(self.history[-HISTORY_SIZE:])
        exclude = np.array([self.ids[i] in recent for i in range(len(self.ids))])
        mask = mask & ~exclude

        indices = np.where(mask)[0]
        if len(indices) == 0:  # fallback: ignore history but keep style
            indices = np.where(~exclude)[0]
        if len(indices) == 0:  # fallback: ignore everything
            indices = np.arange(len(self.ids))

        # Emotion similarity (cosine — vectors are pre-normalised)
        emo_sims = self.emo_matrix[indices] @ face_vec

        # Quality weight: art rating scaled by personal score
        personal  = np.array([self.personal_scores.get(self.ids[i], 0.0) for i in indices])
        quality   = np.clip(self.art_ratings[indices] + personal * 0.2, 0.01, None)
        quality  /= quality.max()

        candidate_scores = emo_sims * quality

        # Top-K candidates by emotion+quality
        k         = min(TOP_K, len(indices))
        top_local = np.argpartition(candidate_scores, -k)[-k:]
        top_idx   = indices[top_local]

        # CLIP diversity penalty against recent history
        if self.history:
            hist_embs    = np.stack([
                self.paintings[hid]["clip_emb"]
                for hid in self.history[-HISTORY_SIZE:]
                if hid in self.paintings
            ])
            clip_sims    = self.clip_matrix[top_idx] @ hist_embs.T  # (k, hist)
            clip_penalty = clip_sims.max(axis=1)
        else:
            clip_penalty = np.zeros(k)

        # Style diversity penalty — fraction of recent history sharing this candidate's
        # style. Complements the CLIP penalty above: CLIP only catches paintings that
        # *look* alike, so a different-looking painting from the same recently-dominant
        # movement would otherwise sail through unpenalised.
        if self.history:
            recent_styles = [
                self.paintings[hid]["style"]
                for hid in self.history[-HISTORY_SIZE:]
                if hid in self.paintings
            ]
            top_styles    = [self.paintings[self.ids[i]]["style"] for i in top_idx]
            style_penalty = np.array([
                recent_styles.count(s) / len(recent_styles) if recent_styles else 0.0
                for s in top_styles
            ])
        else:
            style_penalty = np.zeros(k)

        final_scores = (
            candidate_scores[top_local]
            - DIVERSITY_WEIGHT * clip_penalty
            - STYLE_DIVERSITY_WEIGHT * style_penalty
        )
        # Weighted random sampling so lower-ranked paintings still get shown
        shifted = final_scores - final_scores.max()
        weights = np.exp(shifted / TEMPERATURE)
        weights /= weights.sum()
        best_local = np.random.choice(len(weights), p=weights)
        best_id    = self.ids[top_idx[best_local]]

        self.history.append(best_id)
        if len(self.history) > HISTORY_SIZE * 2:
            self.history = self.history[-HISTORY_SIZE:]

        self.current_painting = best_id
        p = self.paintings[best_id]
        return {
            "id":     best_id,
            "path":   p["path"],
            "style":  p["style"],
            "artist": p["artist"],
            "title":  p["title"],
            "year":   p["year"],
        }

    # ── feedback ──────────────────────────────────────────────────────────────

    def feedback(self, painting_id, gesture=None, seconds_shown=0):
        """
        gesture: "thumbs_up", "thumbs_down", "ok", or None (passive timeout)
        seconds_shown: how long the painting was displayed
        """
        if painting_id not in self.paintings:
            return
        score = self.personal_scores.get(painting_id, 0.0)
        if gesture == "thumbs_up":
            score += 1.0
        elif gesture == "thumbs_down":
            score -= 1.5
        elif gesture == "ok":
            score += 0.5
        elif gesture is None and seconds_shown >= 20:
            score += 0.2
        self.personal_scores[painting_id] = max(-3.0, min(3.0, score))

    def save_scores(self):
        os.makedirs(os.path.dirname(SCORES_FILE), exist_ok=True)
        with open(SCORES_FILE, "w") as f:
            json.dump(self.personal_scores, f, indent=2)
        print("Scores saved.")
