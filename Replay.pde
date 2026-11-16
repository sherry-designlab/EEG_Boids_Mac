// ===== 回放：倍速回放 Boids → 过渡为光绘 =====
// 回放与实时画面、光绘使用同一个模拟（SwarmSim.pde）：
//   - 新录制的会话：从录制开始时的鱼群出发，在相同的步数送入相同的 A / V → 与当时的实时画面完全相同
//   - 以前的会话 / 导入的 CSV：从固定的初始分布出发（每次回放都相同）
// 回放结束后，淡入这次会话的作品（artworks/ 中的存档；光绘由 LightPainting.pde 独立生成，11/14 版的风格）。
// 使用场景：结束瞑想时（Recording.pde）、画廊、导入 CSV 后与文件列表中（DataManager.pde）。
// 关闭：窗口右上角 ×、回放结束后点击窗口、或 ESC。

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
  if (meta != null && meta.hasKey("markers") && tl.startState != null) {
    JSONArray mk = meta.getJSONArray("markers");
    replayMarkerSteps = new int[mk.size()];
    for (int i = 0; i < mk.size(); i++) replayMarkerSteps[i] = mk.getJSONObject(i).getInt("step", 0);
  }

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
  // 记录这一帧中每条鱼经过的位置（最多 BOID_TRAIL_MAX 个点），用于画连续的身体
  for (Boid b : replayCursor.sim.boids) {
    b.trN = 1;
    b.trX[0] = b.position.x;
    b.trY[0] = b.position.y;
  }
  int every = max(1, ceil(replayStepsPerFrame / (float)(BOID_TRAIL_MAX - 1)));
  for (int k = 0; k < replayStepsPerFrame; k++) {
    if (replayCursor.done()) {
      replayPhase = 1;
      return;
    }
    replayCursor.stepOnce(null);
    boolean last = k == replayStepsPerFrame - 1 || millis() - t0 > REPLAY_FRAME_BUDGET_MS;
    if ((k + 1) % every == 0 || last) {
      for (Boid b : replayCursor.sim.boids) {
        if (b.trN < BOID_TRAIL_MAX) {
          b.trX[b.trN] = b.position.x;
          b.trY[b.trN] = b.position.y;
          b.trN++;
        }
      }
    }
    if (millis() - t0 > REPLAY_FRAME_BUDGET_MS) break;
  }
  replayCurA = replayCursor.sim.a;
  replayCurV = replayCursor.sim.v;
}

void drawReplay() {
  if (!replayActive) return;
  if (replayPhase == 0) updateReplay();
  if (replayPhase >= 1 && replayPhase < 2 && replayFinal != null) {
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
  if (replayPhase <= 1 && replayCursor != null) {
    float sc = lw / LP_WORLD_W;
    int cold = color(150, 180, 255), warm = color(255, 160, 60);
    int base = lerpColor(cold, warm, constrain((replayCurV + 1) * 0.5f, 0, 1));
    float alphaNow = map(replayCurA, -1, 1, 120, 220);
    replayLayer.beginDraw();
    replayLayer.noStroke();
    replayLayer.fill(0, 0, 0, 22);
    replayLayer.rect(0, 0, lw, lh);
    // 倍速时一帧走很多步：沿这一帧经过的位置画成连续的身体（不会变成断开的点）
    replayLayer.strokeCap(ROUND);
    replayLayer.noFill();
    for (Boid bd : replayCursor.sim.boids) {
      float sf = bd.velocity.mag() / max(bd.maxSpeed, 1e-6f);
      float r = map(sf, 0, 1, 3, 8) * max(sc, 0.5f);
      if (bd.trN >= 2) {
        replayLayer.stroke(base, alphaNow);
        replayLayer.strokeWeight(r);
        for (int k = 1; k < bd.trN; k++) {
          float dx = bd.trX[k] - bd.trX[k - 1], dy = bd.trY[k] - bd.trY[k - 1];
          if (dx * dx + dy * dy > 80 * 80) continue;   // 穿越边缘的跳变不画
          replayLayer.line(bd.trX[k - 1] * sc, bd.trY[k - 1] * sc, bd.trX[k] * sc, bd.trY[k] * sc);
        }
      } else {
        replayLayer.noStroke();
        replayLayer.fill(base, alphaNow);
        replayLayer.ellipse(bd.position.x * sc, bd.position.y * sc, r, r);
        replayLayer.noFill();
      }
    }
    replayLayer.noStroke();
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

  // 进度条与信息
  SimTimeline tl = replayCursor != null ? replayCursor.tl : null;
  float prog = (replayPhase == 0 && replayCursor != null) ? replayCursor.progress() : 1;
  float by = rWinY + rWinH + 18;
  fill(45);
  rect(rWinX + 14, by, rWinW - 28, 4, 2);
  fill(100, 200, 100);
  rect(rWinX + 14, by, (rWinW - 28) * prog, 4, 2);
  // 标记的刻度
  if (tl != null) {
    fill(230);
    for (int ms : replayMarkerSteps) {
      float mx = rWinX + 14 + (rWinW - 28) * constrain(ms / (float)max(1, tl.totalSteps), 0, 1);
      rect(mx - 1, by - 4, 2, 12);
    }
  }

  textSize(12);
  textAlign(LEFT, CENTER);
  fill(170);
  if (tl != null) {
    long totalMs = (tl.totalSteps - tl.paintFrom) * 1000L / SIM_HZ;
    long curMs = (long)(prog * totalMs);
    // 实际倍速 = 已回放的模拟时间 ÷ 经过的真实时间
    float elapsed = max(0.5f, (millis() - replayStartMs) / 1000.0f);
    float speed = replayPhase == 0 ? (replayCursor.sim.step / (float)SIM_HZ) / elapsed : 0;
    text(formatDuration(curMs) + " / " + formatDuration(totalMs) + (replayPhase == 0 ? "    約 ×" + max(1, round(speed)) + " 倍速" : ""),
         rWinX + 14, by + 22);
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
  // 光绘显示完成后，点击窗口内关闭
  boolean inWin = mouseX >= rWinX && mouseX <= rWinX + rWinW && mouseY >= rWinY && mouseY <= rWinY + rWinH;
  if (replayPhase == 2 && inWin && millis() - replayFadeStart > REPLAY_FADE_MS) closeReplay();
  return true;   // 回放中其他点击一律忽略
}
