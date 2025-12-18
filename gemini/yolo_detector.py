# ============================================
# YOLO DETECTOR - CAMERA
# Real-time object detection from webcam
# ============================================
import cv2
from ultralytics import YOLO
from config import YOLO_MODEL_PATH


class YOLODetector:
    """Real-time object detection from camera"""
    
    # Map YOLO classes to sound effect labels
    CLASS_TO_SOUND = {
        "person": "wind",
        "umbrella": "rain",
        "car": "city",
        "truck": "city",
        "bus": "city",
        "motorcycle": "city",
        "bird": "forest",
        "cat": "forest",
        "dog": "forest",
        "potted plant": "forest",
        "boat": "water",
        "kite": "wind",
    }
    
    def __init__(self):
        print("[YOLO] Loading model...")
        self.model = YOLO(YOLO_MODEL_PATH)
        print("[YOLO] Model loaded")
    
    def list_cameras(self):
        """List available cameras"""
        print("[YOLO] Checking available cameras...")
        available = []
        for i in range(5):
            cap = cv2.VideoCapture(i)
            if cap.isOpened():
                available.append(i)
                cap.release()
        print(f"[YOLO] Available cameras: {available}")
        return available
    
    def run_camera(self, camera_index=0, callback=None):
        """Open single camera and detect objects in real-time"""
        print(f"[YOLO] Opening camera {camera_index}...")
        
        cap = cv2.VideoCapture(camera_index)
        
        if not cap.isOpened():
            print("[YOLO] Error: Could not open camera")
            return
        
        print("[YOLO] Press 'q' to quit")
        
        detected_sounds = set()
        
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            frame = self._process_frame(frame, detected_sounds, callback)
            cv2.imshow("YOLO Camera", frame)
            
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
        
        cap.release()
        cv2.destroyAllWindows()
    
    def run_dual_cameras(self, cam1=0, cam2=1, callback=None):
        """Open both cameras at the same time (falls back to single if needed)"""
        print(f"[YOLO] Opening cameras {cam1} and {cam2}...")
        
        cap1 = cv2.VideoCapture(cam1)
        cap2 = cv2.VideoCapture(cam2)
        
        # Fall back to single camera if one doesn't work
        if not cap1.isOpened() and not cap2.isOpened():
            print("[YOLO] Error: No cameras available")
            return
        if not cap2.isOpened():
            print(f"[YOLO] Camera {cam2} not available, using single camera")
            cap1.release()
            self.run_camera(cam1, callback)
            return
        if not cap1.isOpened():
            print(f"[YOLO] Camera {cam1} not available, using single camera")
            cap2.release()
            self.run_camera(cam2, callback)
            return
        
        print("[YOLO] Press 'q' to quit")
        
        detected_sounds = set()
        
        while True:
            ret1, frame1 = cap1.read()
            ret2, frame2 = cap2.read()
            
            if not ret1 or not ret2:
                break
            
            # Process both frames
            frame1 = self._process_frame(frame1, detected_sounds, callback)
            frame2 = self._process_frame(frame2, detected_sounds, callback)
            
            # Resize to same width
            w = min(frame1.shape[1], frame2.shape[1])
            frame1 = cv2.resize(frame1, (w, int(frame1.shape[0] * w / frame1.shape[1])))
            frame2 = cv2.resize(frame2, (w, int(frame2.shape[0] * w / frame2.shape[1])))
            
            # Combine vertically (top and bottom)
            combined = cv2.vconcat([frame1, frame2])
            
            cv2.imshow("YOLO Dual Cameras", combined)
            
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
        
        cap1.release()
        cap2.release()
        cv2.destroyAllWindows()
    
    def _process_frame(self, frame, detected_sounds, callback):
        """Process a single frame for detection"""
        results = self.model(frame, verbose=False)
        
        for result in results:
            for box in result.boxes:
                class_id = int(box.cls[0])
                class_name = self.model.names[class_id]
                conf = float(box.conf[0])
                
                # Draw box
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(frame, f"{class_name} {conf:.2f}", (x1, y1 - 10),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
                
                # Trigger sound if mapped
                if class_name in self.CLASS_TO_SOUND:
                    sound = self.CLASS_TO_SOUND[class_name]
                    if sound not in detected_sounds:
                        detected_sounds.add(sound)
                        print(f"[YOLO] Detected: {class_name} -> {sound}")
                        if callback:
                            callback(sound)
        
        return frame


if __name__ == "__main__":
    detector = YOLODetector()
    detector.run_dual_cameras(cam1=0, cam2=1)
