import os
import sys
import time
import platform
import subprocess
import cv2
import torch
import torch.nn as nn
from torchvision import transforms, models
from PIL import Image
import numpy as np
from pythonosc import udp_client
from hand_gesture import HandGestureDetector

# Painting selector lives one level up
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "painting_selector"))
try:
    from selector import PaintingSelector
    SELECTOR_AVAILABLE = True
except ImportError:
    SELECTOR_AVAILABLE = False

BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
CHECKPOINT = os.path.join(BASE_DIR, "checkpoints", "best_model.pth")
EMOTIONS   = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]
COLORS = {
    "angry":    (0,   0,   255),
    "disgust":  (0,   140, 255),
    "fear":     (128, 0,   128),
    "happy":    (0,   255, 0),
    "neutral":  (200, 200, 200),
    "sad":      (255, 100, 0),
    "surprise": (0,   255, 255),
}
VA_COORDS = {
    "angry":    (-0.8,  0.8),
    "disgust":  (-0.7,  0.2),
    "fear":     (-0.7,  0.7),
    "happy":    ( 0.9,  0.5),
    "neutral":  ( 0.0,  0.0),
    "sad":      (-0.6, -0.6),
    "surprise": ( 0.1,  0.9),
}

PAINTING_INTERVAL = 20.0  # seconds between painting switches
DEBUG_WINDOW = "Emotion Recognizer  |  Q to quit, D to toggle this window"

if torch.backends.mps.is_available():
    DEVICE = torch.device("mps")
elif torch.cuda.is_available():
    DEVICE = torch.device("cuda")
else:
    DEVICE = torch.device("cpu")

TRANSFORM = transforms.Compose([
    transforms.Grayscale(num_output_channels=3),
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
])


class EmotionModel(nn.Module):
    def __init__(self):
        super().__init__()
        backbone = models.resnet50(weights=None)
        self.features = nn.Sequential(*list(backbone.children())[:-1])
        feat_dim = 2048
        self.cls_head = nn.Sequential(
            nn.Dropout(0.4), nn.Linear(feat_dim, 256), nn.ReLU(),
            nn.Dropout(0.3), nn.Linear(256, 7),
        )
        self.va_head = nn.Sequential(
            nn.Dropout(0.3), nn.Linear(feat_dim, 64), nn.ReLU(),
            nn.Linear(64, 2), nn.Tanh(),
        )

    def forward(self, x):
        feat = self.features(x).flatten(1)
        return self.cls_head(feat), self.va_head(feat)


def load_model():
    model = EmotionModel()
    model.load_state_dict(torch.load(CHECKPOINT, map_location=DEVICE))
    model.eval()
    return model.to(DEVICE)


def predict(model, face_img):
    pil    = Image.fromarray(cv2.cvtColor(face_img, cv2.COLOR_BGR2RGB))
    tensor = TRANSFORM(pil).unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        cls_out, va_out = model(tensor)
        probs = torch.softmax(cls_out, dim=1)[0]
    idx     = probs.argmax().item()
    valence = va_out[0, 0].item()
    arousal = va_out[0, 1].item()
    return EMOTIONS[idx], probs[idx].item(), valence, arousal, probs.cpu().numpy()


def draw_va_plot(frame, valence, arousal, size=220, margin=12):
    fh, fw = frame.shape[:2]
    x0 = fw - size - margin
    y0 = fh - size - margin
    x1 = x0 + size
    y1 = y0 + size
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2

    overlay = frame.copy()
    cv2.rectangle(overlay, (x0 - 4, y0 - 4), (x1 + 4, y1 + 20), (15, 15, 15), -1)
    cv2.addWeighted(overlay, 0.65, frame, 0.35, 0, frame)

    for qx, qy, col in [
        (x0, y0, (30, 20, 20)), (cx, y0, (20, 30, 20)),
        (x0, cy, (20, 20, 30)), (cx, cy, (25, 25, 25)),
    ]:
        overlay2 = frame.copy()
        cv2.rectangle(overlay2, (qx, qy), (qx + size//2, qy + size//2), col, -1)
        cv2.addWeighted(overlay2, 0.3, frame, 0.7, 0, frame)

    cv2.line(frame, (x0, cy), (x1, cy), (70, 70, 70), 1)
    cv2.line(frame, (cx, y0), (cx, y1), (70, 70, 70), 1)
    cv2.putText(frame, "-V", (x0 + 2, cy - 4),  cv2.FONT_HERSHEY_SIMPLEX, 0.32, (90, 90, 90), 1)
    cv2.putText(frame, "+V", (x1 - 18, cy - 4), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (90, 90, 90), 1)
    cv2.putText(frame, "+A", (cx + 3, y0 + 11), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (90, 90, 90), 1)
    cv2.putText(frame, "-A", (cx + 3, y1 - 3),  cv2.FONT_HERSHEY_SIMPLEX, 0.32, (90, 90, 90), 1)

    def to_px(v, a):
        return int(cx + v * (size//2 - 8)), int(cy - a * (size//2 - 8))

    for emotion, (v, a) in VA_COORDS.items():
        ex, ey = to_px(v, a)
        col = COLORS[emotion]
        cv2.circle(frame, (ex, ey), 4, col, -1)
        cv2.putText(frame, emotion[:3], (ex + 5, ey + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.28, col, 1)

    px, py = to_px(valence, arousal)
    cv2.circle(frame, (px, py), 7, (255, 255, 255), -1)
    cv2.line(frame, (px - 10, py), (px + 10, py), (255, 255, 255), 1)
    cv2.line(frame, (px, py - 10), (px, py + 10), (255, 255, 255), 1)

    dists = sorted(VA_COORDS.items(), key=lambda e: (valence-e[1][0])**2 + (arousal-e[1][1])**2)
    cv2.putText(frame, "~  " + "  /  ".join(e for e, _ in dists[:2]),
                (x0, y1 + 16), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (200, 200, 200), 1)


def draw_painting_info(frame, painting, style, time_left, score=0.0):
    """Bottom-left overlay: current painting info + style + score + countdown."""
    fh = frame.shape[0]
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, fh - 88), (500, fh), (15, 15, 15), -1)
    cv2.addWeighted(overlay, 0.6, frame, 0.4, 0, frame)

    if painting:
        artist = painting.get("artist", "")[:30]
        title  = painting.get("title",  "")[:35]
        cv2.putText(frame, f"{artist} — {title}",
                    (8, fh - 64), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)

    score_color = (80, 220, 80) if score > 0 else (80, 80, 220) if score < 0 else (150, 150, 150)
    cv2.putText(frame, f"Style: {style}",
                (8, fh - 42), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (180, 220, 255), 1)
    cv2.putText(frame, f"score: {score:+.1f}",
                (8, fh - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.45, score_color, 1)
    cv2.putText(frame, f"next in {int(time_left)}s",
                (200, fh - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (120, 120, 120), 1)


SCRIPTS_DIR = os.path.join(BASE_DIR, "..", "scripts")


def _is_process_running(name):
    """Best-effort check so repeated camera.py runs don't stack up duplicate
    background processes. If the check itself fails for any reason, assume
    "not running" -- launching an extra instance is a lesser problem than a
    crash here preventing the app from starting at all."""
    try:
        if platform.system() == "Windows":
            out = subprocess.run(
                ["tasklist", "/FI", f"IMAGENAME eq {name}"],
                capture_output=True, text=True, timeout=5,
            )
            return name.lower() in out.stdout.lower()
        else:
            out = subprocess.run(["pgrep", "-x", name], capture_output=True, timeout=5)
            return out.returncode == 0
    except Exception:
        return False


def launch_supercollider():
    """Auto-starts the mood-reactive SC script for the current OS, so it doesn't
    have to be run by hand. Fire-and-forget: doesn't wait for it to boot -- any
    OSC messages sent before it's ready are just silently dropped, harmlessly."""
    system = platform.system()
    proc_name = "sclang.exe" if system == "Windows" else "sclang"

    if _is_process_running(proc_name):
        print("SuperCollider (sclang) already running -- skipping auto-launch.")
        return

    try:
        if system == "Windows":
            script = os.path.join(SCRIPTS_DIR, "run_supercollider.bat")
            subprocess.Popen(["cmd", "/c", script])
        elif system in ("Darwin", "Linux"):
            script = os.path.join(SCRIPTS_DIR, "run_supercollider.sh")
            subprocess.Popen(["bash", script])
        else:
            print(f"Unrecognized OS '{system}' -- start SuperCollider manually.")
            return
        print(f"Launching SuperCollider ({system}): {script}")
    except Exception as e:
        print(f"Could not auto-launch SuperCollider: {e}")


def launch_processing():
    """Auto-opens painting_visualizer.pde in the Processing IDE for the current OS,
    passing the file directly as an argument (doesn't rely on a .pde file-type
    association, which a portable Processing install often lacks). Does NOT auto-run
    it: press Run inside Processing yourself once it opens. Fire-and-forget, same as
    launch_supercollider()."""
    system = platform.system()

    try:
        if system == "Windows":
            script = os.path.join(SCRIPTS_DIR, "run_processing.bat")
            subprocess.Popen(["cmd", "/c", script])
        elif system in ("Darwin", "Linux"):
            script = os.path.join(SCRIPTS_DIR, "run_processing.sh")
            subprocess.Popen(["bash", script])
        else:
            print(f"Unrecognized OS '{system}' -- start Processing manually.")
            return
        print(f"Launching Processing sketch ({system}): {script}")
    except Exception as e:
        print(f"Could not auto-launch Processing: {e}")


def main():
    launch_supercollider()
    launch_processing()

    print(f"Device: {DEVICE}")
    print("Loading emotion model...")
    model = load_model()
    print("Model loaded.")

    # Painting selector (optional — skipped if not yet precomputed)
    selector = None
    if SELECTOR_AVAILABLE:
        paintings_db = os.path.join(BASE_DIR, "..", "painting_selector", "data", "paintings.pkl")
        if os.path.exists(paintings_db):
            try:
                selector = PaintingSelector()
                print(f"Selector loaded: {len(selector.ids)} paintings")
            except Exception as e:
                print(f"Selector failed to load: {e}")
        else:
            print(f"paintings.pkl not found at {paintings_db}")

    # Separate ports per receiver: two processes can't reliably share one UDP port
    # (whichever socket the OS delivers a packet to "wins," so both listening at once
    # means each side randomly drops messages meant for the other).
    osc_processing = udp_client.SimpleUDPClient("127.0.0.1", 12000)
    osc_sc         = udp_client.SimpleUDPClient("127.0.0.1", 12001)

    def send_osc(address, value):
        osc_processing.send_message(address, value)
        osc_sc.send_message(address, value)

    face_cascade  = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    hand_detector = HandGestureDetector()

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Cannot open camera.")
        return
    print("Camera open. Press Q to quit, D to toggle this debug window.")
    # WINDOW_NORMAL (not the default AUTOSIZE) so it can be resized/shrunk programmatically --
    # unlike AUTOSIZE, it doesn't auto-fit the image, so size it to the camera's native
    # resolution up front (otherwise it'd open at some small default size instead)
    cv2.namedWindow(DEBUG_WINDOW, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(DEBUG_WINDOW, int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))

    # State for painting selection
    probs_buffer      = []        # accumulate face probs over 20s window
    last_select_time  = time.time() - PAINTING_INTERVAL  # select immediately on first frame
    current_painting  = None
    last_static        = None
    last_dynamic       = None
    last_feedback_time = {}  # gesture → timestamp, 5s cooldown per gesture type
    show_debug = True  # toggled with 'd' -- painting_visualizer.pde shows the audience-facing
                        # visuals now, so this debug window can be hidden during an actual showing

    try:
      while True:
        ret, frame = cap.read()
        if not ret:
            break

        now      = time.time()
        elapsed  = now - last_select_time
        time_left = max(0.0, PAINTING_INTERVAL - elapsed)

        # ── face emotion ──────────────────────────────────────────────────────
        gray  = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))

        for (x, y, w, h) in faces:
            face_crop                      = frame[y:y+h, x:x+w]
            emotion, conf, V, A, probs_np  = predict(model, face_crop)
            color                          = COLORS[emotion]
            probs_buffer.append(probs_np)

            send_osc("/emotion",  emotion)
            send_osc("/valence",  float(V))
            send_osc("/arousal",  float(A))

            cv2.rectangle(frame, (x, y), (x+w, y+h), color, 2)
            label = f"{emotion}  {conf*100:.0f}%"
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
            cv2.rectangle(frame, (x, y - th - 10), (x + tw + 8, y), color, -1)
            cv2.putText(frame, label, (x + 4, y - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
            cv2.putText(frame, f"V {V:+.2f}  A {A:+.2f}", (x, y + h + 22),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 1)
            draw_va_plot(frame, V, A)

        # ── hand gesture ──────────────────────────────────────────────────────
        hand = hand_detector.detect(frame)
        if hand:
            static  = hand["static"]  or ""
            dynamic = hand["dynamic"] or ""

            send_osc("/gesture",     static  or "none")
            send_osc("/dynamic",     dynamic or "none")
            send_osc("/palm_x",      float(hand["palm_x"]))
            send_osc("/palm_y",      float(hand["palm_y"]))
            send_osc("/hand_size",   float(hand["hand_size"]))
            send_osc("/pinch",       float(hand["pinch"]))
            send_osc("/spread",      float(hand["spread"]))
            send_osc("/wrist_angle", float(hand["wrist_angle"]))

            cv2.putText(frame, f"gesture: {static}",  (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            cv2.putText(frame, f"dynamic: {dynamic}", (10, 58),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)

            if selector and current_painting:
                # Static gesture → feedback with 5s cooldown per gesture type
                if static != last_static and static in ("thumbs_up", "thumbs_down", "ok"):
                    if now - last_feedback_time.get(static, 0) >= 5.0:
                        selector.feedback(current_painting["id"], gesture=static)
                        send_osc("/feedback", static)
                        last_feedback_time[static] = now

                # Dynamic gesture → style navigation (once per gesture change)
                if dynamic != last_dynamic:
                    if dynamic == "swipe_up":
                        style = selector.next_style()
                        send_osc("/style", style)
                    elif dynamic == "swipe_down":
                        style = selector.prev_style()
                        send_osc("/style", style)

            last_static  = static
            last_dynamic = dynamic
        else:
            last_static  = None
            last_dynamic = None

        # ── painting selection every 20s ──────────────────────────────────────
        if selector and elapsed >= PAINTING_INTERVAL:
            # Use averaged probs over the window, fallback to neutral
            if probs_buffer:
                avg_probs = np.mean(probs_buffer, axis=0)
            else:
                avg_probs = np.ones(7) / 7.0

            try:
                current_painting = selector.select(avg_probs)
                print(f"Selected: {current_painting['artist']} — {current_painting['title']} "
                      f"[{current_painting['style']}]")
            except Exception as e:
                print(f"Select failed: {e}")
                current_painting = None
            if current_painting is None:
                last_select_time = now
                continue
            send_osc("/painting/path",   current_painting["path"])
            send_osc("/painting/style",  current_painting["style"])
            send_osc("/painting/artist", current_painting["artist"])
            send_osc("/painting/title",  current_painting["title"])

            probs_buffer     = []
            last_select_time = now

            # Show painting in separate window
            # -- disabled: painting_visualizer.pde now draws the painting itself as the
            # -- particle backdrop, so this separate Python window is redundant (one less
            # -- window on screen). Kept here in case Processing isn't running.
            # img = cv2.imread(current_painting["path"])
            # if img is not None:
            #     h, w = img.shape[:2]
            #     scale = 600 / max(h, w)
            #     img = cv2.resize(img, (int(w * scale), int(h * scale)))
            #     cv2.imshow("Painting", img)

        # ── painting info overlay ─────────────────────────────────────────────
        if selector:
            score = selector.personal_scores.get(current_painting["id"], 0.0) if current_painting else 0.0
            draw_painting_info(frame, current_painting, selector.current_style, time_left, score)

        # cv2.imshow("Emotion Recognizer  |  Q to quit", frame)
        # if cv2.waitKey(1) & 0xFF == ord("q"):
        #     break
        if show_debug:
            cv2.imshow(DEBUG_WINDOW, frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        elif key == ord("d"):
            # shrink to near-nothing rather than destroying the window: with zero cv2
            # windows open, waitKey can lose OS keyboard focus entirely, and there'd be
            # no way to press 'd' (or even 'q') again
            show_debug = not show_debug
            if show_debug:
                cv2.resizeWindow(DEBUG_WINDOW, frame.shape[1], frame.shape[0])
            else:
                cv2.resizeWindow(DEBUG_WINDOW, 1, 1)
    finally:
      # runs on normal quit, an exception, or Ctrl+C — tells SC to stop the sound
      osc_sc.send_message("/shutdown", 1)

      if selector:
          selector.save_scores()

      cap.release()
      cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
