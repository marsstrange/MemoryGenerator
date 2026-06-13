# Face Emotion Recognition

ResNet50 fine-tuned on FER-2013. Classifies 7 emotions: angry, disgust, fear, happy, neutral, sad, surprise.

## Setup

```bash
pip install -r requirements.txt
```

## Dataset

1. Go to https://www.kaggle.com/datasets/msambare/fer2013
2. Download and unzip
3. Place it so the structure looks like:

```
data/
  train/
    angry/
    disgust/
    fear/
    happy/
    neutral/
    sad/
    surprise/
  test/
    angry/
    ...
```

## Train

```bash
python train.py
```

Best model saved to `checkpoints/best_model.pth`.

## Predict

```bash
python predict.py path/to/face.jpg
```
