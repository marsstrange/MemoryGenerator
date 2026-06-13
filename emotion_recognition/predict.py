import torch
import torch.nn as nn
from torchvision import transforms, models
from PIL import Image
import sys

if torch.backends.mps.is_available():
    DEVICE = torch.device("mps")
elif torch.cuda.is_available():
    DEVICE = torch.device("cuda")
else:
    DEVICE = torch.device("cpu")
EMOTIONS = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]
CHECKPOINT = "./checkpoints/best_model.pth"


def load_model(checkpoint_path):
    model = models.resnet50(weights=None)
    model.fc = nn.Sequential(
        nn.Dropout(0.4),
        nn.Linear(model.fc.in_features, 256),
        nn.ReLU(),
        nn.Dropout(0.3),
        nn.Linear(256, 7),
    )
    model.load_state_dict(torch.load(checkpoint_path, map_location=DEVICE))
    model.eval()
    return model.to(DEVICE)


def predict(image_path, model):
    tf = transforms.Compose([
        transforms.Grayscale(num_output_channels=3),
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    image = Image.open(image_path).convert("RGB")
    tensor = tf(image).unsqueeze(0).to(DEVICE)

    with torch.no_grad():
        logits = model(tensor)
        probs = torch.softmax(logits, dim=1)[0]

    results = sorted(zip(EMOTIONS, probs.tolist()), key=lambda x: x[1], reverse=True)
    print(f"\nPrediction for: {image_path}")
    for emotion, prob in results:
        bar = "█" * int(prob * 30)
        print(f"  {emotion:<10} {prob:.3f}  {bar}")
    print(f"\n  --> Predicted: {results[0][0].upper()}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python predict.py <image_path>")
        sys.exit(1)
    model = load_model(CHECKPOINT)
    predict(sys.argv[1], model)
