import os
import argparse
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms, models
from torch.optim.lr_scheduler import StepLR
from tqdm import tqdm

if torch.backends.mps.is_available():
    DEVICE = torch.device("mps")
elif torch.cuda.is_available():
    DEVICE = torch.device("cuda")
else:
    DEVICE = torch.device("cpu")
DATA_DIR = "./data"
CHECKPOINT_DIR = "./checkpoints"
EMOTIONS = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]
NUM_CLASSES = 7
BATCH_SIZE = 64
EPOCHS = 30
LEARNING_RATE = 1e-4


def get_transforms():
    train_tf = transforms.Compose([
        transforms.Grayscale(num_output_channels=3),  # FER-2013 is grayscale
        transforms.Resize((224, 224)),
        transforms.RandomHorizontalFlip(),
        transforms.RandomRotation(10),
        transforms.ColorJitter(brightness=0.2, contrast=0.2),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    val_tf = transforms.Compose([
        transforms.Grayscale(num_output_channels=3),
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    return train_tf, val_tf


def build_model():
    model = models.resnet50(weights=models.ResNet50_Weights.IMAGENET1K_V1)

    # Freeze all layers except the last block + classifier
    for name, param in model.named_parameters():
        if "layer4" not in name and "fc" not in name:
            param.requires_grad = False

    model.fc = nn.Sequential(
        nn.Dropout(0.4),
        nn.Linear(model.fc.in_features, 256),
        nn.ReLU(),
        nn.Dropout(0.3),
        nn.Linear(256, NUM_CLASSES),
    )
    return model.to(DEVICE)


def train_one_epoch(model, loader, criterion, optimizer, epoch, epochs):
    model.train()
    total_loss, correct = 0.0, 0
    bar = tqdm(loader, desc=f"Epoch {epoch:02d}/{epochs} [Train]", unit="batch", leave=False)
    for images, labels in bar:
        images, labels = images.to(DEVICE), labels.to(DEVICE)
        optimizer.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()
        total_loss += loss.item() * images.size(0)
        correct += (outputs.argmax(1) == labels).sum().item()
        bar.set_postfix(loss=f"{loss.item():.4f}")
    n = len(loader.dataset)
    return total_loss / n, correct / n


def evaluate(model, loader, criterion, epoch, epochs):
    model.eval()
    total_loss, correct = 0.0, 0
    bar = tqdm(loader, desc=f"Epoch {epoch:02d}/{epochs} [Val]  ", unit="batch", leave=False)
    with torch.no_grad():
        for images, labels in bar:
            images, labels = images.to(DEVICE), labels.to(DEVICE)
            outputs = model(images)
            loss = criterion(outputs, labels)
            total_loss += loss.item() * images.size(0)
            correct += (outputs.argmax(1) == labels).sum().item()
    n = len(loader.dataset)
    return total_loss / n, correct / n


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke", action="store_true", help="Run a quick sanity check with 200 samples and 2 epochs")
    args = parser.parse_args()

    epochs = 2 if args.smoke else EPOCHS
    train_tf, val_tf = get_transforms()

    train_dataset = datasets.ImageFolder(os.path.join(DATA_DIR, "train"), transform=train_tf)
    val_dataset = datasets.ImageFolder(os.path.join(DATA_DIR, "test"), transform=val_tf)

    if args.smoke:
        train_dataset = Subset(train_dataset, range(200))
        val_dataset = Subset(val_dataset, range(50))
        print("SMOKE TEST MODE — 200 train / 50 val samples, 2 epochs\n")

    train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True, num_workers=4, pin_memory=True)
    val_loader = DataLoader(val_dataset, batch_size=BATCH_SIZE, shuffle=False, num_workers=4, pin_memory=True)

    print(f"Device: {DEVICE}")
    print(f"Train samples: {len(train_dataset)} | Val samples: {len(val_dataset)}")

    model = build_model()
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(filter(lambda p: p.requires_grad, model.parameters()), lr=LEARNING_RATE)
    scheduler = StepLR(optimizer, step_size=10, gamma=0.5)

    os.makedirs(CHECKPOINT_DIR, exist_ok=True)
    best_val_acc = 0.0

    for epoch in range(1, epochs + 1):
        train_loss, train_acc = train_one_epoch(model, train_loader, criterion, optimizer, epoch, epochs)
        val_loss, val_acc = evaluate(model, val_loader, criterion, epoch, epochs)
        scheduler.step()

        print(
            f"Epoch {epoch:02d}/{epochs} | "
            f"Train Loss: {train_loss:.4f} Acc: {train_acc:.4f} | "
            f"Val Loss: {val_loss:.4f} Acc: {val_acc:.4f}"
        )

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), os.path.join(CHECKPOINT_DIR, "best_model.pth"))
            print(f"  --> Saved best model (val acc: {val_acc:.4f})")

    print(f"\nDone. Best val accuracy: {best_val_acc:.4f}")


if __name__ == "__main__":
    main()
