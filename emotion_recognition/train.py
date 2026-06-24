import os
import argparse
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Subset, WeightedRandomSampler
from torchvision import datasets, transforms, models
from torch.optim.lr_scheduler import CosineAnnealingLR
from tqdm import tqdm

if torch.backends.mps.is_available():
    DEVICE = torch.device("mps")
elif torch.cuda.is_available():
    DEVICE = torch.device("cuda")
else:
    DEVICE = torch.device("cpu")

DATA_DIR      = "./data"
CHECKPOINT_DIR = "./checkpoints"
EMOTIONS      = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]
NUM_CLASSES   = 7
BATCH_SIZE    = 64
EPOCHS        = 30
LEARNING_RATE = 1e-4
VA_WEIGHT     = 0.4   # weight of VA loss relative to classification loss

# Valence-Arousal coordinates for each emotion class (order matches EMOTIONS list)
# Valence: -1 (negative) → +1 (positive)
# Arousal: -1 (calm)     → +1 (excited)
VA_TARGETS = torch.tensor([
    [-0.8,  0.8],  # angry
    [-0.7,  0.2],  # disgust
    [-0.7,  0.7],  # fear
    [ 0.9,  0.5],  # happy
    [ 0.0,  0.0],  # neutral
    [-0.6, -0.6],  # sad
    [ 0.1,  0.9],  # surprise
], dtype=torch.float32)


class EmotionModel(nn.Module):
    """ResNet50 backbone with two output heads:
       - cls_head: 7-class classification
       - va_head:  (valence, arousal) regression in [-1, 1]
    """
    def __init__(self):
        super().__init__()
        backbone = models.resnet50(weights=models.ResNet50_Weights.IMAGENET1K_V1)

        for name, param in backbone.named_parameters():
            if "layer4" not in name and "fc" not in name:
                param.requires_grad = False

        self.features = nn.Sequential(*list(backbone.children())[:-1])

        feat_dim = 2048

        self.cls_head = nn.Sequential(
            nn.Dropout(0.4),
            nn.Linear(feat_dim, 256),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(256, NUM_CLASSES),
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


def get_transforms():
    train_tf = transforms.Compose([
        transforms.Grayscale(num_output_channels=3),
        transforms.Resize((224, 224)),
        transforms.RandomHorizontalFlip(),
        transforms.RandomRotation(15),
        transforms.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.1),
        transforms.RandomGrayscale(p=0.05),
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


def train_one_epoch(model, loader, cls_criterion, va_criterion, optimizer, epoch, epochs):
    model.train()
    total_loss, cls_loss_sum, va_loss_sum, correct = 0.0, 0.0, 0.0, 0
    bar = tqdm(loader, desc=f"Epoch {epoch:02d}/{epochs} [Train]", unit="batch", leave=False)

    for images, labels in bar:
        images, labels = images.to(DEVICE), labels.to(DEVICE)
        va_gt = VA_TARGETS[labels.cpu()].to(DEVICE)

        optimizer.zero_grad()
        cls_out, va_out = model(images)

        cls_loss = cls_criterion(cls_out, labels)
        va_loss  = va_criterion(va_out, va_gt)
        loss     = cls_loss + VA_WEIGHT * va_loss

        loss.backward()
        optimizer.step()

        total_loss   += loss.item()    * images.size(0)
        cls_loss_sum += cls_loss.item()* images.size(0)
        va_loss_sum  += va_loss.item() * images.size(0)
        correct      += (cls_out.argmax(1) == labels).sum().item()
        bar.set_postfix(loss=f"{loss.item():.3f}", cls=f"{cls_loss.item():.3f}", va=f"{va_loss.item():.3f}")

    n = len(loader.dataset)
    return total_loss / n, cls_loss_sum / n, va_loss_sum / n, correct / n


def evaluate(model, loader, cls_criterion, va_criterion, epoch, epochs):
    model.eval()
    total_loss, correct = 0.0, 0
    bar = tqdm(loader, desc=f"Epoch {epoch:02d}/{epochs} [Val]  ", unit="batch", leave=False)

    with torch.no_grad():
        for images, labels in bar:
            images, labels = images.to(DEVICE), labels.to(DEVICE)
            va_gt = VA_TARGETS[labels.cpu()].to(DEVICE)

            cls_out, va_out = model(images)
            loss = cls_criterion(cls_out, labels) + VA_WEIGHT * va_criterion(va_out, va_gt)

            total_loss += loss.item() * images.size(0)
            correct    += (cls_out.argmax(1) == labels).sum().item()

    n = len(loader.dataset)
    return total_loss / n, correct / n


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke", action="store_true",
                        help="Sanity check: 200 samples, 2 epochs")
    args = parser.parse_args()

    epochs = 2 if args.smoke else EPOCHS
    train_tf, val_tf = get_transforms()

    train_dataset = datasets.ImageFolder(os.path.join(DATA_DIR, "train"), transform=train_tf)
    val_dataset   = datasets.ImageFolder(os.path.join(DATA_DIR, "test"),  transform=val_tf)

    if args.smoke:
        train_dataset = Subset(train_dataset, range(200))
        val_dataset   = Subset(val_dataset,   range(50))
        print("SMOKE TEST — 200 train / 50 val, 2 epochs\n")

    # Balanced sampling to fix class imbalance (disgust=436 vs happy=7215)
    targets       = [train_dataset[i][1] for i in range(len(train_dataset))]
    counts        = torch.bincount(torch.tensor(targets), minlength=NUM_CLASSES).clamp(min=1)
    sample_w      = (1.0 / counts.float())[targets]
    sampler       = WeightedRandomSampler(sample_w, num_samples=len(sample_w), replacement=True)

    train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, sampler=sampler,
                              num_workers=4, pin_memory=(DEVICE.type == "cuda"))
    val_loader   = DataLoader(val_dataset,   batch_size=BATCH_SIZE, shuffle=False,
                              num_workers=4, pin_memory=(DEVICE.type == "cuda"))

    print(f"Device : {DEVICE}")
    print(f"Train  : {len(train_dataset)} samples")
    print(f"Val    : {len(val_dataset)} samples")
    print(f"Output : 7-class classification  +  (valence, arousal) regression\n")

    model = EmotionModel().to(DEVICE)

    class_weights = (counts.sum() / (NUM_CLASSES * counts.float())).to(DEVICE)
    cls_criterion = nn.CrossEntropyLoss(weight=class_weights)
    va_criterion  = nn.MSELoss()

    optimizer = optim.Adam(
        filter(lambda p: p.requires_grad, model.parameters()),
        lr=LEARNING_RATE, weight_decay=1e-4
    )
    scheduler = CosineAnnealingLR(optimizer, T_max=epochs, eta_min=1e-6)

    os.makedirs(CHECKPOINT_DIR, exist_ok=True)
    best_val_acc = 0.0

    for epoch in range(1, epochs + 1):
        tr_loss, tr_cls, tr_va, tr_acc = train_one_epoch(
            model, train_loader, cls_criterion, va_criterion, optimizer, epoch, epochs)
        val_loss, val_acc = evaluate(
            model, val_loader, cls_criterion, va_criterion, epoch, epochs)
        scheduler.step()

        print(
            f"Epoch {epoch:02d}/{epochs} | "
            f"Train loss {tr_loss:.4f} (cls {tr_cls:.4f} va {tr_va:.4f}) acc {tr_acc:.4f} | "
            f"Val loss {val_loss:.4f} acc {val_acc:.4f}"
        )

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), os.path.join(CHECKPOINT_DIR, "best_model.pth"))
            print(f"  --> Saved best model (val acc {val_acc:.4f})")

    print(f"\nDone. Best val accuracy: {best_val_acc:.4f}")


if __name__ == "__main__":
    main()
