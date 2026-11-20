// ===== 进化面板（E 键显示 / 隐藏）=====
// 左上角常驻一行：第几代・累计时间・物种数
// 面板（左下）：情绪平面（横 = Valence，纵 = Arousal）上的物种。
//   圆的位置 = 该物种诞生那次会话的平均情绪，圆的大小 = 现在的个体数，数字 = 世代（0 = 始祖）
boolean evoPanelOpen = false;

void drawEvoLabel() {
  if (evoHistory == null || !liveSim.evo) return;
  fill(200);
  textSize(12);
  textAlign(LEFT);
  text("進化：第 " + evoHistory.generations + " 世代（累計 " + round(evoHistory.totalMin) + " 分）・"
       + liveSim.species.size() + " 種　[E] 詳細", 70, 105);
}

void drawEvoPanel() {
  if (!evoPanelOpen || evoHistory == null || !liveSim.evo) return;
  float pw = 300, ph = 330;
  float x0 = 24, y0 = height - ph - 44;
  noStroke();
  fill(10, 210);
  rect(x0, y0, pw, ph, 8);
  fill(225);
  textSize(13);
  textAlign(LEFT, TOP);
  text("種（1 セッション = 1 種）", x0 + 14, y0 + 10);

  float cx = x0 + pw / 2, cy = y0 + 40 + 120, R = 115;
  stroke(70);
  strokeWeight(1);
  noFill();
  ellipse(cx, cy, R * 2, R * 2);
  line(cx - R, cy, cx + R, cy);
  line(cx, cy - R, cx, cy + R);
  fill(130);
  textSize(10);
  textAlign(CENTER, CENTER);
  text("V+", cx + R + 10, cy);
  text("V−", cx - R - 10, cy);
  text("A+", cx, cy - R - 8);
  text("A−", cx, cy + R + 8);

  int[] counts = liveSim.speciesCounts();
  for (int i = 0; i < liveSim.species.size(); i++) {
    Species s = liveSim.species.get(i);
    float x = cx + constrain(s.homeV, -1, 1) * R * 0.92f;
    float y = cy - constrain(s.homeA, -1, 1) * R * 0.92f;
    float d = 6 + 3.2f * sqrt(counts[i]);
    int col = lerpColor(color(150, 180, 255), color(255, 160, 60), constrain((s.homeV + 1) * 0.5f, 0, 1));
    noStroke();
    fill(col, 150);
    ellipse(x, y, d, d);
    fill(255);
    textSize(9);
    text(str(s.id), x, y);
  }
  fill(160);
  textSize(10);
  textAlign(LEFT, TOP);
  text("位置 = その回の平均の気分、大きさ = 今の数\n瞑想中、今の気分に近い種が増え、遠い種が減る", x0 + 14, y0 + ph - 40);
}
