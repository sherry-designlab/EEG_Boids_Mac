// ===== 统一的 Boids 模拟（实时・回放・光绘共用）=====
// 实时画面、回放、光绘全部使用这一个模拟：
//   - 固定的虚拟世界（LP_WORLD_W × LP_WORLD_H = 1600×1000），与窗口・显示器无关；画面只是把它缩放显示
//   - 固定时间步长：每秒 SIM_HZ 步，按"步数"计时，不依赖帧率和 millis()
//   - 所有随机数来自会话自己的种子（java.util.Random），不使用全局 random()
//   - 输入（A / V / θ比率 / EEG 连接状态）只在指定的步数改变；实时录制时把这个步数写进 CSV（sim_step 列），
//     回放时在同一步送入同一个值 → 与当时的实时画面逐位相同
// 光绘（作品）由 LightPainting.pde 的独立模拟生成（11/14 版的风格），不使用这里的模拟。

final int   SIM_HZ          = 60;    // 每秒模拟步数（与以前的实时帧率 60fps 相同，运动速度不变）
final int   SIM_POP_TICK    = 15;    // 每 15 步调整一次数量（= 以前的 popTickSec 0.25 秒）
final int   SIM_INIT_N      = 300;   // 初始个体数（与以前的 setup() 相同）
final float SIM_CELL        = 64;    // 邻居查找网格的格子大小（≥ 最大感知半径 62）
final int   SIM_WARMUP      = 60;    // 没有起始状态的旧会话：开头预热步数（不曝光）

// 每一步之后的回调（目前未使用，保留给以后需要逐步处理轨迹的功能）
interface SimPainter {
  void segment(Boid b, float x0, float y0, float x1, float y1, float a, float v);
}

class SwarmSim {
  float W = LP_WORLD_W, H = LP_WORLD_H;
  ArrayList<Boid> boids = new ArrayList<Boid>();
  java.util.Random rng;
  PVector center = new PVector(LP_WORLD_W / 2, LP_WORLD_H / 2);
  PVector target = new PVector(LP_WORLD_W / 2, LP_WORLD_H / 2);
  int step = 0;
  int nextId = 0;
  int state = 0;
  float a = 0, v = 0, thetaR = 0;   // 当前输入（正规化 A / V、θ比率）
  boolean connected = true;
  float wake = 1;   // 启动时"慢慢醒来"：0 → 1（约 3 秒），期间最大速度降低

  int gw, gh;   // 邻居网格的格数

  SwarmSim(long seed) {
    rng = new java.util.Random(seed);
    gw = max(1, ceil(W / SIM_CELL));
    gh = max(1, ceil(H / SIM_CELL));
  }

  // 没有保存状态时的初始分布（固定种子 → 每次相同）
  void initCanonical() {
    for (int i = 0; i < SIM_INIT_N; i++) addBoid(rng.nextFloat() * W, rng.nextFloat() * H);
  }

  Boid addBoid(float x, float y) {
    Boid b = new Boid(x, y, rng, W, H);
    b.id = nextId++;
    boids.add(b);
    return b;
  }

  void setInput(float na, float nv, float nth) {
    a = na; v = nv; thetaR = nth;
  }

  // ---- 一步 ----
  void step(SimPainter painter) {
    // EEG 断开：A / V 缓慢回到 0（以前在 updateEmotion() 中每帧进行）
    if (!connected) {
      a = lerp(a, 0, 0.02f);
      v = lerp(v, 0, 0.02f);
    }

    // θ比率的滞后切换（以前的 updateRightBoids）
    if (state == 0 && thetaR > thetaOn) state = 1;
    if (state == 1 && thetaR < thetaOff) state = 0;
    if (state == 1) fractalTarget();
    else target.lerp(center, 0.03f);

    float globalMaxSpeed = map(a, -1, 1, 2.4f, 5.6f);
    if (wake < 1) {
      globalMaxSpeed *= 0.25f + 0.75f * wake;
      wake = min(1, wake + 1.0f / (3 * SIM_HZ));
    }
    float globalMaxForce = map(a, -1, 1, 0.11f, 0.30f);
    float attractStrength = map(a, -1, 1, 0.18f, 1.15f);
    float jitterStrength  = map(a, -1, 1, 0.00f, 0.10f);
    float alignW    = map(a, -1, 1, 0.7f, 2.0f);
    float cohesionW = map(v, -1, 1, 0.75f, 1.75f);
    float separateW = map(v, -1, 1, 2.60f, 1.10f);
    float cohesionRadius = map(v, -1, 1, 38f, 62f);
    float separateRadius = map(v, -1, 1, 40f, 24f);

    if (step % SIM_POP_TICK == 0) adjustPopulation();

    int n = boids.size();
    ensureBuffers(n);
    for (int i = 0; i < n; i++) {
      Boid b = boids.get(i);
      b.maxSpeed = globalMaxSpeed;
      b.maxForce = globalMaxForce;
      b.attractStrength = attractStrength;
      b.jitterStrength = jitterStrength;
      b.cohesionRadius = cohesionRadius;
      b.separateRadius = separateRadius;
      px[i] = b.position.x; py[i] = b.position.y;
      vx[i] = b.velocity.x; vy[i] = b.velocity.y;
    }
    buildGrid(n);
    // 受力计算：全部个体都基于"这一步开始时"的位置和速度（同步更新），
    // 每个个体的计算互不影响 → 可以多线程并行，结果与线程的执行顺序无关（逐位相同）
    final float fMS = globalMaxSpeed, fMF = globalMaxForce, fAS = attractStrength;
    final float fAW = alignW, fCW = cohesionW, fSW = separateW, fCR = cohesionRadius, fSR = separateRadius;
    final float tx = target.x, ty = target.y;
    if (n >= 64) {
      java.util.stream.IntStream.range(0, n).parallel().forEach(i -> computeForce(i, fMS, fMF, fAS, fAW, fCW, fSW, fCR, fSR, tx, ty));
    } else {
      for (int i = 0; i < n; i++) computeForce(i, fMS, fMF, fAS, fAW, fCW, fSW, fCR, fSR, tx, ty);
    }
    // 位置更新按固定顺序进行（抖动的随机数按顺序取用）
    for (int i = 0; i < n; i++) {
      Boid b = boids.get(i);
      b.acceleration.set(fx[i], fy[i]);
      b.update();
      if (painter != null) painter.segment(b, px[i], py[i], b.position.x, b.position.y, a, v);
    }
    step++;
  }

  void adjustPopulation() {
    int desired = constrain(round(map(v, -1, 1, popMin, popMax)), popMin, popMax);
    int current = boids.size();
    if (current == desired) return;
    int stepMax = constrain(round(map(abs(v), 0, 1, 1, 6)), 1, 8);
    if (current < desired) {
      int addN = min(stepMax, desired - current);
      for (int i = 0; i < addN; i++) addBoid(rng.nextFloat() * W, rng.nextFloat() * H);
    } else {
      int removeN = min(stepMax, current - desired);
      for (int i = 0; i < removeN; i++) boids.remove(rng.nextInt(boids.size()));
    }
  }

  // 以前的 updateAttractorWithFractal（frameCount → step，屏幕尺寸 → 虚拟世界）
  void fractalTarget() {
    float zx = map((step * 3) % (int)W, 0, W, -2, 2);
    float zy = map((step * 2) % (int)H, 0, H, -2, 2);
    float cx = -0.7f + 0.10f * v;
    float cy = 0.27015f + 0.06f * a;
    int iter = 0;
    while (zx * zx + zy * zy < 4 && iter < 100) {
      float xtemp = zx * zx - zy * zy + cx;
      zy = 2 * zx * zy + cy;
      zx = xtemp;
      iter++;
    }
    target.x = map(zx, -2, 2, 0, W);
    target.y = map(zy, -2, 2, 0, H);
  }

  // ---- 邻居网格（数组链表，顺序固定）----
  float[] px = new float[0], py, vx, vy, fx, fy;
  int[] cellHead, nextInCell;

  void ensureBuffers(int n) {
    if (px.length >= n) return;
    int m = max(n, 600);
    px = new float[m]; py = new float[m]; vx = new float[m]; vy = new float[m];
    fx = new float[m]; fy = new float[m];
    nextInCell = new int[m];
  }

  int cellX(float x) { return constrain((int)(x / SIM_CELL), 0, gw - 1); }
  int cellY(float y) { return constrain((int)(y / SIM_CELL), 0, gh - 1); }

  void buildGrid(int n) {
    if (cellHead == null) cellHead = new int[gw * gh];
    java.util.Arrays.fill(cellHead, -1);
    for (int i = n - 1; i >= 0; i--) {
      int c = cellY(py[i]) * gw + cellX(px[i]);
      nextInCell[i] = cellHead[c];
      cellHead[c] = i;
    }
  }

  // 一个个体所受的力（追随目标 + 整列 + 结合 + 分离），结果写入 fx[i], fy[i]
  void computeForce(int i, float maxSpeed, float maxForce, float attract,
                    float alignW, float cohW, float sepW, float cohR, float sepR, float tx, float ty) {
    float x = px[i], y = py[i], ux = vx[i], uy = vy[i];
    float ax = 0, ay = 0;

    // seek
    float dx = tx - x, dy = ty - y;
    float d = sqrt(dx * dx + dy * dy);
    if (d >= 1e-6f) {
      float sx = dx / d * maxSpeed - ux, sy = dy / d * maxSpeed - uy;
      float sm = sqrt(sx * sx + sy * sy);
      if (sm > maxForce) { sx = sx / sm * maxForce; sy = sy / sm * maxForce; }
      ax += sx * attract; ay += sy * attract;
    }

    float alR = 50;
    float maxR = max(alR, max(cohR, sepR));
    float maxR2 = maxR * maxR;
    float alX = 0, alY = 0, coX = 0, coY = 0, seX = 0, seY = 0;
    int alN = 0, coN = 0, seN = 0;
    int cx = cellX(x), cy = cellY(y);
    for (int gy = max(0, cy - 1); gy <= min(gh - 1, cy + 1); gy++) {
      for (int gx = max(0, cx - 1); gx <= min(gw - 1, cx + 1); gx++) {
        for (int j = cellHead[gy * gw + gx]; j >= 0; j = nextInCell[j]) {
          if (j == i) continue;
          float ox = px[j] - x, oy = py[j] - y;
          float d2 = ox * ox + oy * oy;
          if (d2 >= maxR2) continue;
          float dd = sqrt(d2);
          if (dd < alR) { alX += vx[j]; alY += vy[j]; alN++; }
          if (dd < cohR) { coX += px[j]; coY += py[j]; coN++; }
          if (dd < sepR && dd > 0) { seX -= ox / d2; seY -= oy / d2; seN++; }
        }
      }
    }
    if (alN > 0) {
      float[] s = steerTo(alX / alN, alY / alN, ux, uy, maxSpeed, maxForce);
      ax += s[0] * alignW; ay += s[1] * alignW;
    }
    if (coN > 0) {
      float[] s = steerTo(coX / coN - x, coY / coN - y, ux, uy, maxSpeed, maxForce);
      ax += s[0] * cohW; ay += s[1] * cohW;
    }
    if (seN > 0) {
      float[] s = steerTo(seX / seN, seY / seN, ux, uy, maxSpeed, maxForce);
      ax += s[0] * sepW; ay += s[1] * sepW;
    }
    fx[i] = ax; fy[i] = ay;
  }

  // Reynolds 的转向：期望方向设为最大速度，减去当前速度，限制在最大力以内
  float[] steerTo(float dx, float dy, float ux, float uy, float maxSpeed, float maxForce) {
    float m = sqrt(dx * dx + dy * dy);
    if (m > 0) { dx = dx / m * maxSpeed; dy = dy / m * maxSpeed; }
    float sx = dx - ux, sy = dy - uy;
    float sm = sqrt(sx * sx + sy * sy);
    if (sm > maxForce) { sx = sx / sm * maxForce; sy = sy / sm * maxForce; }
    return new float[] { sx, sy };
  }

  // ---- 状态的保存与恢复（水族馆式：下次启动时鱼群在原来的位置）----
  JSONObject toJSON() {
    JSONObject o = new JSONObject();
    o.setInt("nextId", nextId);
    o.setInt("state", state);
    o.setBoolean("connected", connected);
    // 浮点数一律以字符串保存（Float.toString ↔ Float.parseFloat 往返逐位相同）
    o.setString("tx", Float.toString(target.x));
    o.setString("ty", Float.toString(target.y));
    o.setString("a", Float.toString(a));
    o.setString("v", Float.toString(v));
    o.setString("theta", Float.toString(thetaR));
    o.setString("wake", Float.toString(wake));
    JSONArray arr = new JSONArray();
    for (Boid b : boids) {
      arr.append(b.id + " " + Float.toString(b.position.x) + " " + Float.toString(b.position.y)
               + " " + Float.toString(b.velocity.x) + " " + Float.toString(b.velocity.y));
    }
    o.setJSONArray("boids", arr);
    return o;
  }

  void fromJSON(JSONObject o) {
    boids.clear();
    nextId = o.getInt("nextId");
    state = o.getInt("state");
    connected = o.getBoolean("connected", true);
    target.set(Float.parseFloat(o.getString("tx")), Float.parseFloat(o.getString("ty")));
    a = Float.parseFloat(o.getString("a"));
    v = Float.parseFloat(o.getString("v"));
    thetaR = Float.parseFloat(o.getString("theta"));
    wake = Float.parseFloat(o.getString("wake", "1"));
    JSONArray arr = o.getJSONArray("boids");
    for (int i = 0; i < arr.size(); i++) {
      String[] e = split(arr.getString(i), ' ');
      Boid b = new Boid(Float.parseFloat(e[1]), Float.parseFloat(e[2]), rng, W, H);
      b.velocity.set(Float.parseFloat(e[3]), Float.parseFloat(e[4]));
      b.id = Integer.parseInt(e[0]);
      boids.add(b);
    }
  }

  // 录制开始：重设随机数种子、步数归零（回放从同一状态、同一随机序列开始）
  void beginRecording(long seed) {
    rng.setSeed(seed);
    for (Boid b : boids) b.rng = rng;
    step = 0;
  }
}

// θ比率（θ / (α+β+θ)）：实时与回放用同一个函数、同一组被接受的样本；StrictMath → 任何电脑结果相同
float simThetaRatio(float[][] bands) {
  if (bands == null) return 0;
  float mT = 0.25f * (bands[1][0] + bands[1][1] + bands[1][2] + bands[1][3]);
  float mA = 0.25f * (bands[2][0] + bands[2][1] + bands[2][2] + bands[2][3]);
  float mB = 0.25f * (bands[3][0] + bands[3][1] + bands[3][2] + bands[3][3]);
  float pT = (float)StrictMath.pow(10, mT);
  float pA = (float)StrictMath.pow(10, mA);
  float pB = (float)StrictMath.pow(10, mB);
  return pT / (pA + pB + pT + 1e-12f);
}

// ===== 会话的时间线：CSV（+ 会话 JSON）→ 按步数排列的输入 =====
class SimTimeline {
  int[] steps;          // 各行生效的步数
  float[] av, vv, th;   // 各行的输入
  int[] evStep;         // 连接状态变化的步数
  boolean[] evConn;
  JSONObject startState = null;   // 录制开始时的鱼群（新会话才有）
  long seed;
  int paintFrom;        // 从这一步开始曝光
  int totalSteps;

  int rowCount() { return steps.length; }
}

SimTimeline simLoadTimeline(File csv) {
  String[] lines = loadStrings(csv.getAbsolutePath());
  if (lines == null || lines.length < 2) return null;
  String[] head = split(lines[0], ',');
  int colStep = -1, colTheta0 = -1;
  for (int i = 0; i < head.length; i++) {
    String h = head[i].trim();
    if (h.equals("sim_step")) colStep = i;
    if (h.equals("theta_TP9")) colTheta0 = i;
  }
  JSONObject meta = sessionMetaLoad(csv);
  JSONObject start = (meta != null && meta.hasKey("swarm_start")) ? meta.getJSONObject("swarm_start") : null;
  boolean hasStart = start != null && colStep >= 0;

  ArrayList<float[]> rows = new ArrayList<float[]>();
  for (int i = 1; i < lines.length; i++) {
    String[] p = split(lines[i], ',');
    if (p.length < 5) continue;
    try {
      float t = Float.parseFloat(p[0]);
      float a = Float.parseFloat(p[3]);
      float v = Float.parseFloat(p[4]);
      if (Float.isNaN(a) || Float.isNaN(v)) continue;
      float th = 0;
      if (colTheta0 >= 0 && p.length >= colTheta0 + 12) {
        float[][] bands = new float[5][4];
        for (int b = 1; b <= 3; b++)
          for (int e = 0; e < 4; e++) bands[b][e] = Float.parseFloat(p[colTheta0 + (b - 1) * 4 + e]);
        th = simThetaRatio(bands);
        if (Float.isNaN(th)) th = 0;
      }
      int st;
      if (hasStart && p.length > colStep) st = Integer.parseInt(p[colStep].trim());
      else st = SIM_WARMUP + round(t * SIM_HZ / 1000.0f);
      rows.add(new float[] { st, a, v, th });
    } catch (Exception e) {
      continue;
    }
  }
  if (rows.size() < 2) return null;

  SimTimeline tl = new SimTimeline();
  int n = rows.size();
  tl.steps = new int[n]; tl.av = new float[n]; tl.vv = new float[n]; tl.th = new float[n];
  for (int i = 0; i < n; i++) {
    float[] r = rows.get(i);
    tl.steps[i] = (int)r[0]; tl.av[i] = r[1]; tl.vv[i] = r[2]; tl.th[i] = r[3];
  }
  ArrayList<int[]> ev = new ArrayList<int[]>();
  if (hasStart && meta.hasKey("events")) {
    JSONArray arr = meta.getJSONArray("events");
    for (int i = 0; i < arr.size(); i++) {
      JSONObject e = arr.getJSONObject(i);
      ev.add(new int[] { e.getInt("step"), e.getBoolean("connected") ? 1 : 0 });
    }
  }
  tl.evStep = new int[ev.size()];
  tl.evConn = new boolean[ev.size()];
  for (int i = 0; i < ev.size(); i++) { tl.evStep[i] = ev.get(i)[0]; tl.evConn[i] = ev.get(i)[1] == 1; }

  if (hasStart) {
    tl.startState = start;
    tl.seed = meta.getLong("swarm_seed");
    tl.paintFrom = 0;
    tl.totalSteps = meta.hasKey("end_step") ? meta.getInt("end_step") : tl.steps[n - 1] + SIM_HZ;
  } else {
    tl.seed = lpSeedFor(csv.getName());
    tl.paintFrom = SIM_WARMUP;
    tl.totalSteps = tl.steps[n - 1] + SIM_HZ;
  }
  return tl;
}

// 按时间线建立模拟（起始状态）
SwarmSim simForTimeline(SimTimeline tl) {
  SwarmSim sim = new SwarmSim(tl.seed);
  if (tl.startState != null) {
    sim.fromJSON(tl.startState);
    sim.beginRecording(tl.seed);   // 与录制开始时相同：同一种子、步数从 0 开始
  } else {
    sim.initCanonical();
    sim.setInput(tl.av[0], tl.vv[0], tl.th[0]);
  }
  return sim;
}

// 时间线的播放游标：把 [sim.step] 之前应生效的输入送进模拟，再走一步
class SimCursor {
  SimTimeline tl;
  SwarmSim sim;
  int row = 0, ev = 0;
  SimCursor(SimTimeline tl) {
    this.tl = tl;
    sim = simForTimeline(tl);
  }
  boolean done() { return sim.step >= tl.totalSteps; }
  void stepOnce(SimPainter p) {
    while (ev < tl.evStep.length && tl.evStep[ev] <= sim.step) { sim.connected = tl.evConn[ev]; ev++; }
    while (row < tl.steps.length && tl.steps[row] <= sim.step) { sim.setInput(tl.av[row], tl.vv[row], tl.th[row]); row++; }
    sim.step(sim.step >= tl.paintFrom ? p : null);
  }
  float progress() { return constrain(sim.step / (float)max(1, tl.totalSteps), 0, 1); }
}
