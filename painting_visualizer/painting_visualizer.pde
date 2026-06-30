// Requires: oscP5 library (Sketch → Import Library → Add Library → search "oscP5")
// Listens on port 12000 for /painting/path, /emotion, /valence, /arousal from camera.py

import oscP5.*;
import netP5.*;

OscP5 osc;

PImage painting;
String paintingPath = "";
String emotion      = "neutral";
float  valence      = 0, arousal = 0;
float  sValence     = 0, sArousal = 0;  // smoothed

int       NUM_PARTICLES = 1800;
Particle[] particles;

// Emotion → base color
HashMap<String, int[]> EMOTION_COL = new HashMap<>();

void setup() {
  size(1100, 800, P2D);
  colorMode(RGB, 255);

  EMOTION_COL.put("angry",    new int[]{230, 30,  20 });
  EMOTION_COL.put("disgust",  new int[]{120, 180, 30 });
  EMOTION_COL.put("fear",     new int[]{110, 0,   200});
  EMOTION_COL.put("happy",    new int[]{255, 215, 0  });
  EMOTION_COL.put("neutral",  new int[]{180, 180, 180});
  EMOTION_COL.put("sad",      new int[]{30,  90,  210});
  EMOTION_COL.put("surprise", new int[]{255, 140, 0  });

  osc = new OscP5(this, 12000);

  particles = new Particle[NUM_PARTICLES];
  for (int i = 0; i < NUM_PARTICLES; i++) particles[i] = new Particle();

  background(0);
}

void draw() {
  // Smooth emotion values
  sArousal = lerp(sArousal, arousal,  0.04);
  sValence = lerp(sValence, valence,  0.04);

  // Trailing fade — slower fade = longer trails
  fill(0, 0, 0, 14);
  noStroke();
  rect(0, 0, width, height);

  // Painting as subtle washed-out base
  if (painting != null) {
    float baseAlpha = 25 + abs(sValence) * 15;
    tint(255, baseAlpha);
    image(painting, 0, 0, width, height);
    noTint();
  }

  // Flow-field particles
  for (Particle p : particles) {
    p.update();
    p.display();
  }

  // Emotion vignette around the frame edge
  drawVignette();
}

// Soft radial glow at the edges in the emotion color
void drawVignette() {
  int[] ec = getEmotionColor();
  float intensity = 0.25 + abs(sArousal) * 0.45;
  noStroke();
  for (int i = 14; i >= 0; i--) {
    float t     = i / 14.0;
    float alpha = (1 - t) * (1 - t) * intensity * 90;
    float sz    = lerp(0, max(width, height) * 1.6, 1 - t);
    fill(ec[0], ec[1], ec[2], alpha);
    ellipse(width / 2, height / 2, sz, sz);
  }
}

int[] getEmotionColor() {
  return EMOTION_COL.containsKey(emotion) ? EMOTION_COL.get(emotion) : new int[]{180, 180, 180};
}

// ── OSC ───────────────────────────────────────────────────────────────────────

void oscEvent(OscMessage msg) {
  String addr = msg.addrPattern();
  if (addr.equals("/painting/path")) {
    String path = msg.get(0).stringValue();
    if (!path.equals(paintingPath)) {
      paintingPath = path;
      thread("loadPainting");
    }
  }
  else if (addr.equals("/emotion"))  emotion = msg.get(0).stringValue();
  else if (addr.equals("/valence"))  valence = msg.get(0).floatValue();
  else if (addr.equals("/arousal"))  arousal = msg.get(0).floatValue();
}

void loadPainting() {
  PImage img = loadImage(paintingPath);
  if (img == null) return;
  img.resize(width, height);
  img.loadPixels();
  painting = img;
  // Reset all particles so they re-sample the new image
  for (Particle p : particles) p.reset();
  // Clear trails on painting change
  background(0);
}

// ── Particle ──────────────────────────────────────────────────────────────────

class Particle {
  float x, y, px, py;
  float life, maxLife;
  float sz;
  color paintCol;

  Particle() { reset(); }

  void reset() {
    x  = random(width);
    y  = random(height);
    px = x;  py = y;
    maxLife = random(70, 200);
    life    = random(maxLife);   // stagger initial ages
    sz      = random(0.6, 3.2);
    paintCol = color(120);
  }

  void update() {
    px = x;  py = y;

    // Perlin noise flow field
    // noise scale: higher arousal → tighter, faster eddies
    float ns = 0.003 + abs(sArousal) * 0.004;
    // time drift: faster when aroused
    float t  = frameCount * 0.005 * (1.0 + abs(sArousal) * 0.9);

    float angle = noise(x * ns, y * ns, t) * TWO_PI * 4;

    // Valence biases flow:
    //   positive valence → smooth clockwise curl
    //   negative valence → chaos (extra noise layer)
    angle += sValence * 0.9;
    if (sValence < 0) {
      angle += noise(x * ns * 3, y * ns * 3, t * 2) * abs(sValence) * TWO_PI;
    }

    float speed = 1.0 + abs(sArousal) * 2.8;
    x += cos(angle) * speed;
    y += sin(angle) * speed;
    life--;

    // Sample painting color at current screen position
    if (painting != null) {
      int sx = constrain((int)(x / width  * (painting.width  - 1)), 0, painting.width  - 1);
      int sy = constrain((int)(y / height * (painting.height - 1)), 0, painting.height - 1);
      paintCol = painting.pixels[sy * painting.width + sx];
    }

    if (life <= 0 || x < -30 || x > width + 30 || y < -30 || y > height + 30) {
      reset();
    }
  }

  void display() {
    float lifeRatio = life / maxLife;
    float alpha     = sin(lifeRatio * PI) * 160;   // fade in and out smoothly

    // Blend painting color with emotion color based on arousal
    int[] ec      = getEmotionColor();
    float blend   = constrain(0.15 + abs(sArousal) * 0.30, 0, 0.6);
    float r       = lerp(red(paintCol),   ec[0], blend);
    float g       = lerp(green(paintCol), ec[1], blend);
    float b       = lerp(blue(paintCol),  ec[2], blend);

    stroke(r, g, b, alpha);
    strokeWeight(sz);
    line(px, py, x, y);
  }
}