// ===== 光绘静止画生成（11/14 版的算法，11/16 恢复）=====
// 把一次会话的 A/V 时间序列重新驱动一群 Boids（时间压缩为 2000 步，个体数为实时的 20%），
// 将全部运动轨迹像"长曝光"一样累积到一张图上，得到光绘风格的静止画。
// 光绘的模拟独立于实时・回放（SwarmSim.pde）：调整实时 Boids 的规则不会影响光绘。
// 这里使用的 Boid.flock / seek / update 只被光绘使用（实时・回放使用 SwarmSim 的受力计算）。
// 作品存档与生成：Artwork.pde。
// ※ 修改下列参数会改变光绘的样子：请同时把 Artwork.pde 的 LP_STYLE_VERSION 加 1（全部作品按新风格重新生成）。

// 虚拟画布：光绘・回放的模拟在这个固定大小的空间里进行，与显示器的分辨率无关，
// 因此在任何电脑・显示器上，同一会话都得到同一张光绘。
float LP_WORLD_W = 1600;
float LP_WORLD_H = 1000;

int   LP_IMG_W       = 960;    // 缩略图的宽（高按虚拟画布比例 = 600）
int   LP_EXPORT_W    = 3840;   // 作品的宽（高 = 2400）
float LP_WHITE_MIX   = 0.4f;   // 光绘中"越快越白"的程度（实时画面为 0.8；光绘是累积的，0.8 会把颜色冲淡成白色）
float LP_POP_SCALE   = 0.2f;   // 模拟用 Boids 数量 = 实时数量(popMin~popMax) × 该比例（画廊与回放共用）
int   LP_STEP_BUDGET = 2000;   // 整个会话的模拟总步数上限（长会话会被压缩）
int   LP_WARMUP      = 60;     // 预热步数（不曝光，避免初始随机散点）
float LP_GLOW        = 0.8f;   // 辉光强度
int   LP_GLOW_RADIUS = 3;      // 辉光模糊半径（以宽 600px 为基准，按分辨率自动缩放，使不同分辨率的观感一致）

// ===== 可复现性 =====
// 同一个会话（同一个 CSV）无论生成多少次、在画廊还是回放中，都必须得到同一张光绘。
// 因此：每次模拟使用自己的随机数生成器，种子由文件名决定（同一文件 → 同一种子），
// 不使用全局 random()（全局随机数会被实时画面和其他线程同时消耗，顺序无法保证）。
long lpSeedFor(String fileName) {
  return fileName.replace(".csv", "").hashCode();
}

// 读取CSV中正规化后的 A/V（第4、5列：arousal_norm, valence_norm）
ArrayList<float[]> lpLoadSession(File csv) {
  ArrayList<float[]> data = new ArrayList<float[]>();
  String[] lines = loadStrings(csv.getAbsolutePath());
  if (lines == null) return data;
  for (int i = 1; i < lines.length; i++) {
    String[] p = split(lines[i], ',');
    if (p.length < 5) continue;
    try {
      float a = Float.parseFloat(p[3]);
      float v = Float.parseFloat(p[4]);
      if (Float.isNaN(a) || Float.isNaN(v)) continue;
      data.add(new float[]{ a, v });
    } catch (NumberFormatException e) {
      continue;
    }
  }
  return data;
}

// 生成光绘图（取景范围 = 全屏，与全屏实时画面一致）
// outW：输出宽度。分辨率只影响精细程度，不影响构图（模拟在虚拟画布中进行）
PImage lpRender(ArrayList<float[]> data, long seed, int outW) {
  java.util.Random rng = new java.util.Random(seed);
  int W = outW;
  int H = lpHeightFor(outW);
  int N = W * H;
  float[] accR = new float[N];
  float[] accG = new float[N];
  float[] accB = new float[N];

  // 时间压缩：数据点多时抽样，少时每点多模拟几步
  int n = data.size();
  int stride = max(1, ceil(n / (float)LP_STEP_BUDGET));
  int used = ceil(n / (float)stride);
  int stepsPer = constrain(round(LP_STEP_BUDGET / (float)used), 1, 60);

  // 与全屏实时画面相同的初始条件
  PVector center = new PVector(LP_WORLD_W / 2, LP_WORLD_H / 2);
  PVector target = center.copy();
  ArrayList<Boid> boids = new ArrayList<Boid>();
  int initN = max(10, round(300 * LP_POP_SCALE));
  for (int i = 0; i < initN; i++) {
    boids.add(new Boid(rng.nextFloat() * LP_WORLD_W, rng.nextFloat() * LP_WORLD_H, rng, LP_WORLD_W, LP_WORLD_H));
  }

  int step = 0;
  for (int i = 0; i < n; i += stride) {
    float a = data.get(i)[0];
    float v = data.get(i)[1];
    int reps = (i == 0) ? LP_WARMUP + stepsPer : stepsPer;
    for (int s = 0; s < reps; s++) {
      boolean expose = !(i == 0 && s < LP_WARMUP);
      lpSimStep(boids, target, center, a, v, step, expose, accR, accG, accB, W, H, LP_POP_SCALE, rng);
      step++;
    }
  }

  return lpFinish(accR, accG, accB, W, H);
}

// 模拟一步：参数映射与 updateRightBoids() 一致
// （CSV中没有theta，与原左屏回放相同按 state=0 处理：目标点回归中心）
void lpSimStep(ArrayList<Boid> boids, PVector target, PVector center, float a, float v,
               int step, boolean expose,
               float[] accR, float[] accG, float[] accB, int W, int H, float popScale, java.util.Random rng) {
  target.lerp(center, 0.03f);

  float globalMaxSpeed = map(a, -1, 1, 2.4f, 5.6f);
  float globalMaxForce = map(a, -1, 1, 0.11f, 0.30f);
  float attractStrength = map(a, -1, 1, 0.18f, 1.15f);
  float jitterStrength  = map(a, -1, 1, 0.00f, 0.10f);
  float alignW    = map(a, -1, 1, 0.7f, 2.0f);
  float cohesionW = map(v, -1, 1, 0.75f, 1.75f);
  float separateW = map(v, -1, 1, 2.60f, 1.10f);
  float cohesionRadius = map(v, -1, 1, 38f, 62f);
  float separateRadius = map(v, -1, 1, 40f, 24f);

  // 数量调整：约每15步一次（相当于实时的 popTickSec=0.25s @60fps）
  if (step % 15 == 0) {
    int pMin = max(1, round(popMin * popScale));
    int pMax = max(pMin, round(popMax * popScale));
    int desired = constrain(round(map(v, -1, 1, pMin, pMax)), pMin, pMax);
    int stepMax = constrain(round(map(abs(v), 0, 1, 1, 6)), 1, 8);
    int current = boids.size();
    if (current < desired) {
      int addN = min(stepMax, desired - current);
      for (int i = 0; i < addN; i++) boids.add(new Boid(rng.nextFloat() * LP_WORLD_W, rng.nextFloat() * LP_WORLD_H, rng, LP_WORLD_W, LP_WORLD_H));
    } else if (current > desired) {
      int removeN = min(stepMax, current - desired);
      for (int i = 0; i < removeN; i++) boids.remove(rng.nextInt(boids.size()));
    }
  }

  // 颜色与亮度：与实时画面（Boid.showOn）相同的配色
  //   愉悦度低 → 天蓝 (102,204,255)，高 → 粉色 (255,102,204)；游得越快越接近白色（每条鱼各自计算）
  float t = constrain((v + 1) * 0.5f, 0, 1);
  float intensity = map(a, -1, 1, 120, 220) / 255.0f;
  float br = lerp(BOID_COLD_R, BOID_WARM_R, t), bg = lerp(BOID_COLD_G, BOID_WARM_G, t), bb = lerp(BOID_COLD_B, BOID_WARM_B, t);

  float sx = W / LP_WORLD_W;
  float sy = H / LP_WORLD_H;
  // 线条粗细随分辨率等比放大（以宽 960px 时 1px 为基准），高分辨率输出的观感与画廊一致
  float brush = W / 960.0f;
  float stepLen = max(0.5f, brush * 0.5f);   // 线段上采样点的间距（px）

  for (Boid b : boids) {
    b.maxSpeed = globalMaxSpeed;
    b.maxForce = globalMaxForce;
    b.attractStrength = attractStrength;
    b.jitterStrength = jitterStrength;
    b.cohesionRadius = cohesionRadius;
    b.separateRadius = separateRadius;

    float px = b.position.x, py = b.position.y;
    b.seek(target);
    b.flock(boids, alignW, cohesionW, separateW);
    b.update();

    if (!expose) continue;

    float sr = constrain(b.velocity.mag() / max(b.maxSpeed, 1e-6f), 0, 1) * LP_WHITE_MIX;
    float cr = lerp(br, 255, sr) / 255.0f * intensity;
    float cg = lerp(bg, 255, sr) / 255.0f * intensity;
    float cb = lerp(bb, 255, sr) / 255.0f * intensity;

    // 把这一步的位移线段"曝光"到画布（全屏取景）
    float x0 = px * sx, y0 = py * sy;
    float x1 = b.position.x * sx, y1 = b.position.y * sy;
    float dx = x1 - x0, dy = y1 - y0;
    float len = sqrt(dx*dx + dy*dy);
    if (len > 20 * brush) continue;  // 穿越画布边缘的跳变，不画
    int ns = max(1, ceil(len / stepLen));
    for (int k = 0; k < ns; k++) {
      float u = (k + 0.5f) / ns;
      if (brush <= 1.25f) lpSplat(accR, accG, accB, W, H, x0 + dx*u, y0 + dy*u, cr/ns, cg/ns, cb/ns);
      else lpSplatBrush(accR, accG, accB, W, H, x0 + dx*u, y0 + dy*u, cr/ns, cg/ns, cb/ns, brush * 0.7f);
    }
  }
}

// 双线性累加一个光点
void lpSplat(float[] R, float[] G, float[] B, int W, int H,
             float x, float y, float r, float g, float b) {
  if (!(x >= 0 && y >= 0 && x < W - 1 && y < H - 1)) return;  // 也排除NaN
  int ix = (int)x, iy = (int)y;
  float fx = x - ix, fy = y - iy;
  int i00 = iy * W + ix, i10 = i00 + 1, i01 = i00 + W, i11 = i01 + 1;
  float w00 = (1-fx)*(1-fy), w10 = fx*(1-fy), w01 = (1-fx)*fy, w11 = fx*fy;
  R[i00] += r*w00; R[i10] += r*w10; R[i01] += r*w01; R[i11] += r*w11;
  G[i00] += g*w00; G[i10] += g*w10; G[i01] += g*w01; G[i11] += g*w11;
  B[i00] += b*w00; B[i10] += b*w10; B[i01] += b*w01; B[i11] += b*w11;
}

// 高分辨率用：以半径 rad 的圆盘（中心重、边缘轻）累加一个光点，总光量与 lpSplat 相同
void lpSplatBrush(float[] R, float[] G, float[] B, int W, int H,
                  float x, float y, float r, float g, float b, float rad) {
  if (!(x >= 0 && y >= 0 && x < W && y < H)) return;
  int x0 = max(0, (int)floor(x - rad)), x1 = min(W - 1, (int)ceil(x + rad));
  int y0 = max(0, (int)floor(y - rad)), y1 = min(H - 1, (int)ceil(y + rad));
  float sum = 0;
  for (int yy = y0; yy <= y1; yy++)
    for (int xx = x0; xx <= x1; xx++) {
      float d = sqrt((xx - x) * (xx - x) + (yy - y) * (yy - y));
      if (d < rad) sum += 1 - d / rad;
    }
  if (sum <= 0) return;
  for (int yy = y0; yy <= y1; yy++)
    for (int xx = x0; xx <= x1; xx++) {
      float d = sqrt((xx - x) * (xx - x) + (yy - y) * (yy - y));
      if (d >= rad) continue;
      float w = (1 - d / rad) / sum;
      int i = yy * W + xx;
      R[i] += r * w;
      G[i] += g * w;
      B[i] += b * w;
    }
}

// 可分离盒式模糊（滑动窗口求和：计算量与半径无关，4K 也能在几秒内完成）
float[] lpBlur(float[] src, int W, int H, int r) {
  float[] tmp = new float[W*H];
  float[] out = new float[W*H];
  float norm = 1.0f / (2*r + 1);
  for (int y = 0; y < H; y++) {
    int row = y * W;
    float s = 0;
    for (int k = -r; k <= r; k++) s += src[row + constrain(k, 0, W - 1)];
    for (int x = 0; x < W; x++) {
      tmp[row + x] = s * norm;
      s += src[row + min(x + r + 1, W - 1)] - src[row + max(x - r, 0)];
    }
  }
  for (int x = 0; x < W; x++) {
    float s = 0;
    for (int k = -r; k <= r; k++) s += tmp[constrain(k, 0, H - 1) * W + x];
    for (int y = 0; y < H; y++) {
      out[y * W + x] = s * norm;
      s += tmp[min(y + r + 1, H - 1) * W + x] - tmp[max(y - r, 0) * W + x];
    }
  }
  return out;
}

int lpHeightFor(int w) {
  return max(1, round(w * LP_WORLD_H / LP_WORLD_W));
}

// 辉光 + 自动曝光：把累积的光量转成最终图像（画廊缩图与回放结尾共用）
PImage lpFinish(float[] accR, float[] accG, float[] accB, int W, int H) {
  int N = W * H;
  // 辉光：模糊两次后叠加
  int gr = max(1, round(LP_GLOW_RADIUS * W / 600.0f));
  float[] gR = lpBlur(lpBlur(accR, W, H, gr), W, H, gr);
  float[] gG = lpBlur(lpBlur(accG, W, H, gr), W, H, gr);
  float[] gB = lpBlur(lpBlur(accB, W, H, gr), W, H, gr);
  for (int i = 0; i < N; i++) {
    accR[i] += LP_GLOW * gR[i];
    accG[i] += LP_GLOW * gG[i];
    accB[i] += LP_GLOW * gB[i];
  }

  // 自动曝光：以亮度99.5百分位作为参考，再用 1-exp(-kx) 做胶片式色调映射
  // （高分辨率时每隔若干像素取样计算百分位，结果与全量计算几乎相同，速度快得多）
  int stride = max(1, N / 600000);
  float[] lum = new float[N / stride + 1];
  int cnt = 0;
  for (int i = 0; i < N; i += stride) {
    float L = 0.299f*accR[i] + 0.587f*accG[i] + 0.114f*accB[i];
    if (L > 0) lum[cnt++] = L;
  }

  PImage img = createImage(W, H, RGB);
  img.loadPixels();
  if (cnt == 0) {
    for (int i = 0; i < N; i++) img.pixels[i] = 0xFF000000;
  } else {
    Arrays.sort(lum, 0, cnt);
    float ref = lum[(int)(0.995f * (cnt - 1))];
    float k = 2.3f / max(ref, 1e-9f);
    for (int i = 0; i < N; i++) {
      // StrictMath：在任何电脑上结果逐位相同
      int r = (int)(255 * (1 - StrictMath.exp(-k * accR[i])));
      int g = (int)(255 * (1 - StrictMath.exp(-k * accG[i])));
      int b = (int)(255 * (1 - StrictMath.exp(-k * accB[i])));
      img.pixels[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
    }
  }
  img.updatePixels();
  return img;
}
