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

// ── palm-driven flow ────────────────────────────────────────────────────────
float   palmX = 0.5, palmY = 0.5;      // last known palm position (0-1, raw camera-frame coords)
float   palmDX = 0, palmDY = 0;        // raw frame-to-frame delta (this is the "movement" signal)
float   sPalmDX = 0, sPalmDY = 0;      // smoothed delta -> what actually drives particle direction
int     lastHandMsgTime = 0;           // millis() of last /palm_x, /palm_y or /hand_size received
final float PALM_GAIN    = 60.0;       // scales tiny per-frame deltas up to a usable force
final float PALM_PUSH    = 1.5;        // steady-state push ~= PALM_PUSH*10 px/frame (see vx/vy decay in update()) — deliberately strong so a swipe is obvious
final int   PALM_TIMEOUT = 200;        // ms of silence => treat hand as gone, push/zoom relax to neutral

// ── palm-distance zoom ──────────────────────────────────────────────────────
float   handSize = 0.0;                // raw /hand_size (~0.1 far - 0.4 close, 0 = no hand)
float   sZoom = 1.0;                   // smoothed zoom actually applied around canvas centre

// ── fast-approach scatter ───────────────────────────────────────────────────
float   scatterEnergy = 0;             // 0-1, spikes on a fast approach then decays
final float SCATTER_DELTA_THRESHOLD = 0.03; // per-message hand_size jump counted as "fast"
final float SCATTER_STRENGTH        = 6.0;  // outward push at full scatterEnergy
final float SCATTER_DECAY           = 0.90; // per-frame decay of the burst

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

  boolean handPresent = millis() - lastHandMsgTime <= PALM_TIMEOUT;
  if (!handPresent) {
    palmDX = 0;
    palmDY = 0;
  }
  sPalmDX = lerp(sPalmDX, palmDX, 0.5);
  sPalmDY = lerp(sPalmDY, palmDY, 0.5);
  float palmForceX = constrain(sPalmDX * PALM_GAIN, -1, 1);
  float palmForceY = constrain(sPalmDY * PALM_GAIN, -1, 1);

  // closer palm (bigger hand_size) => zoom in; no hand => relax back to 1.0
  float targetZoom = handPresent ? map(handSize, 0.1, 0.4, 0.7, 1.6) : 1.0;
  sZoom = lerp(sZoom, constrain(targetZoom, 0.5, 2.0), 0.05);

  scatterEnergy *= SCATTER_DECAY;   // burst fades on its own; oscEvent re-tops it up while approach stays fast

  if (needsRespawn && painting != null) {
    spawnFromBox();
    needsRespawn = false;
  }

  fill(0, 0, 0, 10);
  noStroke();
  rect(0, 0, width, height);

  pushMatrix();
  translate(width / 2.0, height / 2.0);
  scale(sZoom);
  translate(-width / 2.0, -height / 2.0);
  for (PixelParticle p : pxParticles) {
    p.update(palmForceX, palmForceY);
    p.display();
  }
  popMatrix();

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
  // draws the actual painting once as the fresh backdrop — the ongoing per-frame black
  // fade in draw() then lets it slowly dissolve into the particle trails over the next
  // ~20s, so this sketch alone shows the artwork (no separate Python "Painting" window needed)
  image(painting, 0, 0);

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
  else if (addr.equals("/palm_x")) {
    float nx = msg.get(0).floatValue();
    palmDX = nx - palmX;          // delta since last message = instantaneous x-movement
    palmX  = nx;
    lastHandMsgTime = millis();   // mark hand as "seen" so draw() doesn't decay push/zoom to neutral
  }
  else if (addr.equals("/palm_y")) {
    float ny = msg.get(0).floatValue();
    palmDY = ny - palmY;          // delta since last message = instantaneous y-movement
    palmY  = ny;
    lastHandMsgTime = millis();
  }
  else if (addr.equals("/hand_size")) {
    float ns    = msg.get(0).floatValue();
    float delta = ns - handSize;             // growth rate = how fast the palm is approaching
    handSize = ns;
    lastHandMsgTime = millis();
    if (delta > SCATTER_DELTA_THRESHOLD) scatterEnergy = 1.0;
  }
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

  // palmForceX/Y: unit-ish vector of the palm's current movement direction,
  // magnitude ~0 when the palm is still or off-screen (see draw())
  void update(float palmForceX, float palmForceY) {
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

    // radial push away from screen centre, ~0 unless a fast approach just fired scatterEnergy
    float cx = x - width / 2.0, cy = y - height / 2.0;
    float cd = sqrt(cx * cx + cy * cy);
    float scatterX = cd > 1 ? (cx / cd) * scatterEnergy * SCATTER_STRENGTH : 0;
    float scatterY = cd > 1 ? (cy / cd) * scatterEnergy * SCATTER_STRENGTH : 0;

    // palm term is kept out of the "* speed * 0.1" scaling (which shrinks near high-gradient
    // painting areas) so a swipe always gives the same strong, obvious push, ~0 when palm is still
    vx = vx * 0.9 + (edgeX + noiseX + springX) * speed * 0.1 + palmForceX * PALM_PUSH + scatterX;
    vy = vy * 0.9 + (edgeY + noiseY + springY) * speed * 0.1 + palmForceY * PALM_PUSH + scatterY;

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