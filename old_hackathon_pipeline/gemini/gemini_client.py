# ============================================
# GEMINI CLIENT
# Handles all Gemini API interactions
# ============================================
import time
import requests
from typing import Optional
from google import genai
from google.genai import types
from config import GEMINI_API_KEY, VIDEO_DURATION, VIDEO_ASPECT_RATIO


class GeminiClient:
    """Handles Gemini API for text analysis and video generation"""
    
    def __init__(self):
        self.client = genai.Client(api_key=GEMINI_API_KEY)
    
    def get_sound_effects(self, prompt_text: str, available_labels: list) -> list:
        """Ask Gemini which sound effects match the scene"""
        print("\n[Gemini] Analyzing scene for sound effects...")
        
        labels_str = ", ".join(available_labels)
        
        prompt = f"""You are a sound designer. Given a memory/dream/scene and a list of available sound effects, select which ones would fit.

Available sound effects: {labels_str}

Scene: {prompt_text}

Respond with ONLY the applicable sound effect names from the list, separated by commas. No explanations - just the exact label names."""
        
        response = self.client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt
        )
        
        sound_effects_str = response.text
        sound_effects = [s.strip().lower() for s in sound_effects_str.split(',')]
        
        # Filter to only include valid labels
        valid_effects = [s for s in sound_effects if s in available_labels]
        return valid_effects
    
    def generate_video(self, prompt_text: str) -> Optional[str]:
        """Generate video using Gemini Veo"""
        print("\n[Gemini] Generating video with Veo...")
        print("   This may take a minute...")
        
        video_prompt = f"A beautiful, atmospheric, cinematic video of: {prompt_text}. Dreamlike quality, soft lighting, gentle movement, nostalgic mood."
        
        try:
            operation = self.client.models.generate_videos(
                model="veo-2.0-generate-001",
                prompt=video_prompt,
                config=types.GenerateVideosConfig(
                    durationSeconds=VIDEO_DURATION,
                    aspectRatio=VIDEO_ASPECT_RATIO,
                    numberOfVideos=1,
                )
            )
            
            print("   Waiting for video generation...")
            while not operation.done:
                time.sleep(5)
                print("   Still generating...")
                operation = self.client.operations.get(operation)
            
            if operation.response and operation.response.generated_videos:
                video = operation.response.generated_videos[0]
                video_uri = video.video.uri
                
                print("   Downloading video...")
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

