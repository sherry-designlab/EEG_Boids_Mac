// ===== 进化：物种（Swarm Chemistry 式）=====
// 参考：Sayama, H. (2009) Swarm Chemistry. Artificial Life 15(1)；Sayama (2011) Seeking open-ended evolution in Swarm Chemistry.
//
// 【通道分离】看的人要能分清"现在的情绪"与"过去的历史"：
//   情绪（此刻、立即）：颜色冷暖（V）、透明度・速度・力・抖动的整体强度（A）、身体粗细（V 低 → 变细）
//                       → 全体个体同时变化，与物种无关
//   历史（物种、累积）：群体由哪些物种组成、每个物种的运动方式（recipe）、各物种的数量
//                       → 形态（团・带・分群・混合）与身体大小，与此刻的情绪无关
//   ※ 原系统中由情绪控制的"聚合／分离"、吸引点（中心・分形）、个体数，在进化版中改由物种决定或固定，
//     这样"A/V 不变、历史不同 → 只有形态不同"，"历史不变、A/V 不同 → 只有颜色・速度不同"。
//
// 【物种 = 一次会话】
//   每次瞑想（会话）结束时，由这次的情绪特征（平均 A / V、波动）生成一个新物种：
//     平均 A → 速度・对齐的强度・身体大小（平静 → 大而慢）
//     平均 V → 聚合／分离的强度与半径・对其他物种的开放度（V 低 → 只和同种在一起、彼此保持距离）
//     波动   → 游动的摇摆（不稳定的会话 → 摇摆大）
//     每个物种还有自己缓慢漂移的"栖息点"（周期约 1〜3 分），群体不再只围着一个中心旋转
//   新物种带 EVO_NEW_K 个个体诞生（从和这次情绪最不共鸣的物种中转化而来）。始祖物种 = A=V=0。
//
// 【情绪直接决定兴衰】只在瞑想（录制）中、EEG 连接时：
//   每 EVO_TICK 步（4 秒）一次：按"数量 × 与当前情绪的共鸣"选一个兴盛的物种（分裂出 1 个），
//   按"数量 × (1 − 共鸣)"选一个衰退的物种（失去 1 个）。共鸣 = 当前 A/V 与物种诞生时的 A/V 越近越大。
//   个体总数固定（EVO_N），每个物种至少保留 1 个（遗存），物种数超过上限时最少的物种灭绝（并入最相近的物种）。
//
// 【历史 = 所有会话】启动时按时间顺序把所有会话 CSV（含导入的数据）重新喂给同一规则（只算物种的数量），
//   得到现在的物种构成。同样的数据永远得到同样的结果；删除・导入会话后下次启动自动反映。
//   实时的进化只在录制中发生，并使用与历史计算相同的随机数序列 → 实时结果 = 下次启动时的重算结果。
//
// 光绘（作品）完全不受影响（LightPainting.pde 的独立模拟）。进化版之前录制的会话按原系统回放。

final int   EVO_N            = 240;   // 个体总数（固定）
final int   EVO_TICK         = 240;   // 兴衰判定的间隔（步）= 4 秒
final int   EVO_NEW_K        = 16;    // 新物种诞生时的个体数
final int   EVO_MAX_SPECIES  = 16;    // 物种数上限
final float EVO_RES_SIGMA    = 0.6f;  // 共鸣的宽度（A/V 平面上的距离）
final float EVO_ATTRACT      = 0.35f; // 向栖息点的吸引（固定，不随情绪变化）
final long  EVO_FOUNDER_SEED = 20261118L;

class Species {
  int id;            // = 诞生的世代（始祖 0）
  float homeA, homeV;           // 诞生时的情绪（共鸣的中心）
  float speed, alignW, cohW, sepW, cohR, sepR, wander, open, size;   // recipe
  float fx, fy, phx, phy, rad;  // 栖息点的漂移
  int count = 0;     // 历史计算用的个体数

  float anchorX(int step, float W) { return W * 0.5f + W * rad * (float)StrictMath.sin(step * fx + phx); }
  float anchorY(int step, float H) { return H * 0.5f + H * rad * (float)StrictMath.sin(step * fy + phy); }

  String encode() {
    float[] p = { homeA, homeV, speed, alignW, cohW, sepW, cohR, sepR, wander, open, size, fx, fy, phx, phy, rad };
    StringBuilder sb = new StringBuilder();
    sb.append(id).append(' ').append(count);
    for (float x : p) sb.append(' ').append(Float.toString(x));
    return sb.toString();
  }
  Species copy() { return evoDecodeSpecies(encode()); }
}

Species evoDecodeSpecies(String s) {
  String[] e = split(s, ' ');
  Species sp = new Species();
  sp.id = Integer.parseInt(e[0]);
  sp.count = Integer.parseInt(e[1]);
  float[] p = new float[16];
  for (int i = 0; i < 16; i++) p[i] = Float.parseFloat(e[2 + i]);
  sp.homeA = p[0]; sp.homeV = p[1]; sp.speed = p[2]; sp.alignW = p[3]; sp.cohW = p[4]; sp.sepW = p[5];
  sp.cohR = p[6]; sp.sepR = p[7]; sp.wander = p[8]; sp.open = p[9]; sp.size = p[10];
  sp.fx = p[11]; sp.fy = p[12]; sp.phx = p[13]; sp.phy = p[14]; sp.rad = p[15];
  return sp;
}

// 会话的情绪特征 → 物种（加少量突变）
Species evoMakeSpecies(int id, float ma, float mv, float sa, float sv, java.util.Random r) {
  Species s = new Species();
  s.id = id;
  s.homeA = ma; s.homeV = mv;
  s.speed  = evoMut(map(ma, -1, 1, 0.75f, 1.25f), 0.5f, r);
  s.alignW = evoMut(map(ma, -1, 1, 0.7f, 2.0f), 1.3f, r);
  s.size   = evoMut(map(ma, -1, 1, 1.45f, 0.75f), 0.7f, r);
  s.cohW   = evoMut(map(mv, -1, 1, 0.75f, 1.75f), 1.0f, r);
  s.sepW   = evoMut(map(mv, -1, 1, 2.6f, 1.1f), 1.5f, r);
  s.cohR   = evoMut(map(mv, -1, 1, 38, 62), 24, r);
  s.sepR   = evoMut(map(mv, -1, 1, 40, 24), 16, r);
  s.open   = constrain(evoMut(map(mv, -1, 1, 0.2f, 1.0f), 0.8f, r), 0.1f, 1);
  s.wander = constrain(evoMut(map(constrain(sa + sv, 0, 1.2f), 0, 1.2f, 0, 0.12f), 0.12f, r), 0, 0.15f);
  s.fx  = 0.0006f + r.nextFloat() * 0.001f;   // 周期约 1〜3 分
  s.fy  = 0.0006f + r.nextFloat() * 0.001f;
  s.phx = r.nextFloat() * TWO_PI;
  s.phy = r.nextFloat() * TWO_PI;
  s.rad = 0.12f + r.nextFloat() * 0.16f;
  return s;
}
// 突变：取值范围的 5%（标准差）
float evoMut(float x, float range, java.util.Random r) { return x + (float)r.nextGaussian() * 0.05f * range; }

float evoResonance(Species s, float a, float v) {
  float da = a - s.homeA, dv = v - s.homeV;
  return (float)StrictMath.exp(-(da * da + dv * dv) / (2 * EVO_RES_SIGMA * EVO_RES_SIGMA));
}

// ---- 兴衰（物种层面；实时与历史计算共用，随机数的使用顺序完全相同）----
// 返回 {兴盛的物种, 衰退的物种}（下标）；不发生时返回 null
int[] evoChooseFlow(ArrayList<Species> sp, int[] counts, float a, float v, java.util.Random r) {
  int n = sp.size();
  if (n < 2) return null;
  float[] up = new float[n], down = new float[n];
  float su = 0, sd = 0;
  for (int i = 0; i < n; i++) {
    float res = evoResonance(sp.get(i), a, v);
    up[i] = counts[i] * res;
    down[i] = counts[i] > 1 ? counts[i] * (1 - res) : 0;   // 至少保留 1 个
    su += up[i]; sd += down[i];
  }
  float ru = r.nextFloat() * su, rd = r.nextFloat() * sd;   // 两个随机数始终都取（保持序列一致）
  if (su <= 0 || sd <= 0) return null;
  int iu = evoPickWeighted(up, ru), id = evoPickWeighted(down, rd);
  if (iu == id) return null;
  return new int[] { iu, id };
}

int evoPickWeighted(float[] w, float x) {
  for (int i = 0; i < w.length; i++) {
    if (x < w[i]) return i;
    x -= w[i];
  }
  for (int i = w.length - 1; i >= 0; i--) if (w[i] > 0) return i;
  return 0;
}

// ---- 会话结束：新物种诞生（+ 必要时灭绝）。实时与历史计算共用 ----
class EvoPlan {
  Species born;
  int[] take;            // 从各物种转化给新物种的个数
  int extinct = -1;      // 灭绝的物种（下标），-1 = 无
  int extinctTo = -1;    // 灭绝物种的个体并入的物种（下标）
}

class SessionPrint {
  float ma, mv, sa, sv, minutes;
}

SessionPrint evoPrintOf(SimTimeline tl) {
  SessionPrint p = new SessionPrint();
  int n = tl.av.length;
  double sa = 0, sv = 0, qa = 0, qv = 0;
  for (int i = 0; i < n; i++) { sa += tl.av[i]; sv += tl.vv[i]; qa += tl.av[i] * tl.av[i]; qv += tl.vv[i] * tl.vv[i]; }
  p.ma = (float)(sa / n); p.mv = (float)(sv / n);
  p.sa = (float)Math.sqrt(Math.max(0, qa / n - p.ma * p.ma));
  p.sv = (float)Math.sqrt(Math.max(0, qv / n - p.mv * p.mv));
  p.minutes = tl.totalSteps / (float)(SIM_HZ * 60);
  return p;
}

EvoPlan evoPlanGeneration(ArrayList<Species> sp, int[] counts, SessionPrint p, int gen, String name) {
  java.util.Random r = new java.util.Random(lpSeedFor(name) ^ 0x5DEECE66DL);
  EvoPlan plan = new EvoPlan();
  plan.born = evoMakeSpecies(gen, p.ma, p.mv, p.sa, p.sv, r);
  int n = sp.size();
  int[] c = counts.clone();
  plan.take = new int[n];
  float[] w = new float[n];
  for (int k = 0; k < EVO_NEW_K; k++) {
    float s = 0;
    for (int i = 0; i < n; i++) { w[i] = c[i] > 1 ? c[i] * (1 - evoResonance(sp.get(i), p.ma, p.mv)) + 1e-6f : 0; s += w[i]; }
    float x = r.nextFloat() * s;
    if (s <= 0) break;
    int i = evoPickWeighted(w, x);
    c[i]--; plan.take[i]++;
  }
  if (n + 1 > EVO_MAX_SPECIES) {
    // 最少的物种灭绝（同数时最早的），个体并入与它最相近的物种
    int ex = -1;
    for (int i = 0; i < n; i++) if (ex < 0 || c[i] < c[ex]) ex = i;
    int to = -1; float best = -1;
    for (int i = 0; i < n; i++) {
      if (i == ex) continue;
      float d = evoResonance(sp.get(i), sp.get(ex).homeA, sp.get(ex).homeV);
      if (d > best) { best = d; to = i; }
    }
    plan.extinct = ex; plan.extinctTo = to;
  }
  return plan;
}

// ===== 历史 =====
class EvoHistory {
  ArrayList<Species> species = new ArrayList<Species>();
  int generations = 0;
  float totalMin = 0;
  ArrayList<String> log = new ArrayList<String>();   // evolution_history.csv 的行
}
EvoHistory evoHistory = null;

File[] evoSessionFiles() {
  File[] csvs = sessionsDir().listFiles((dir, name) -> name.startsWith("eeg_session_") && name.endsWith(".csv"));
  if (csvs == null) return new File[0];
  java.util.Arrays.sort(csvs, (x, y) -> x.getName().compareTo(y.getName()));   // 文件名 = 录制开始时刻
  return csvs;
}

Species evoFounder() {
  return evoMakeSpecies(0, 0, 0, 0.3f, 0.3f, new java.util.Random(EVO_FOUNDER_SEED));
}

EvoHistory evoBuildHistory() {
  int t0 = millis();
  EvoHistory h = new EvoHistory();
  Species f = evoFounder();
  f.count = EVO_N;
  h.species.add(f);
  evoLog(h, "(始祖)");
  for (File csv : evoSessionFiles()) {
    SimTimeline tl = null;
    try { tl = simLoadTimeline(csv); } catch (Exception e) { tl = null; }
    if (tl == null) continue;
    evoAbsorbSession(h, tl, csv.getName());
    evoLog(h, stemOf(csv.getName()));
  }
  println("[進化] " + h.generations + " セッションを吸収（" + nf(h.totalMin, 0, 1) + " 分、" + (millis() - t0) + " ms）→ "
          + h.species.size() + " 種");
  return h;
}

// 一个会话：与实时（录制中）完全相同的时间线与随机数
void evoAbsorbSession(EvoHistory h, SimTimeline tl, String name) {
  java.util.Random gr = new java.util.Random(evoGeneSeed(tl.seed));
  float a = tl.av[0], v = tl.vv[0];
  if (tl.startState != null && tl.startState.hasKey("a") && tl.startState.hasKey("v")) {   // 实时录制的会话：录制开始时的 A/V
    a = Float.parseFloat(tl.startState.getString("a"));
    v = Float.parseFloat(tl.startState.getString("v"));
  }
  boolean conn = true;
  if (tl.startState != null) conn = tl.startState.getBoolean("connected", true);
  int row = 0, ev = 0;
  int n = h.species.size();
  int[] counts = new int[n];
  for (int i = 0; i < n; i++) counts[i] = h.species.get(i).count;
  for (int st = 0; st < tl.totalSteps; st++) {
    while (ev < tl.evStep.length && tl.evStep[ev] <= st) { conn = tl.evConn[ev]; ev++; }
    while (row < tl.steps.length && tl.steps[row] <= st) { a = tl.av[row]; v = tl.vv[row]; row++; }
    if (!conn) {
      a = lerp(a, 0, 0.02f);
      v = lerp(v, 0, 0.02f);
    }
    if (conn && st % EVO_TICK == 0) {
      int[] fl = evoChooseFlow(h.species, counts, a, v, gr);
      if (fl != null) { counts[fl[0]]++; counts[fl[1]]--; }
    }
  }
  for (int i = 0; i < n; i++) h.species.get(i).count = counts[i];
  evoApplyPlanCounts(h, evoPlanGeneration(h.species, counts, evoPrintOf(tl), h.generations + 1, name));
  h.generations++;
  h.totalMin += tl.totalSteps / (float)(SIM_HZ * 60);
}

void evoApplyPlanCounts(EvoHistory h, EvoPlan plan) {
  int k = 0;
  for (int i = 0; i < plan.take.length; i++) { h.species.get(i).count -= plan.take[i]; k += plan.take[i]; }
  plan.born.count = k;
  if (plan.extinct >= 0) {
    h.species.get(plan.extinctTo).count += h.species.get(plan.extinct).count;
    h.species.remove(plan.extinct);
  }
  h.species.add(plan.born);
}

void evoLog(EvoHistory h, String session) {
  for (Species s : h.species) {
    h.log.add(h.generations + "," + session + "," + s.id + "," + s.homeA + "," + s.homeV + "," + s.count);
  }
}

void evoExportHistory(EvoHistory h) {
  try {
    PrintWriter w = createWriter(dataRootFile("evolution_history.csv").getAbsolutePath());
    w.println("generation,session,species_id,home_arousal,home_valence,count");
    for (String l : h.log) w.println(l);
    w.flush();
    w.close();
  } catch (Exception e) {
    println("evolution_history.csv を保存できませんでした: " + e.getMessage());
  }
}

// ===== 实时鱼群 =====
// 启动时：历史的物种构成 → 水族馆里的个体（位置保持，个体数对齐 EVO_N）
void evoApplyToLive(SwarmSim s, EvoHistory h) {
  s.evo = true;
  s.species.clear();
  for (Species sp : h.species) s.species.add(sp.copy());
  while (s.boids.size() > EVO_N) s.boids.remove(s.boids.size() - 1);
  while (s.boids.size() < EVO_N) s.addBoid(s.rng.nextFloat() * s.W, s.rng.nextFloat() * s.H);
  int k = 0;
  for (Species sp : s.species) {
    for (int j = 0; j < sp.count && k < s.boids.size(); j++) s.boids.get(k++).sp = sp;
  }
  while (k < s.boids.size()) s.boids.get(k++).sp = s.species.get(s.species.size() - 1);
}

// 录制结束：这次会话成为新物种（与历史计算相同的规则与随机数）
void evoSessionEnd(SwarmSim s, File csv) {
  if (!s.evo || evoHistory == null) return;
  SimTimeline tl = simLoadTimeline(csv);
  if (tl == null) return;
  int[] counts = s.speciesCounts();
  EvoPlan plan = evoPlanGeneration(s.species, counts, evoPrintOf(tl), evoHistory.generations + 1, csv.getName());
  s.applyPlan(plan);
  evoHistory.generations++;
  evoHistory.totalMin += tl.totalSteps / (float)(SIM_HZ * 60);
  evoHistory.species.clear();
  int[] c = s.speciesCounts();
  for (int i = 0; i < s.species.size(); i++) {
    Species cp = s.species.get(i).copy();
    cp.count = c[i];
    evoHistory.species.add(cp);
  }
  evoLog(evoHistory, stemOf(csv.getName()));
  evoExportHistory(evoHistory);
  println("[進化] 新しい種が生まれました（第 " + evoHistory.generations + " 世代、" + s.species.size() + " 種）");
}

long evoGeneSeed(long seed) { return seed ^ 0x2545F4914F6CDD1DL; }

// ---- 外观（实时与回放共用）----
// 颜色：与原系统相同（V → 冷暖），与物种无关；粗细：物种的大小 × 情绪（V 低 → 变细）
float evoBodyScale(Boid b, float v) {
  if (b.sp == null) return 1;
  return b.sp.size * map(constrain(v, -1, 1), -1, 1, 0.75f, 1.1f);
}
