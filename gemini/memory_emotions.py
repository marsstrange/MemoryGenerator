from google import genai
from google.genai import types
from pythonosc import udp_client
import os
import sys
import subprocess
import time

# ============================================
# API KEY - Get free from: https://aistudio.google.com/apikey
# ============================================
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

# ============================================
# VIDEO GENERATION TOGGLE (costs money!)
# Set to False to disable video generation
# ============================================
ENABLE_VIDEO_GENERATION = True

# Sound effect labels file (relative to this script's location)
SOUND_LABELS_FILE = os.path.join(os.path.dirname(__file__), "sound_effect_labels.txt")

# SuperCollider OSC settings
SC_IP = "127.0.0.1"
SC_PORT = 57120
SC_ADDRESS = "/class"

# Initialize Gemini client
client = genai.Client(api_key=GEMINI_API_KEY)

# Initialize OSC client
osc_client = udp_client.SimpleUDPClient(SC_IP, SC_PORT)

def load_sound_labels():
    """Load sound effect labels from file"""
    labels = []
    with open(SOUND_LABELS_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                labels.append(line)
    return labels

def get_sound_effects(prompt_text, available_labels):
    """Ask Gemini which sound effects are applicable"""
    print("\nAsking Gemini for applicable sound effects...")
    
    labels_str = ", ".join(available_labels)
    
    prompt = f"""You are a sound designer. Given a memory/dream/scene and a list of available sound effects, select which ones would fit.

Available sound effects: {labels_str}

Scene: {prompt_text}

Respond with ONLY the applicable sound effect names from the list, separated by commas. No explanations - just the exact label names."""
    
    response = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=prompt
    )
    
    sound_effects_str = response.text
    sound_effects = [s.strip().lower() for s in sound_effects_str.split(',')]
    
    # Filter to only include valid labels
    valid_effects = [s for s in sound_effects if s in available_labels]
    return valid_effects

def send_to_supercollider(sound_effects):
    """Send sound effect class names to SuperCollider via OSC"""
    print(f"\nSending to SuperCollider (port {SC_PORT})...")
    
    for effect in sound_effects:
        print(f"   Sending: {SC_ADDRESS} '{effect}'")
        osc_client.send_message(SC_ADDRESS, effect)

def generate_video_with_gemini(prompt_text):
    """Generate a video using Gemini Veo"""
    import requests
    
    print("\nGenerating video with Gemini Veo...")
    print("   This may take a minute...")
    
    video_prompt = f"A beautiful, atmospheric, cinematic video of: {prompt_text}. Dreamlike quality, soft lighting, gentle movement, nostalgic mood."
    
    try:
        # Generate video with Veo
        operation = client.models.generate_videos(
            model="veo-2.0-generate-001",
            prompt=video_prompt,
            config=types.GenerateVideosConfig(
                durationSeconds=8,  # Max allowed: 5-8 seconds
                aspectRatio="16:9",
                numberOfVideos=1,
            )
        )
        
        # Wait for video generation to complete
        print("   Waiting for video generation...")
        while not operation.done:
            time.sleep(5)
            print("   Still generating...")
            operation = client.operations.get(operation)
        
        # Download the video from URI
        if operation.response and operation.response.generated_videos:
            video = operation.response.generated_videos[0]
            video_uri = video.video.uri
            
            print("   Downloading video...")
            
            # Download video from URI with API key
            response = requests.get(
                video_uri,
                headers={"x-goog-api-key": GEMINI_API_KEY}
            )
            
            if response.status_code == 200:
                video_path = "gemini_video.mp4"
                with open(video_path, "wb") as f:
                    f.write(response.content)
                print(f"   Video saved: {video_path}")
                return video_path
            else:
                print(f"   Download failed: {response.status_code}")
                return None
        else:
            print("   No video generated")
            return None
            
    except Exception as e:
        print(f"   Video generation failed: {e}")
        return None

def play_fullscreen(video_path):
    """Play video fullscreen, autoplay, loop (muted - sound from SuperCollider)"""
    print("\nPlaying video fullscreen (autoplay + loop)...")
    print("   Sound will come from SuperCollider")
    print("   Press 'q' or ESC to quit")
    
    # Use mpv for true fullscreen with autoplay and loop
    try:
        # mpv with fullscreen, no audio, loop forever
        subprocess.run([
            "mpv", 
            "--fs",              # fullscreen
            "--no-audio",        # mute (SC handles audio)
            "--loop=inf",        # loop forever
            "--no-osc",          # hide on-screen controls
            "--no-input-default-bindings",  # minimal controls
            "--input-conf=/dev/null",
            "--osd-level=0",     # no OSD
            video_path
        ], check=True)
    except FileNotFoundError:
        # Fallback: use Python + OpenCV for autoplay loop
        print("   mpv not found, using OpenCV player...")
        play_with_opencv(video_path)

def play_with_opencv(video_path):
    """Fallback player using OpenCV"""
    import cv2
    
    cap = cv2.VideoCapture(video_path)
    
    # Get video properties
    fps = cap.get(cv2.CAP_PROP_FPS)
    delay = int(1000 / fps) if fps > 0 else 33
    
    # Create fullscreen window
    cv2.namedWindow("Memory Video", cv2.WND_PROP_FULLSCREEN)
    cv2.setWindowProperty("Memory Video", cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
    
    print("   Press 'q' to quit")
    
    while True:
        ret, frame = cap.read()
        
        if not ret:
            # Loop: restart video
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            continue
        
        cv2.imshow("Memory Video", frame)
        
        # Quit on 'q' or ESC
        key = cv2.waitKey(delay) & 0xFF
        if key == ord('q') or key == 27:
            break
    
    cap.release()
    cv2.destroyAllWindows()

def main():
    print("=" * 60)
    print("MEMORY/DREAM -> VIDEO + SUPERCOLLIDER AUDIO")
    print("=" * 60)
    
    # Load sound labels
    print("\nLoading sound effect labels...")
    sound_labels = load_sound_labels()
    print(f"   Found {len(sound_labels)} sound effects: {sound_labels}")
    
    # Get prompt input
    if len(sys.argv) > 1:
        prompt_text = " ".join(sys.argv[1:])
    else:
        prompt_text = input("\nEnter your memory/dream: ")
    
    if not prompt_text.strip():
        print("No input provided!")
        return
    
    print(f"\nYour prompt:\n{prompt_text}")
    
    # Step 1: Get sound effects from Gemini
    sound_effects = get_sound_effects(prompt_text, sound_labels)
    
    print(f"\nSound effects selected:")
    for sound in sound_effects:
        print(f"   - {sound}")
    
    # Step 2: Generate video with Gemini Veo (if enabled)
    video_path = None
    if ENABLE_VIDEO_GENERATION:
        video_path = generate_video_with_gemini(prompt_text)
        
        if video_path is None:
            print("\nCould not generate video. Exiting.")
            return
    else:
        print("\n[VIDEO GENERATION DISABLED - set ENABLE_VIDEO_GENERATION = True to enable]")
    
    # Step 3: Send sounds to SuperCollider (triggers audio)
    send_to_supercollider(sound_effects)
    
    # Step 4: Play video fullscreen (no audio - SC handles sound)
    if video_path:
        play_fullscreen(video_path)
    
    print("\n" + "=" * 60)
    print("Done!")
    print("=" * 60)
    
    return {
        "prompt": prompt_text,
        "sound_effects": sound_effects,
        "video_path": video_path
    }

if __name__ == "__main__":
    main()
