// ===== 实时鱼群（SwarmSim）=====
// 实时画面、回放、光绘用的是同一个模拟（SwarmSim.pde）。
// 这里只负责：按真实时间推进固定步长、记录 EEG 连接状态的变化、保存/恢复鱼群状态。
SwarmSim liveSim;
int liveLastMs = -1;
float liveAcc = 0;
final int LIVE_MAX_STEPS_PER_FRAME = 4;   // 电脑很忙时最多补 4 步（之后只会变慢，不会与回放不一致）
int lastSwarmSaveMs = 0;

void initLiveSim() {
  liveSim = null;
  File f = dataRootFile("swarm_state.json");
  if (f.exists()) {
    try {
      SwarmSim s = new SwarmSim(System.currentTimeMillis());
      s.fromJSON(loadJSONObject(f.getAbsolutePath()));
      if (s.boids.size() > 0) liveSim = s;
    } catch (Exception e) {
      println("swarm_state.json を読み込めませんでした: " + e.getMessage());
    }
  }
  if (liveSim == null) {
    // 第一次启动：固定种子的初始分布
    liveSim = new SwarmSim(1);
    liveSim.initCanonical();
  } else {
    println("前回の群れから再開します（" + liveSim.boids.size() + " 匹）");
  }
  liveSim.beginRecording(System.currentTimeMillis());   // 只是重设随机数；录制开始时会再设一次
  liveSim.wake = 0;            // 慢慢醒来
  liveSim.connected = false;
  liveSim.a = 0;
  liveSim.v = 0;
  boidsRight = liveSim.boids;
}

void stepLiveSim() {
  // EEG 连接状态的变化：录制中记入会话 JSON（回放时在同一步重现）
  if (liveSim.connected != eegConnected) {
    liveSim.connected = eegConnected;
    if (isRecording) recordConnectionEvent(liveSim.step, eegConnected);
  }
  int now = millis();
  if (liveLastMs < 0) liveLastMs = now;
  liveAcc += (now - liveLastMs) * SIM_HZ / 1000.0f;
  liveLastMs = now;
  int n = (int)liveAcc;
  if (n > LIVE_MAX_STEPS_PER_FRAME) {
    n = LIVE_MAX_STEPS_PER_FRAME;
    liveAcc = n;
  }
  liveAcc -= n;
  // 每走一步就把鱼画到 Boids 图层上（与以前"每帧一步、每帧画一次"相同的观感）：
  // 一帧走了几步，就留下几个身体的圆点，彼此重叠成连续的身体，不会出现断开的点
  boolean drawNow = isRealtimeMode();
  if (drawNow) beginBoidLayer();
  if (n == 0 && drawNow) drawLiveBoids();
  for (int i = 0; i < n; i++) {
    liveSim.step(null);
    if (drawNow) drawLiveBoids();
  }
  if (drawNow) boidLayer.endDraw();
  // 画面显示用的 A / V = 模拟中的值（EEG 断开时会慢慢回到 0）
  arousal = liveSim.a;
  valence = liveSim.v;
  boidsRight = liveSim.boids;

  if (now - lastSwarmSaveMs > 60000) {
    lastSwarmSaveMs = now;
    saveSwarmState();
  }
}

void saveSwarmState() {
  if (liveSim == null) return;
  try {
    saveJSONObject(liveSim.toJSON(), dataRootFile("swarm_state.json").getAbsolutePath());
  } catch (Exception e) {
    println("swarm_state.json を保存できませんでした: " + e.getMessage());
  }
}

// 程序结束时保存鱼群状态（下次启动时从这里继续）
void dispose() {
  saveSwarmState();
  super.dispose();
}

