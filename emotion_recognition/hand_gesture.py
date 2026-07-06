import math
import time
import os
import urllib.request
import cv2
from collections import deque
import mediapipe as mp
from mediapipe.tasks import python as tasks_python
from mediapipe.tasks.python.vision import HandLandmarker, HandLandmarkerOptions, RunningMode

MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hand_landmarker.task")
MODEL_URL  = ("https://storage.googleapis.com/mediapipe-models/"
              "hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task")

HAND_CONNECTIONS = [
    (0,1),(1,2),(2,3),(3,4),
    (5,6),(6,7),(7,8),
    (9,10),(10,11),(11,12),
    (13,14),(14,15),(15,16),
    (17,18),(18,19),(19,20),
    (0,5),(5,9),(9,13),(13,17),(0,17),
]


def _ensure_model():
    if not os.path.exists(MODEL_PATH):
        print("Downloading hand_landmarker.task model (~8 MB)...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        print("Model downloaded.")


class HandGestureDetector:

    def __init__(self, max_hands=1, history_len=20):
        _ensure_model()
        options = HandLandmarkerOptions(
            base_options=tasks_python.BaseOptions(model_asset_path=MODEL_PATH),
            running_mode=RunningMode.VIDEO,
            num_hands=max_hands,
            min_hand_detection_confidence=0.7,
            min_hand_presence_confidence=0.6,
            min_tracking_confidence=0.6,
        )
        self._landmarker = HandLandmarker.create_from_options(options)
        self._t0         = time.monotonic()
        self._pos_hist   = deque(maxlen=history_len)
        self._size_hist  = deque(maxlen=history_len)
        self._last_dyn   = None
        self._dyn_ttl    = 0

    # ── helpers ────────────────────────────────────────────────────────────

    @staticmethod
    def _joint_angle(a, b, c):
        """Angle at b formed by a→b←c, in degrees."""
        v1x, v1y = a.x - b.x, a.y - b.y
        v2x, v2y = c.x - b.x, c.y - b.y
        dot = v1x * v2x + v1y * v2y
        mag = math.hypot(v1x, v1y) * math.hypot(v2x, v2y)
        if mag < 1e-6:
            return 0.0
        return math.degrees(math.acos(max(-1.0, min(1.0, dot / mag))))

    def _finger_states(self, lm, handedness):
        """[thumb, index, middle, ring, pinky]  True = extended."""
        # Thumb: MCP joint (lm[2]) angle between CMC(1) and IP(3) — straight when extended
        thumb = self._joint_angle(lm[1], lm[2], lm[3]) > 120
        rest  = [lm[tip].y < lm[pip].y for tip, pip in [(8,6),(12,10),(16,14),(20,18)]]
        return [thumb] + rest

    def _palm_center(self, lm):
        pts = [lm[i] for i in [0, 5, 9, 13, 17]]
        return sum(p.x for p in pts) / 5, sum(p.y for p in pts) / 5

    def _hand_size(self, lm):
        xs = [p.x for p in lm]; ys = [p.y for p in lm]
        return (max(xs) - min(xs)) * (max(ys) - min(ys))

    def _pinch_dist(self, lm):
        return math.hypot(lm[4].x - lm[8].x, lm[4].y - lm[8].y)

    def _finger_spread(self, lm):
        tips = [lm[i] for i in [4, 8, 12, 16, 20]]
        return sum(math.hypot(tips[i].x - tips[i+1].x, tips[i].y - tips[i+1].y)
                   for i in range(len(tips) - 1))

    def _wrist_angle(self, lm):
        return math.degrees(math.atan2(lm[9].y - lm[0].y, lm[9].x - lm[0].x))

    # ── static classification ──────────────────────────────────────────────

    def _static(self, fingers, lm):
        thumb, index, middle, ring, pinky = fingers
        if index and middle and ring and pinky:                 return "open"
        if thumb and not index and not middle and not ring and not pinky:
            # Confirm tip is genuinely away from the palm (not curled across fist)
            tip_to_palm = math.hypot(lm[4].x - lm[9].x, lm[4].y - lm[9].y)
            palm_width  = math.hypot(lm[5].x - lm[17].x, lm[5].y - lm[17].y)
            if tip_to_palm > palm_width * 0.7:
                return "thumbs_up" if lm[4].y < lm[0].y else "thumbs_down"
        if not index and not middle and not ring and not pinky: return "fist"

        # ok: index curled to touch thumb tip, middle+ring+pinky extended
        if middle and ring and pinky and not index:
            pinch   = math.hypot(lm[4].x - lm[8].x, lm[4].y - lm[8].y)
            palm_w  = math.hypot(lm[5].x - lm[17].x, lm[5].y - lm[17].y)
            if pinch < palm_w * 0.35:
                return "ok"

        if index and not middle and not ring and not pinky:           return "point"
        if index and middle and not ring and not pinky:               return "peace"
        if thumb and not index and not middle and not ring and pinky: return "thumbs_up"

        return "unknown"

    # ── dynamic classification ─────────────────────────────────────────────

    def _dynamic(self, px, py, size, static):
        # Propagate active gesture TTL regardless of hand state
        if self._dyn_ttl > 0:
            self._dyn_ttl -= 1
            return self._last_dyn

        # Only track open hand
        if static != "open":
            self._pos_hist.clear()
            self._size_hist.clear()
            return None

        # New sequence must begin near frame center
        near_center = abs(px - 0.5) < 0.25 and abs(py - 0.5) < 0.25
        if not self._pos_hist and not near_center:
            return None

        self._pos_hist.append((px, py))
        self._size_hist.append(size)

        if len(self._pos_hist) < 15:
            return None

        xs = [p[0] for p in self._pos_hist]
        ys = [p[1] for p in self._pos_hist]
        dx = xs[-1] - xs[0]
        dy = ys[-1] - ys[0]

        changes = sum(1 for i in range(1, len(xs)-1)
                      if (xs[i]-xs[i-1]) * (xs[i+1]-xs[i]) < 0)
        if changes >= 5 and max(xs) - min(xs) > 0.25:
            return self._emit("wave")

        if abs(dx) > 0.18 and abs(dx) > abs(dy) * 1.8:
            return self._emit("swipe_right" if dx > 0 else "swipe_left")

        if abs(dy) > 0.18 and abs(dy) > abs(dx) * 1.8:
            return self._emit("swipe_down" if dy > 0 else "swipe_up")

        if len(self._size_hist) >= 15:
            if self._size_hist[-1] - self._size_hist[0] > 0.08:
                return self._emit("push")

        return None

    def _emit(self, gesture):
        self._last_dyn = gesture
        self._dyn_ttl  = 15
        self._pos_hist.clear()
        self._size_hist.clear()
        return gesture

    # ── main entry ─────────────────────────────────────────────────────────

    def detect(self, frame):
        """Process frame in-place (draws landmarks). Returns dict or None."""
        rgb      = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        ts_ms    = int((time.monotonic() - self._t0) * 1000)
        result   = self._landmarker.detect_for_video(mp_image, ts_ms)

        if not result.hand_landmarks:
            self._pos_hist.clear()
            self._size_hist.clear()
            self._dyn_ttl = 0
            return None

        lm  = result.hand_landmarks[0]
        hnd = result.handedness[0][0].category_name  # "Left" or "Right"

        # Draw skeleton on frame
        h, w = frame.shape[:2]
        pts = [(int(l.x * w), int(l.y * h)) for l in lm]
        for (a, b) in HAND_CONNECTIONS:
            cv2.line(frame, pts[a], pts[b], (80, 200, 80), 2)
        for pt in pts:
            cv2.circle(frame, pt, 4, (255, 255, 255), -1)

        fingers = self._finger_states(lm, hnd)
        px, py  = self._palm_center(lm)
        size    = self._hand_size(lm)
        static  = self._static(fingers, lm)

        return {
            "static":      static,
            "dynamic":     self._dynamic(px, py, size, static),
            "palm_x":      px,
            "palm_y":      py,
            "hand_size":   size,
            "pinch":       self._pinch_dist(lm),
            "spread":      self._finger_spread(lm),
            "wrist_angle": self._wrist_angle(lm),
            "fingers":     fingers,
            "handedness":  hnd,
        }
