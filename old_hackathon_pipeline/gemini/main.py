#!/usr/bin/env python3
# ============================================
# MEMORY GENERATOR - MAIN
# Orchestrates Gemini, YOLO, and SuperCollider
# ============================================
import sys
import subprocess
from config import (
    ENABLE_VIDEO_GENERATION,
    ENABLE_YOLO_DETECTION,
    ENABLE_GEMINI_SOUNDS
)

from gemini_client import GeminiClient
from yolo_detector import YOLODetector
from sound_controller import SoundController


class MemoryGenerator:
    """Main application class"""
    
    def __init__(self):
        self.sound = SoundController()
        self.gemini = GeminiClient() if (ENABLE_GEMINI_SOUNDS or ENABLE_VIDEO_GENERATION) else None
        self.yolo = YOLODetector() if ENABLE_YOLO_DETECTION else None
    
    def run(self, prompt_text: str):
        """Run the full memory generation pipeline"""
        print(f"\nYour prompt:\n{prompt_text}")
        
        # Step 1: Get initial sound effects from Gemini
        if ENABLE_GEMINI_SOUNDS and self.gemini:
            sound_effects = self.gemini.get_sound_effects(
                prompt_text, 
                self.sound.get_available_labels()
            )
            print(f"\n[Gemini] Sound effects selected: {sound_effects}")
            self.sound.trigger_multiple(sound_effects)
        
        # Step 2: Generate video with Gemini Veo
        video_path = None
        if ENABLE_VIDEO_GENERATION and self.gemini:
            video_path = self.gemini.generate_video(prompt_text)
            if video_path is None:
                print("\n[Error] Could not generate video.")
                return
        else:
            print("\n[Video generation disabled]")
        
        # Step 3: Play video with YOLO detection (if enabled)
        if video_path:
            if ENABLE_YOLO_DETECTION and self.yolo:
                # Play with real-time object detection
                self.yolo.detect_realtime(
                    video_path, 
                    callback=lambda sounds: self.sound.trigger_multiple(sounds)
                )
            else:
                # Simple playback without detection
                self._play_video_simple(video_path)
        
        print("\n" + "=" * 60)
        print("Done!")
        print("=" * 60)
    
    def _play_video_simple(self, video_path: str):
        """Play video without YOLO detection"""
        print("\n[Video] Playing fullscreen...")
        print("   Press 'q' or ESC to quit")
        
        try:
            subprocess.run([
                "mpv", 
                "--fs",
                "--no-audio",
                "--loop=inf",
                "--no-osc",
                "--no-input-default-bindings",
                "--input-conf=/dev/null",
                "--osd-level=0",
                video_path
            ], check=True)
        except FileNotFoundError:
            print("   mpv not found, using OpenCV...")
            self._play_with_opencv(video_path)
    
    def _play_with_opencv(self, video_path: str):
        """Fallback player using OpenCV"""
        import cv2
        
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        delay = int(1000 / fps) if fps > 0 else 33
        
        cv2.namedWindow("Memory Video", cv2.WND_PROP_FULLSCREEN)
        cv2.setWindowProperty("Memory Video", cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
        
        while True:
            ret, frame = cap.read()
            if not ret:
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                continue
            
            cv2.imshow("Memory Video", frame)
            key = cv2.waitKey(delay) & 0xFF
            if key == ord('q') or key == 27:
                break
        
        cap.release()
        cv2.destroyAllWindows()


def main():
    print("=" * 60)
    print("MEMORY GENERATOR")
    print("Gemini + YOLO + SuperCollider")
    print("=" * 60)
    
    # Show current settings
    print(f"\nSettings:")
    print(f"   Video Generation: {'ON' if ENABLE_VIDEO_GENERATION else 'OFF'}")
    print(f"   YOLO Detection:   {'ON' if ENABLE_YOLO_DETECTION else 'OFF'}")
    print(f"   Gemini Sounds:    {'ON' if ENABLE_GEMINI_SOUNDS else 'OFF'}")
    
    # Get prompt
    if len(sys.argv) > 1:
        prompt_text = " ".join(sys.argv[1:])
    else:
        prompt_text = input("\nEnter your memory/dream: ")
    
    if not prompt_text.strip():
        print("No input provided!")
        return
    
    # Run
    app = MemoryGenerator()
    app.run(prompt_text)


if __name__ == "__main__":
    main()

