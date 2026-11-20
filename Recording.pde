// ===== 录制（瞑想セッション）控制 =====
// 只有在"EEG 已连接 + 已校准"时才能开始录制；开始录制时才创建 CSV。
// 操作：右下角的圆形水波按钮（鼠标）或 Space 键，开始 / 结束。
// 录制中如果 EEG 断开，该期间不写入数据；恢复连接后自动继续写入。
// 结束时数据不足 2 行（几乎没录到）则自动删除该 CSV，避免产生空记录。

boolean isRecording = false;
// 回放用：录制开始时的鱼群、随机数种子、EEG 连接状态的变化（结束时写进会话 JSON）
JSONObject recSwarmStart = null;
long recSeed = 0;
JSONArray recEvents = null;
int recordedRows = 0;
float recBtnX, recBtnY;
float REC_BTN_R = 34;

boolean canStartRecording() {
  return eegConnected && normalization.isCalibrated;
}

void startRecording() {
  if (isRecording || !canStartRecording()) return;
  initializeSave();
  sessionStartTime = System.currentTimeMillis();
  lastSaveTime = 0;
  recordedRows = 0;
  resetNoiseStats();
  sampleReadyForSave = false;
  // 鱼群：从现在的状态开始，重设随机数种子、步数归零
  recSeed = System.currentTimeMillis();
  liveSim.beginRecording(recSeed);
  recSwarmStart = liveSim.toJSON();
  recEvents = new JSONArray();
  recMarkers = new JSONArray();
  isRecording = true;
  println("● 記録開始: " + currentSessionFile);
}

void stopRecording() {
  stopRecording(false);
}

// showReplay = true：保存后立即在窗口中倍速回放，并以光绘收尾（Replay.pde）
void stopRecording(boolean showReplay) {
  if (!isRecording) return;
  isRecording = false;
  if (csvWriter != null) {
    csvWriter.flush();
    csvWriter.close();
    csvWriter = null;
  }
  File f = sessionFile(currentSessionFile);
  if (recordedRows >= 2) {
    // 会话 JSON：回放所需的鱼群起始状态等
    final JSONObject start = recSwarmStart;
    final JSONArray events = recEvents;
    final JSONArray markers = recMarkers;
    final long seed = recSeed;
    final int endStep = liveSim.step;
    sessionMetaUpdate(f, o -> {
      o.setInt("format", 1);
      o.setLong("swarm_seed", seed);
      o.setInt("sim_hz", SIM_HZ);
      o.setInt("end_step", endStep);
      o.setJSONObject("swarm_start", start);
      o.setJSONArray("events", events);
      o.setJSONArray("markers", markers);
    });
    saveSwarmState();
  }
  if (recordedRows < 2) {
    if (f.exists() && f.delete()) println("記録が短すぎるため削除しました: " + currentSessionFile);
    sessionMetaFile(f).delete();
  } else {
    println("■ 記録を保存しました: " + currentSessionFile + "（" + recordedRows + " 行、ノイズ除去 " + noiseRejectedCount + " 秒）");
    String saved = currentSessionFile;
    currentSessionFile = "";
    startArtworkInBackground(f);   // 4K 作品在后台生成（回放结束时淡入）
    if (showReplay) {
      showToast("保存しました（" + recordedRows + " 秒分・ノイズ除去 " + noiseRejectedCount + " 秒）");
      openReplay(f, "今回の瞑想の振り返り");
      replayOfferMemo = true;   // 回放结束后显示「今日のメモを書く」（可跳过）
    }
    return;
  }
  currentSessionFile = "";
}

void toggleRecording() {
  if (isRecording) stopRecording(true);
  else startRecording();
}

String recordingElapsedText() {
  long ms = System.currentTimeMillis() - sessionStartTime;
  long sec = ms / 1000;
  return nf((int)(sec / 60), 2) + ":" + nf((int)(sec % 60), 2);
}

boolean mouseOverRecordButton() {
  return dist(mouseX, mouseY, recBtnX, recBtnY) < REC_BTN_R + 8;
}

// 圆形水波按钮（实时模式右下角）
void drawRecordButton() {
  recBtnX = width - 110;
  recBtnY = height - 140;
  boolean enabled = isRecording || canStartRecording();
  boolean hover = enabled && mouseOverRecordButton();
  float t = millis() / 1000.0f;

  int base;
  if (isRecording)   base = color(255, 120, 120);   // 录制中：暖红
  else if (enabled)  base = color(120, 200, 255);   // 可开始：冷青
  else               base = color(110);             // 不可用：灰
  float br = red(base), bg = green(base), bb = blue(base);

  // 水波：3 圈同心圆依次向外扩散并淡出（录制中更快）
  if (enabled) {
    float speed = isRecording ? 0.8f : 0.3f;
    noFill();
    for (int i = 0; i < 3; i++) {
      float p = (t * speed + i / 3.0f) % 1.0f;
      float r = REC_BTN_R + p * REC_BTN_R * 1.5f;
      stroke(br, bg, bb, (1 - p) * (hover ? 170 : 120));
      strokeWeight(0.5f + 2 * (1 - p));
      ellipse(recBtnX, recBtnY, r * 2, r * 2);
    }
  }

  // 按钮本体：柔和发光的圆（录制中轻微呼吸）
  float breathe = isRecording ? 1 + 0.05f * sin(t * 3) : 1;
  noStroke();
  fill(br, bg, bb, hover ? 70 : 40);
  ellipse(recBtnX, recBtnY, REC_BTN_R * 2.3f * breathe, REC_BTN_R * 2.3f * breathe);
  fill(0, 160);
  ellipse(recBtnX, recBtnY, REC_BTN_R * 2, REC_BTN_R * 2);
  stroke(br, bg, bb, enabled ? 220 : 120);
  strokeWeight(1.5f);
  noFill();
  ellipse(recBtnX, recBtnY, REC_BTN_R * 2, REC_BTN_R * 2);

  // 中心图标：未录制 = 圆点，录制中 = 方块（停止）
  noStroke();
  fill(br, bg, bb, enabled ? 235 : 120);
  if (isRecording) {
    rectMode(CENTER);
    rect(recBtnX, recBtnY, 20, 20, 4);
    rectMode(CORNER);
  } else {
    ellipse(recBtnX, recBtnY, 22, 22);
  }

  // 按钮下方文字
  textAlign(CENTER, CENTER);
  textSize(13);
  float ly = recBtnY + REC_BTN_R + 22;
  if (isRecording) {
    fill(255, 150, 150);
    text("● REC  " + recordingElapsedText(), recBtnX, ly);
    fill(170);
    textSize(11);
    text("瞑想を終える（Space）・ M キーでマーク＋一言メモ", recBtnX, ly + 18);
    // 噪声去除的统计（NoiseFilter.pde）
    fill(130);
    textAlign(RIGHT, CENTER);
    text("ノイズ除去 " + noiseRejectedCount + " 秒" + (noiseRejectedCount > 0 ? "（直近：" + lastNoiseReason + "）" : ""), width - 20, ly + 36);
    if (!eegConnected) {
      fill(230, 190, 80);
      text("EEG 切断中：この間は記録されません", width - 20, ly + 54);
    }
  } else if (enabled) {
    fill(210);
    text("瞑想を始める", recBtnX, ly);
    fill(150);
    textSize(11);
    text("クリック / Space", recBtnX, ly + 18);
  } else {
    fill(140);
    text(eegConnected ? "キャリブレーション中" : "EEG 未接続", recBtnX, ly);
    fill(110);
    textSize(11);
    text("記録できません", recBtnX, ly + 18);
  }
  drawMarkerFlash();
  textAlign(LEFT);
}

// 录制中 EEG 连接状态变化（BoidControl.pde 的 stepLiveSim 调用）
void recordConnectionEvent(int step, boolean connected) {
  if (recEvents == null) return;
  JSONObject e = new JSONObject();
  e.setInt("step", step);
  e.setBoolean("connected", connected);
  recEvents.append(e);
}

// 在后台生成作品（已存在则什么都不做）
void startArtworkInBackground(File csv) {
  final File f = csv;
  Thread t = new Thread(() -> {
    try {
      ensureArtwork(f);
    } catch (Exception ex) {
      println("作品の生成に失敗しました: " + ex);
    }
  });
  t.setDaemon(true);
  t.start();
}
