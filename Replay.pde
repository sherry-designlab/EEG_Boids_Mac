// ===== 回放：倍速回放 Boids → 过渡为光绘 =====
// 回放与实时画面、光绘使用同一个模拟（SwarmSim.pde）：
//   - 新录制的会话：从录制开始时的鱼群出发，在相同的步数送入相同的 A / V → 与当时的实时画面完全相同
//   - 以前的会话 / 导入的 CSV：从固定的初始分布出发（每次回放都相同）
// 回放结束后，淡入这次会话的作品（artworks/ 中的存档；光绘由 LightPainting.pde 独立生成，11/14 版的风格）。
// 使用场景：结束瞑想时（Recording.pde）、画廊、导入 CSV 后与文件列表中（DataManager.pde）。
// 关闭：窗口右上角 ×、回放结束后点击窗口、或 ESC。
// 进度条可以拖动（或点击）跳到任意位置；冥想中做的标记到达时，在画面下方显示它的备注。
// 画法与实时画面相同：每条鱼画出最近 REPLAY_TAIL 步的位置，越旧越淡（倍速时也是同样的"小蝌蚪"）。

float REPLAY_TARGET_SEC = 20;      // 回放的目标时长（秒）：长会话自动提高倍速
int   REPLAY_FRAME_BUDGET_MS = 25; // 每帧模拟最多花这么多时间（电脑慢时回放变长，但不卡顿）
int   REPLAY_FADE_MS = 2500;       // 光绘淡入时间

boolean replayActive = false;
String replayTitle = "";
SimCursor replayCursor;
int replayStepsPerFrame = 1;
PGraphics replayLayer;
int replayPhase = 0;                // 0 = 回放中, 1 = 等待作品, 2 = 作品显示
volatile PImage replayFinal = null;
int replayFadeStart = 0;
float replayCurA = 0, replayCurV = 0;
float rWinX, rWinY, rWinW, rWinH;
float rCloseX, rCloseY;
File replayCsv = null;
int replayStartMs = 0;
int replayGen = 0;                  // 回放编号（关闭后，旧的后台读取结果不再使用）
boolean replayOfferMemo = false;    // 刚结束的冥想：回放结束后显示「今日のメモを書く」
int[] replayMarkerSteps = new int[0];   // 冥想中的标记（进度条上显示刻度）
String[] replayMarkerLabels = new String[0];
String replayCaption = null;            // 正在显示的标记备注
int replayCaptionMs = 0;
final int REPLAY_CAPTION_MS = 3500;
int replaySeekTarget = -1;              // 跳转目标（步）；-1 = 没有跳转
boolean replayDragging = false;         // 正在拖动进度条
float replayDragFrac = 0;
float rBarX, rBarY, rBarW;
float rMemoX, rMemoY, rMemoW = 160, rMemoH = 26;

// 打开回放；数据不足时返回 false
boolean openReplay(File csv, String title) {
  if (csv == null || !csv.exists()) {
    showToast("ファイルが見つかりません");
    return false;
  }
  SimTimeline tl = simLoadTimeline(csv);
  if (tl == null) {
    showToast("データが不足しているため再生できません");
    return false;
  }
  replayTitle = title;
  replayCsv = csv;
  replayCursor = new SimCursor(tl);
  replayStepsPerFrame = max(1, ceil(tl.totalSteps / (REPLAY_TARGET_SEC * 60)));
  replayPhase = 0;
  replayFinal = null;
  replayLayer = null;
  replayActive = true;
  replayStartMs = millis();
  replayOfferMemo = false;
  JSONObject meta = sessionMetaLoad(csv);
  replayMarkerSteps = new int[0];
  replayMarkerLabels = new String[0];
  if (meta != null && meta.hasKey("markers") && tl.startState != null) {
    JSONArray mk = meta.getJSONArray("markers");
    replayMarkerSteps = new int[mk.size()];
    replayMarkerLabels = new String[mk.size()];
    for (int i = 0; i < mk.size(); i++) {
      replayMarkerSteps[i] = mk.getJSONObject(i).getInt("step", 0);
      replayMarkerLabels[i] = mk.getJSONObject(i).getString("label", "");
    }
  }
  replayCaption = null;
  replaySeekTarget = -1;
  replayDragging = false;

  // 作品：后台准备（没有则生成），回放结束时淡入
  final int gen = ++replayGen;
  final File f = csv;
  Thread t = new Thread(() -> {
    try {
      PImage big = loadArtwork(f);
      if (big != null && gen == replayGen) replayFinal = downscale(big, 1920);
    } catch (Exception ex) {
      println("作品を読み込めませんでした: " + ex);
    }
  });
  t.setDaemon(true);
  t.start();
  println("▶ 再生: " + csv.getName() + "（" + tl.totalSteps + " ステップ）");
  return true;
}

void closeReplay() {
  replayActive = false;
  replayGen++;
  replayCursor = null;
  replayLayer = null;
  replayFinal = null;
}

// 推进模拟（每帧）：目标步数，或用完时间预算为止
void updateReplay() {
  int t0 = millis();
  // 跳转中：不画、尽快走到目标步（时间预算内），到达后继续正常回放
  if (replaySeekTarget >= 0) {
    while (replayCursor.sim.step < replaySeekTarget && !replayCursor.done() && millis() - t0 < 40) stepReplayOnce(false);
    if (replayCursor.sim.step >= replaySeekTarget || replayCursor.done()) replaySeekTarget = -1;
    replayCurA = replayCursor.sim.a;
    replayCurV = replayCursor.sim.v;
    return;
  }
  for (int k = 0; k < replayStepsPerFrame; k++) {
    if (replayCursor.done()) {
      replayPhase = 1;
      return;
    }
    stepReplayOnce(true);
    if (millis() - t0 > REPLAY_FRAME_BUDGET_MS) break;
  }
  replayCurA = replayCursor.sim.a;
  replayCurV = replayCursor.sim.v;
}

// 一步：模拟 + 记录拖尾 + 经过标记时显示备注
void stepReplayOnce(boolean showMarkers) {
  int before = replayCursor.sim.step;
  replayCursor.stepOnce(null);
  for (Boid b : replayCursor.sim.boids) b.pushTail();
  if (!showMarkers) return;
  for (int i = 0; i < replayMarkerSteps.length; i++) {
    if (replayMarkerSteps[i] >= before && replayMarkerSteps[i] < replayCursor.sim.step) {
      String lb = replayMarkerLabels[i];
      replayCaption = lb.length() > 0 ? lb : "マーク";
      replayCaptionMs = millis();
    }
  }
}

// 跳到进度 frac（0〜1）：往前跳 = 从头重新计算（模拟是确定的，结果与正常播放相同）
void replaySeek(float frac) {
  if (replayCursor == null) return;
  SimTimeline tl = replayCursor.tl;
  int target = constrain(round(frac * tl.totalSteps), 0, tl.totalSteps);
  if (target < replayCursor.sim.step) replayCursor = new SimCursor(tl);
  replaySeekTarget = target;
  replayCaption = null;
  replayPhase = 0;   // 结束后拖回去也可以重新播放
}

void drawReplay() {
  if (!replayActive) return;
  if (replayPhase == 0) updateReplay();
  if (replayPhase == 1 && replayFinal != null) {
    replayPhase = 2;
    replayFadeStart = millis();
  }

  // 背景变暗（实时画面仍在后面继续运行）
  noStroke();
  fill(0, 200);
  rect(0, 0, width, height);

  // 窗口大小：保持虚拟画布的比例（16:10），与显示器无关
  float aspect = LP_WORLD_W / LP_WORLD_H;
  rWinW = width * 0.72f;
  rWinH = rWinW / aspect;
  if (rWinH > height * 0.76f) {
    rWinH = height * 0.76f;
    rWinW = rWinH * aspect;
  }
  rWinX = (width - rWinW) / 2;
  rWinY = (height - rWinH) / 2 + 10;

  // 窗口框与标题栏
  fill(20);
  stroke(60);
  strokeWeight(1);
  rect(rWinX - 1, rWinY - 44, rWinW + 2, rWinH + 44 + 56, 8);
  noStroke();
  fill(225);
  textSize(15);
  textAlign(LEFT, CENTER);
  text(replayTitle, rWinX + 14, rWinY - 22);

  // 关闭按钮
  rCloseX = rWinX + rWinW - 22;
  rCloseY = rWinY - 22;
  boolean overClose = dist(mouseX, mouseY, rCloseX, rCloseY) < 13;
  fill(overClose ? color(200, 70, 70) : color(60));
  ellipse(rCloseX, rCloseY, 24, 24);
  stroke(235);
  strokeWeight(1.6f);
  line(rCloseX - 5, rCloseY - 5, rCloseX + 5, rCloseY + 5);
  line(rCloseX + 5, rCloseY - 5, rCloseX - 5, rCloseY + 5);
  noStroke();

  // 回放图层（带拖尾）
  int lw = max(1, round(rWinW)), lh = max(1, round(rWinH));
  if (replayLayer == null || replayLayer.width != lw || replayLayer.height != lh) {
    replayLayer = createGraphics(lw, lh);
    replayLayer.beginDraw();
    replayLayer.background(0);
    replayLayer.endDraw();
  }
  if (replayPhase <= 1 && replayCursor != null && replaySeekTarget < 0) {
    float sc = lw / LP_WORLD_W;
    // 与实时画面相同的颜色・透明度・大小（Boid.showOn）；拖尾：k 步前的位置透明度 × 0.92^k
    //（= 实时画面每帧淡出 20/255、每帧一步时的拖尾）
    int cold = color(150, 180, 255), warm = color(255, 160, 60);
    int base = lerpColor(cold, warm, constrain((replayCurV + 1) * 0.5f, 0, 1));
    float alphaNow = map(replayCurA, -1, 1, 120, 220);
    replayLayer.beginDraw();
    replayLayer.background(0);
    replayLayer.noStroke();
    for (Boid bd : replayCursor.sim.boids) {
      float sf = bd.velocity.mag() / max(bd.maxSpeed, 1e-6f);
      float r = map(sf, 0, 1, 3, 8) * replayBodyScale(bd, replayCurV) * max(sc, 0.5f);
      float al = alphaNow;
      int idx = bd.tlHead;
      for (int k = 0; k < bd.tlN; k++) {
        replayLayer.fill(base, al);
        replayLayer.ellipse(bd.tlX[idx] * sc, bd.tlY[idx] * sc, r, r);
        al *= 0.9216f;
        idx = (idx - 1 + REPLAY_TAIL) % REPLAY_TAIL;
      }
    }
    replayLayer.endDraw();
  }
  image(replayLayer, rWinX, rWinY);

  // 光绘淡入
  float fade = 0;
  if (replayPhase == 2 && replayFinal != null) {
    fade = constrain((millis() - replayFadeStart) / (float)REPLAY_FADE_MS, 0, 1);
    float e = fade * fade * (3 - 2 * fade);   // smoothstep
    tint(255, e * 255);
    image(replayFinal, rWinX, rWinY, rWinW, rWinH);
    noTint();
  }

  // 标记的备注（到达标记时在画面下方显示几秒）
  if (replayCaption != null && replayPhase == 0) {
    float t = (millis() - replayCaptionMs) / (float)REPLAY_CAPTION_MS;
    if (t >= 1) replayCaption = null;
    else {
      float al = t < 0.1f ? t / 0.1f : (t > 0.8f ? (1 - t) / 0.2f : 1);
      textSize(15);
      float tw = textWidth(replayCaption) + 40;
      float cx = rWinX + rWinW / 2, cy = rWinY + rWinH - 40;
      noStroke();
      fill(0, 170 * al);
      rect(cx - tw / 2, cy - 18, tw, 36, 18);
      fill(255, 255 * al);
      ellipse(cx - tw / 2 + 16, cy, 6, 6);
      textAlign(CENTER, CENTER);
      text(replayCaption, cx + 6, cy);
    }
  }

  // 进度条与信息（可以拖动）
  SimTimeline tl = replayCursor != null ? replayCursor.tl : null;
  float prog;
  if (replayDragging) prog = replayDragFrac;
  else if (replaySeekTarget >= 0 && tl != null) prog = replaySeekTarget / (float)max(1, tl.totalSteps);
  else prog = (replayPhase == 0 && replayCursor != null) ? replayCursor.progress() : 1;
  float by = rWinY + rWinH + 18;
  rBarX = rWinX + 14;
  rBarY = by;
  rBarW = rWinW - 28;
  boolean overBar = mouseX >= rBarX - 6 && mouseX <= rBarX + rBarW + 6 && abs(mouseY - (by + 2)) < 10;
  fill(45);
  rect(rBarX, by, rBarW, 4, 2);
  fill(100, 200, 100);
  rect(rBarX, by, rBarW * prog, 4, 2);
  // 标记的刻度（鼠标移上去显示备注）
  String hoverLabel = null;
  float hoverX = 0;
  if (tl != null) {
    for (int i = 0; i < replayMarkerSteps.length; i++) {
      float mx = rBarX + rBarW * constrain(replayMarkerSteps[i] / (float)max(1, tl.totalSteps), 0, 1);
      fill(230);
      rect(mx - 1, by - 4, 2, 12);
      if (abs(mouseX - mx) < 5 && abs(mouseY - (by + 2)) < 10) {
        hoverLabel = replayMarkerLabels[i].length() > 0 ? replayMarkerLabels[i] : "マーク";
        hoverX = mx;
      }
    }
  }
  // 拖动用的圆点
  if (overBar || replayDragging) {
    fill(235);
    ellipse(rBarX + rBarW * prog, by + 2, 12, 12);
  }
  if (hoverLabel != null && !replayDragging) {
    textSize(12);
    float tw = textWidth(hoverLabel) + 16;
    fill(0, 200);
    rect(hoverX - tw / 2, by - 30, tw, 22, 6);
    fill(235);
    textAlign(CENTER, CENTER);
    text(hoverLabel, hoverX, by - 19);
  }

  textSize(12);
  textAlign(LEFT, CENTER);
  fill(170);
  if (tl != null) {
    long totalMs = (tl.totalSteps - tl.paintFrom) * 1000L / SIM_HZ;
    long curMs = (long)(prog * totalMs);
    // 倍速 = 每帧的步数 × 帧率 ÷ 每秒步数
    float speed = replayStepsPerFrame * frameRate / SIM_HZ;
    String st = replaySeekTarget >= 0 ? "    移動中…" : (replayPhase == 0 ? "    約 ×" + max(1, round(speed)) + " 倍速" : "");
    text(formatDuration(curMs) + " / " + formatDuration(totalMs) + st, rWinX + 14, by + 22);
  }
  textAlign(RIGHT, CENTER);
  if (replayPhase == 0) {
    fill(170);
    text("A " + signed(replayCurA) + "   V " + signed(replayCurV), rWinX + rWinW - 14, by + 22);
  } else if (replayPhase == 1) {
    fill(200, 200, 120);
    text("光絵を準備中…", rWinX + rWinW - 14, by + 22);
  } else if (fade >= 1) {
    fill(150);
    if (replayOfferMemo) {
      // 可以跳过：直接关闭即可
      rMemoX = rWinX + rWinW - 14 - rMemoW;
      rMemoY = by + 22 - rMemoH / 2;
      boolean hov = mouseX >= rMemoX && mouseX <= rMemoX + rMemoW && mouseY >= rMemoY && mouseY <= rMemoY + rMemoH;
      noStroke();
      fill(hov ? 75 : 50);
      rect(rMemoX, rMemoY, rMemoW, rMemoH, 6);
      fill(230);
      textAlign(CENTER, CENTER);
      text("今日のメモを書く", rMemoX + rMemoW / 2, rMemoY + rMemoH / 2);
      textAlign(RIGHT, CENTER);
      fill(150);
      text("クリック / ESC で閉じる", rMemoX - 16, by + 22);
    } else {
      text("クリック / ESC で閉じる", rWinX + rWinW - 14, by + 22);
    }
  }
  textAlign(LEFT);
}

// 回放窗口打开时的鼠标处理（返回 true = 已处理）
boolean replayHandleClick() {
  if (!replayActive) return false;
  if (dist(mouseX, mouseY, rCloseX, rCloseY) < 13) {
    closeReplay();
    return true;
  }
  if (replayOfferMemo && replayPhase == 2 && mouseX >= rMemoX && mouseX <= rMemoX + rMemoW && mouseY >= rMemoY && mouseY <= rMemoY + rMemoH) {
    File f = replayCsv;
    closeReplay();
    openDiaryEditor(f, "今日のメモ");
    return true;
  }
  // 进度条：按下开始拖动（松开时跳转）
  if (replayCursor != null && mouseX >= rBarX - 6 && mouseX <= rBarX + rBarW + 6 && abs(mouseY - (rBarY + 2)) < 10) {
    replayDragging = true;
    replayDragFrac = constrain((mouseX - rBarX) / max(1, rBarW), 0, 1);
    return true;
  }
  // 光绘显示完成后，点击窗口内关闭
  boolean inWin = mouseX >= rWinX && mouseX <= rWinX + rWinW && mouseY >= rWinY && mouseY <= rWinY + rWinH;
  if (replayPhase == 2 && inWin && millis() - replayFadeStart > REPLAY_FADE_MS) closeReplay();
  return true;   // 回放中其他点击一律忽略
}

// 拖动进度条（MouseInput.pde 的 mouseDragged / mouseReleased 调用）
void replayHandleDrag() {
  if (!replayActive || !replayDragging) return;
  replayDragFrac = constrain((mouseX - rBarX) / max(1, rBarW), 0, 1);
}

void replayHandleRelease() {
  if (!replayActive || !replayDragging) return;
  replayDragging = false;
  replaySeek(replayDragFrac);
}
