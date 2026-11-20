// ===== Emotion UI（右上角） =====
void drawEmotionUI() {
  int size = 120;
  int margin = 20;
  int x = width - size - margin;
  int y = margin;

  fill(0, 80);
  noStroke();
  rect(x, y, size, size, 10);

  stroke(150);
  line(x + size/2, y, x + size/2, y + size);
  line(x, y + size/2, x + size, y + size/2);

  float ex = map(valence, -1, 1, x, x + size);
  float ey = map(arousal, 1, -1, y, y + size);

  noStroke();
  fill(255, 100, 100);
  ellipse(ex, ey, 16, 16);

  fill(200);
  textSize(12);
  text("Excited", x + size - 40, y + 15);
  text("Alerted", x + 10, y + 15);
  text("Relax", x + size - 30, y + size - 5);
  text("Tired", x + 10, y + size - 5);

  text(String.format("A=%.3f", arousalRaw), x + 8, y + size + 14);
  text(String.format("V=%.3f", valenceRaw), x + 8, y + size + 28);
  text(String.format("A=%.2f  V=%.2f", arousal, valence), x + 8, y + size + 42);
  text(String.format("pop=%d", boidsRight.size()), x + 8, y + size + 56);
}

// ===== 新增：显示帮助信息 =====
void drawHelpInfo() {
  fill(150);
  textSize(12);
  textAlign(LEFT);
  
  if (normalization.isCalibrated) {
    // 已校准状态
    text("Space キー / 右下のボタン：瞑想の開始・終了", 20, height - 80);
    text("M キー：瞑想中にマーク＋一言メモ（20 字まで）", 20, height - 60);
    text("R キーを押す：再キャリブレーション", 20, height - 40);
    text("X キーを押す：プログラムを終了する", 20, height - 20);
  } else {
    // 校准中状态
    long currentTimeMs = System.currentTimeMillis();
    long elapsedSinceCalibStart = currentTimeMs - calibrationStartTime;
    float remainSec = (normalization.calibrationTimeMs - elapsedSinceCalibStart) / 1000.0f;
    
    text("残りのキャリブレーション時間:" + nf(max(0, remainSec), 1, 1) + " 秒", 20, height - 40);
    text(eegConnected ? "静かにしてください." : "EEG を接続するとキャリブレーションが進みます.", 20, height - 20);
  }
}

// ===== 校准进度提示（最上层） =====
void drawCalibrationOverlay() {
  // 未校准但 EEG 未连接：显示连接提示（校准计时暂停中）
  if (!normalization.isCalibrated && !eegConnected) {
    fill(200);
    textSize(20);
    textAlign(CENTER, CENTER);
    text("EEG を接続してください", width/2, height/2 - 20);
    fill(150);
    textSize(13);
    text("接続されるとキャリブレーション（" + nf(normalization.calibrationTimeMs/1000, 1, 0) + " 秒）が始まります", width/2, height/2 + 14);
    return;
  }
  if (!normalization.isCalibrated) {
    long currentTimeMs = System.currentTimeMillis();
    long elapsedSinceCalibStart = currentTimeMs - calibrationStartTime;
    float calibProgress = elapsedSinceCalibStart / normalization.calibrationTimeMs;
    
    // 显示校准进度
    fill(200);
    textSize(20);
    textAlign(CENTER, CENTER);
    text("キャリブレーション中...", width/2, height/2 - 50);
    
    // 进度条
    noFill();
    stroke(100);
    strokeWeight(2);
    int barWidth = 300;
    rect(width/2 - barWidth/2, height/2, barWidth, 30);
    
    fill(100, 200, 100);
    noStroke();
    rect(width/2 - barWidth/2, height/2, barWidth * calibProgress, 30);
    
    fill(200);
    textSize(14);
    text(nf(calibProgress * 100, 1, 1) + "%", width/2, height/2 + 15);
    
    textSize(12);
    text("安静な状態を保ってください." + nf(normalization.calibrationTimeMs/1000, 1, 0) + " 秒", 
         width/2, height/2 + 80);
  }
}
