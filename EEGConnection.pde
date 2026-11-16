// ===== EEG 连接判定 =====
// 自动判定：最近 EEG_TIMEOUT_MS 毫秒内收到过 /muse/ 开头的 OSC 消息 → 视为已连接。
// 另外读取 Mind Monitor 发送的 horseshoe（各电极接触质量：1=良好, 2=一般, 4=差）用于提示佩戴状态。
// 未连接时：
//   - 不计算情绪（arousal / valence 缓慢回到 0），不写入 CSV，不进入折线图
//   - 校准计时暂停（避免用 0 值数据完成校准）
//   - 无法开始录制

int   EEG_TIMEOUT_MS = 2000;
int   lastOscMillis = -100000;
boolean eegConnected = false;
float[] horseshoe = { 4, 4, 4, 4 };     // TP9, AF7, AF8, TP10
int   lastEEGCheckMillis = 0;

// 在 oscEvent() 中对每条 /muse/ 消息调用
void markOscReceived() {
  lastOscMillis = millis();
}

// 每帧在 draw() 开头调用
void updateEEGConnection() {
  int now = millis();
  boolean was = eegConnected;
  eegConnected = (now - lastOscMillis) < EEG_TIMEOUT_MS;

  if (was != eegConnected) {
    println(eegConnected ? "✓ EEG が接続されました" : "⚠ EEG の接続が切れました");
  }

  // 未连接时暂停校准计时：把校准开始时间往后推，相当于"未连接的时间不算"
  if (!eegConnected && !normalization.isCalibrated) {
    calibrationStartTime += (now - lastEEGCheckMillis);
  }
  lastEEGCheckMillis = now;
}

// 佩戴状态：4 个电极都很差时视为没有戴好
boolean eegContactPoor() {
  for (int i = 0; i < 4; i++) if (horseshoe[i] < 4) return false;
  return true;
}

// 画面上方中央的连接状态
void drawEEGStatus() {
  float cx = width / 2.0f;
  float y = 28;
  textSize(12);
  textAlign(LEFT, CENTER);

  String label;
  int dotColor;
  if (!eegConnected) {
    label = "EEG 未接続";
    dotColor = color(200, 90, 90);
  } else if (eegContactPoor()) {
    label = "EEG 接続中 ・ ヘッドバンドの装着を確認してください";
    dotColor = color(230, 190, 80);
  } else {
    label = "EEG 接続中";
    dotColor = color(110, 210, 130);
  }

  float w = textWidth(label) + (eegConnected ? 70 : 30);
  float x = cx - w / 2;

  noStroke();
  fill(0, 150);
  rect(x - 12, y - 14, w + 24, 28, 14);

  // 状态灯（未连接时闪烁）
  float a = eegConnected ? 255 : 140 + 115 * sin(millis() / 300.0f);
  fill(red(dotColor), green(dotColor), blue(dotColor), a);
  ellipse(x + 5, y, 9, 9);

  fill(215);
  text(label, x + 18, y);

  // 4 个电极的接触质量
  if (eegConnected) {
    float sx = x + 18 + textWidth(label) + 14;
    for (int i = 0; i < 4; i++) {
      if (horseshoe[i] <= 1) fill(110, 210, 130);
      else if (horseshoe[i] <= 2) fill(230, 190, 80);
      else fill(200, 90, 90);
      ellipse(sx + i * 11, y, 7, 7);
    }
  }

  // 未连接时的操作提示
  if (!eegConnected) {
    fill(150);
    textSize(11);
    textAlign(CENTER, CENTER);
    text("Muse を装着し、Mind Monitor の OSC 送信先をこの PC（ポート 8000）に設定してください", cx, y + 26);
  }
  textAlign(LEFT);
}
