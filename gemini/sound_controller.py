# ============================================
# SOUND CONTROLLER
# Handles SuperCollider OSC communication
# ============================================
from typing import Union
from pythonosc import udp_client
from config import SC_IP, SC_PORT, SC_ADDRESS, SOUND_LABELS_FILE


class SoundController:
    """Manages sound effects and SuperCollider communication"""
    
    def __init__(self):
        self.osc_client = udp_client.SimpleUDPClient(SC_IP, SC_PORT)
        self.available_labels = self._load_labels()
        self.active_sounds = set()
    
    def _load_labels(self) -> list:
        """Load available sound effect labels from file"""
        labels = []
        try:
            with open(SOUND_LABELS_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        labels.append(line)
            print(f"[Sound] Loaded {len(labels)} effects: {labels}")
        except FileNotFoundError:
            print(f"[Sound] Warning: {SOUND_LABELS_FILE} not found")
        return labels
    
    def get_available_labels(self) -> list:
        """Get list of available sound effect labels"""
        return self.available_labels
    
    def trigger(self, sound_effect: str):
        """Send a single sound effect to SuperCollider"""
        if sound_effect in self.available_labels:
            print(f"[Sound] Triggering: {sound_effect}")
            self.osc_client.send_message(SC_ADDRESS, sound_effect)
            self.active_sounds.add(sound_effect)
        else:
            print(f"[Sound] Unknown effect: {sound_effect}")
    
    def trigger_multiple(self, sound_effects: Union[list, set]):
        """Send multiple sound effects to SuperCollider"""
        print(f"\n[Sound] Sending to SuperCollider (port {SC_PORT})...")
        for effect in sound_effects:
            self.trigger(effect)
    
    def stop(self, sound_effect: str):
        """Stop a specific sound effect"""
        # Send stop message (you may need to implement this in SC)
        self.osc_client.send_message("/stop", sound_effect)
        self.active_sounds.discard(sound_effect)
    
    def stop_all(self):
        """Stop all active sounds"""
        for sound in self.active_sounds.copy():
            self.stop(sound)
        self.active_sounds.clear()

