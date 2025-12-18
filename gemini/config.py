# ============================================
# CONFIGURATION
# ============================================
import os

# API Key - Get free from: https://aistudio.google.com/apikey
GEMINI_API_KEY = "AIzaSyC-EB9WADDlvmoVdyfqJe6hpxFgxgwGGjw"

# ============================================
# FEATURE TOGGLES
# ============================================
ENABLE_VIDEO_GENERATION = False   # Costs money! Set False to disable
ENABLE_YOLO_DETECTION = True     # Use YOLO for real-time sound effects
ENABLE_GEMINI_SOUNDS = True      # Use Gemini to select initial sounds

# ============================================
# PATHS
# ============================================
BASE_DIR = os.path.dirname(__file__)
SOUND_LABELS_FILE = os.path.join(BASE_DIR, "sound_effect_labels.txt")
YOLO_MODEL_PATH = os.path.join(BASE_DIR, "yolov8n.pt")

# ============================================
# SUPERCOLLIDER OSC SETTINGS
# ============================================
SC_IP = "127.0.0.1"
SC_PORT = 57120
SC_ADDRESS = "/class"

# ============================================
# VIDEO SETTINGS
# ============================================
VIDEO_DURATION = 8  # seconds (5-8 for Veo)
VIDEO_ASPECT_RATIO = "16:9"

