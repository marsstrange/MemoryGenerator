import os
import cv2
import torch
import torch.nn as nn
from torchvision import transforms, models
from PIL import Image
import numpy as np
from pythonosc import udp_client
from hand_gesture import HandGestureDetector

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

# VA coordinates for each emotion — used for the 2D plot overlay
VA_COORDS = {
    "angry":    (-0.8,  0.8),
    "disgust":  (-0.7,  0.2),
    "fear":     (-0.7,  0.7),
    "happy":    ( 0.9,  0.5),
    "neutral":  ( 0.0,  0.0),
    "sad":      (-0.6, -0.6),
    "surprise": ( 0.1,  0.9),
}

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
    """ResNet50 + two heads: classification and VA regression."""
    def __init__(self):
        super().__init__()
        backbone = models.resnet50(weights=None)
        self.features = nn.Sequential(*list(backbone.children())[:-1])
        feat_dim = 2048
        self.cls_head = nn.Sequential(
            nn.Dropout(0.4),
            nn.Linear(feat_dim, 256),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(256, 7),
        )
        self.va_head = nn.Sequential(
            nn.Dropout(0.3),
            nn.Linear(feat_dim, 64),
            nn.ReLU(),
            nn.Linear(64, 2),
            nn.Tanh(),
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
    idx      = probs.argmax().item()
    valence  = va_out[0, 0].item()
    arousal  = va_out[0, 1].item()
    return EMOTIONS[idx], probs[idx].item(), valence, arousal


def draw_va_plot(frame, valence, arousal, size=220, margin=12):
    fh, fw = frame.shape[:2]
    x0 = fw - size - margin
    y0 = fh - size - margin
    x1 = x0 + size
    y1 = y0 + size
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2

    # Semi-transparent background
    overlay = frame.copy()
    cv2.rectangle(overlay, (x0 - 4, y0 - 4), (x1 + 4, y1 + 20), (15, 15, 15), -1)
    cv2.addWeighted(overlay, 0.65, frame, 0.35, 0, frame)

    # Quadrant shading (subtle)
    for qx, qy, col in [
        (x0, y0, (30, 20, 20)),   # top-left:  negative + excited
        (cx, y0, (20, 30, 20)),   # top-right: positive + excited
        (x0, cy, (20, 20, 30)),   # bot-left:  negative + calm
        (cx, cy, (25, 25, 25)),   # bot-right: positive + calm
    ]:
        overlay2 = frame.copy()
        cv2.rectangle(overlay2, (qx, qy), (qx + size//2, qy + size//2), col, -1)
        cv2.addWeighted(overlay2, 0.3, frame, 0.7, 0, frame)

    # Grid lines
    cv2.line(frame, (x0, cy), (x1, cy), (70, 70, 70), 1)
    cv2.line(frame, (cx, y0), (cx, y1), (70, 70, 70), 1)

    # Axis labels
    cv2.putText(frame, "-V",    (x0 + 2, cy - 4),  cv2.FONT_HERSHEY_SIMPLEX, 0.32, (90, 90, 90), 1)
    cv2.putText(frame, "+V",    (x1 - 18, cy - 4), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (90, 90, 90), 1)
    cv2.putText(frame, "+A",    (cx + 3, y0 + 11), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (90, 90, 90), 1)
    cv2.putText(frame, "-A",    (cx + 3, y1 - 3),  cv2.FONT_HERSHEY_SIMPLEX, 0.32, (90, 90, 90), 1)

    def to_px(v, a):
        px = int(cx + v * (size // 2 - 8))
        py = int(cy - a * (size // 2 - 8))  # flip: up = higher arousal
        return px, py

    # Emotion reference dots
    for emotion, (v, a) in VA_COORDS.items():
        ex, ey = to_px(v, a)
        col = COLORS[emotion]
        cv2.circle(frame, (ex, ey), 4, col, -1)
        cv2.putText(frame, emotion[:3], (ex + 5, ey + 4),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.28, col, 1)

    # Current VA point
    px, py = to_px(valence, arousal)
    cv2.circle(frame, (px, py), 7, (255, 255, 255), -1)
    cv2.line(frame, (px - 10, py), (px + 10, py), (255, 255, 255), 1)
    cv2.line(frame, (px, py - 10), (px, py + 10), (255, 255, 255), 1)

    # Closest 2 emotions by Euclidean distance in VA space
    dists = sorted(VA_COORDS.items(), key=lambda e: (valence - e[1][0])**2 + (arousal - e[1][1])**2)
    closest_label = "~  " + "  /  ".join(e for e, _ in dists[:2])
    cv2.putText(frame, closest_label, (x0, y1 + 16),
                cv2.FONT_HERSHEY_SIMPLEX, 0.38, (200, 200, 200), 1)


def main():
    print(f"Device: {DEVICE}")
    print("Loading model...")
    model = load_model()
    print("Model loaded.")

    osc          = udp_client.SimpleUDPClient("127.0.0.1", 12000)
    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    hand_detector = HandGestureDetector()

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Cannot open camera.")
        return

    print("Camera open. Press Q to quit.")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        gray  = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        faces = face_cascade.detectMultiScale(
            gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))

        for (x, y, w, h) in faces:
            face_crop             = frame[y:y+h, x:x+w]
            emotion, conf, V, A   = predict(model, face_crop)
            color                 = COLORS[emotion]

            # Send emotion label + continuous VA over OSC
            osc.send_message("/emotion",  emotion)
            osc.send_message("/valence",  float(V))
            osc.send_message("/arousal",  float(A))

            # Draw bounding box
            cv2.rectangle(frame, (x, y), (x+w, y+h), color, 2)

            # Emotion label
            label = f"{emotion}  {conf*100:.0f}%"
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
            cv2.rectangle(frame, (x, y - th - 10), (x + tw + 8, y), color, -1)
            cv2.putText(frame, label, (x + 4, y - 6),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)

            # Valence / Arousal text under face box
            va_label = f"V {V:+.2f}  A {A:+.2f}"
            cv2.putText(frame, va_label, (x, y + h + 22),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 1)

            draw_va_plot(frame, V, A)

        # Hand gesture detection
        hand = hand_detector.detect(frame)
        if hand:
            osc.send_message("/gesture",     hand["static"]  or "none")
            osc.send_message("/dynamic",     hand["dynamic"] or "none")
            osc.send_message("/palm_x",      float(hand["palm_x"]))
            osc.send_message("/palm_y",      float(hand["palm_y"]))
            osc.send_message("/hand_size",   float(hand["hand_size"]))
            osc.send_message("/pinch",       float(hand["pinch"]))
            osc.send_message("/spread",      float(hand["spread"]))
            osc.send_message("/wrist_angle", float(hand["wrist_angle"]))

            # Gesture overlay — top left
            static  = hand["static"]  or ""
            dynamic = hand["dynamic"] or ""
            cv2.putText(frame, f"gesture: {static}",  (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            cv2.putText(frame, f"dynamic: {dynamic}", (10, 58),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)

        cv2.imshow("Emotion Recognizer  |  Q to quit", frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
