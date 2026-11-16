// ===== 实时折线图：Valence / Arousal（画面底部） =====
// 显示的是相对 calibration.json 基准正规化后的值（与 Boids 使用的 arousal / valence 相同）：
//   0 线 = 校准时的平均值 μ；±0.5 = 偏离 μ 一个标准差 σ；±1 = 偏离 2σ 以上（已截断）
// 每接受一个新样本（约 1Hz）记录一次，显示最近 CHART_LEN 秒。

//int CHART_LEN = 120;                                   // 显示最近 120 个样本（约 2 分钟）
//FloatList chartArousal = new FloatList();
//FloatList chartValence = new FloatList();
//float chartLastSampleSec = -1e9;

// 记录新样本：只在 updateEmotion() 接受了新数据时追加
//void updateChartData() {
//  if (lastAcceptedSec == chartLastSampleSec) return;
//  chartLastSampleSec = lastAcceptedSec;
//  chartArousal.append(arousal);
//  chartValence.append(valence);
//  while (chartArousal.size() > CHART_LEN) chartArousal.remove(0);
//  while (chartValence.size() > CHART_LEN) chartValence.remove(0);
//}

//void drawRealtimeCharts() {
//  updateChartData();

  // 底部居中
//  float x0 = width * 0.2f;
//  float x1 = width * 0.8f;
//  float chartH = 70;
//  float gap = 18;
//  float bottom = height - 60;                // 下方留给帮助文字和 "Press X"
//  float yV = bottom - chartH;                // Valence 在下
//  float yA = yV - gap - chartH;              // Arousal 在上

//  drawOneChart(chartArousal, "Arousal", arousal, color(255, 110, 110), x0, yA, x1 - x0, chartH);
//  drawOneChart(chartValence, "Valence", valence, color(255, 170, 70),  x0, yV, x1 - x0, chartH);
//}

//void drawOneChart(FloatList data, String name, float current, int lineColor,
//                  float x, float y, float w, float h) {
  // 背景
//  noStroke();
//  fill(0, 140);
//  rect(x - 8, y - 4, w + 16, h + 8, 6);

//  float midY = y + h / 2;

  // 基准线：μ（实线）与 ±1σ（细虚线）
//  stroke(120);
//  strokeWeight(1);
//  line(x, midY, x + w, midY);
//  stroke(70);
//  float sigUp = map(0.5f, -1, 1, y + h, y);
//  float sigDn = map(-0.5f, -1, 1, y + h, y);
//  for (float dx = 0; dx < w; dx += 8) {
//    line(x + dx, sigUp, x + min(dx + 4, w), sigUp);
//    line(x + dx, sigDn, x + min(dx + 4, w), sigDn);
//  }

//  // 折线：最新的点在最右端
//  int n = data.size();
//  if (n >= 2) {
//    noFill();
//    stroke(lineColor);
//    strokeWeight(2);
//    beginShape();
//    for (int i = 0; i < n; i++) {
//      float px = x + w - (n - 1 - i) * (w / (CHART_LEN - 1));
//      float py = map(constrain(data.get(i), -1, 1), -1, 1, y + h, y);
//      vertex(px, py);
//    }
//    endShape();
//  }

  // 文字：名称与当前值（左上），基准刻度（右侧）
//  noStroke();
//  fill(lineColor);
//  textSize(12);
//  textAlign(LEFT, TOP);
//  text(name + "  " + (current >= 0 ? "+" : "") + nf(current, 1, 2), x + 4, y + 2);

//  fill(130);
//  textSize(10);
//  textAlign(LEFT, CENTER);
//  text("μ", x + w + 12, midY);
//  text("+1σ", x + w + 12, sigUp);
//  text("−1σ", x + w + 12, sigDn);
//  textAlign(LEFT);
//}
