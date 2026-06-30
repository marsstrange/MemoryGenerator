// Requires: oscP5 library (Sketch → Import Library → Add Library → search "oscP5")
// Click + drag on the window to select a box — each pixel becomes a particle
// Particles flow along the painting's gradient field

import oscP5.*;
import netP5.*;

OscP5 osc;

PImage  painting;
String  paintingPath = "";
float   valence = 0, arousal = 0;
float   sValence = 0, sArousal = 0;

float[] gradAngle;
float[] gradMag;

ArrayList<PixelParticle> pxParticles = new ArrayList<>();
int GRID_SPACING = 4;

int selX1, selY1, selX2, selY2;
boolean selecting    = false;
boolean needsRespawn = false;

void setup() {
  size(1100, 800);
  pixelDensity(1);
  colorMode(RGB, 255);
  osc = new OscP5(this, 12000);
  background(0);
}

void draw() {
  sArousal = lerp(sArousal, arousal, 0.04);
  sValence = lerp(sValence, valence, 0.04);

  if (needsRespawn && painting != null) {
    spawnFromBox();
    needsRespawn = false;
  }

  fill(0, 0, 0, 10);
  noStroke();
  rect(0, 0, width, height);

  for (PixelParticle p : pxParticles) {
    p.update();
    p.display();
  }

  if (selecting) {
    noFill();
    stroke(255, 160);
    strokeWeight(1);
    rect(selX1, selY1, mouseX - selX1, mouseY - selY1);
  }
}

// ── Box selection ─────────────────────────────────────────────────────────────

void mousePressed()  { selX1 = mouseX; selY1 = mouseY; selecting = true; }
void mouseDragged()  { selX2 = mouseX; selY2 = mouseY; }
void mouseReleased() {
  selecting = false;
  selX2 = mouseX; selY2 = mouseY;
  if (painting != null && abs(selX2 - selX1) > 20 && abs(selY2 - selY1) > 20)
    needsRespawn = true;
}

void spawnFromBox() {
  pxParticles.clear();
  background(0);

  int x1 = constrain(min(selX1, selX2), 0, width  - 1);
  int x2 = constrain(max(selX1, selX2), 0, width  - 1);
  int y1 = constrain(min(selY1, selY2), 0, height - 1);
  int y2 = constrain(max(selY1, selY2), 0, height - 1);

  for (int y = y1; y <= y2; y += GRID_SPACING) {
    for (int x = x1; x <= x2; x += GRID_SPACING) {
      int px = constrain((int)map(x, 0, width,  0, painting.width  - 1), 0, painting.width  - 1);
      int py = constrain((int)map(y, 0, height, 0, painting.height - 1), 0, painting.height - 1);
      color c = painting.pixels[py * painting.width + px];
      pxParticles.add(new PixelParticle(x, y, c));
    }
  }
  println("Spawned " + pxParticles.size() + " pixel particles");
}

// ── Gradient computation ──────────────────────────────────────────────────────

void computeGradients() {
  int w = painting.width, h = painting.height;
  gradAngle = new float[w * h];
  gradMag   = new float[w * h];
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      int idx  = y * w + x;
      float dx = brightness(painting.pixels[idx+1]) - brightness(painting.pixels[idx-1]);
      float dy = brightness(painting.pixels[idx+w]) - brightness(painting.pixels[idx-w]);
      gradMag[idx]   = sqrt(dx*dx + dy*dy);
      gradAngle[idx] = atan2(dy, dx);
    }
  }
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
  else if (addr.equals("/valence")) valence = msg.get(0).floatValue();
  else if (addr.equals("/arousal")) arousal = msg.get(0).floatValue();
}

void loadPainting() {
  PImage img = loadImage(paintingPath);
  if (img == null) return;
  img.resize(width, height);
  img.loadPixels();
  painting = img;
  computeGradients();
  selX1 = 0; selY1 = 0; selX2 = width; selY2 = height;
  needsRespawn = true;
}

// ── PixelParticle ─────────────────────────────────────────────────────────────

class PixelParticle {
  float ox, oy, x, y, vx, vy;
  color col;
  float life, maxLife;

  PixelParticle(float _x, float _y, color _col) {
    ox = _x; oy = _y; x = _x; y = _y;
    vx = 0; vy = 0;
    col = _col;
    maxLife = random(200, 500);
    life    = random(maxLife);
  }

  void update() {
    int sx  = constrain((int)(x / width  * (painting.width  - 1)), 0, painting.width  - 1);
    int sy  = constrain((int)(y / height * (painting.height - 1)), 0, painting.height - 1);
    int idx = sy * painting.width + sx;

    float mag    = constrain(gradMag[idx] / 80.0, 0, 1);
    float gAngle = gradAngle[idx];

    float edgeX = -sin(gAngle) * mag;
    float edgeY =  cos(gAngle) * mag;

    float ns     = 0.005;
    float t      = frameCount * 0.003 * (1.0 + abs(sArousal) * 0.8);
    float na     = noise(ox * ns, oy * ns, t) * TWO_PI * 3;
    float noiseX = cos(na) * (1.0 - mag);
    float noiseY = sin(na) * (1.0 - mag);

    float springX = (ox - x) * 0.003;
    float springY = (oy - y) * 0.003;

    float speed = (0.6 + abs(sArousal) * 1.8) * lerp(1.0, 0.25, mag);

    vx = vx * 0.9 + (edgeX + noiseX + springX) * speed * 0.1;
    vy = vy * 0.9 + (edgeY + noiseY + springY) * speed * 0.1;

    x += vx; y += vy;
    life--;

    if (life <= 0) {
      x = ox + random(-2, 2); y = oy + random(-2, 2);
      vx = 0; vy = 0;
      maxLife = random(200, 500);
      life    = maxLife;
    }
  }

  void display() {
    float alpha = sin((life / maxLife) * PI) * 210;
    stroke(red(col), green(col), blue(col), alpha);
    strokeWeight(GRID_SPACING * 0.85);
    point(x, y);
  }
}