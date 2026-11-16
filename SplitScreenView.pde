// ===== 绘制画面：Real-time 模式（全屏 Boids）或 Gallery 模式（全屏画廊） =====
// 函数名沿用 drawSplitScreen，现在已不再分屏
PGraphics boidLayer;   // Boids 专用图层：拖尾只作用于这一层

void drawSplitScreen() {
  // Gallery 模式：画廊独占全屏
  if (galleryOpen) {
    drawGallery();
    return;
  }
  // Data Management 模式：文件列表独占全屏
  if (dataOpen) {
    drawDataManager();
    return;
  }

  // 全屏 Boids（带拖尾）
  drawBoidLayer();
  
  // 右上角情绪面板
  drawEmotionUI();
  
  // 底部 Valence / Arousal 实时折线图（RealtimeChart.pde 已整体注释，暂时停用；恢复时两处一起取消注释）
  // drawRealtimeCharts();
  
  // 左上角标签
  drawScreenLabels();

  // EEG 连接状态（上方中央）与 瞑想开始/结束 按钮（右下）
  drawEEGStatus();
  drawRecordButton();
}

// Boids 画到独立图层上：在图层上做半透明黑色淡出（原来的拖尾效果），再整体贴到屏幕。
// 图层的更新在 BoidControl.pde 的 stepLiveSim() 中进行（每一步画一次），这里只负责贴到屏幕。
void drawBoidLayer() {
  if (boidLayer != null) image(boidLayer, 0, 0);
}

// 每帧开始：淡出一次（拖尾）
void beginBoidLayer() {
  if (boidLayer == null || boidLayer.width != width || boidLayer.height != height) {
    boidLayer = createGraphics(width, height);
    boidLayer.beginDraw();
    boidLayer.background(0);
    boidLayer.endDraw();
  }
  boidLayer.beginDraw();
  boidLayer.noStroke();
  boidLayer.fill(0, 0, 0, 20);
  boidLayer.rect(0, 0, width, height);
}

// 把当前这一步的鱼画到图层上
// 虚拟世界（1600×1000）按比例缩放到窗口；比例不同时上下或左右留出与背景同色的边
void drawLiveBoids() {
  float sc = min(width / LP_WORLD_W, height / LP_WORLD_H);
  boidLayer.pushMatrix();
  boidLayer.translate((width - LP_WORLD_W * sc) / 2, (height - LP_WORLD_H * sc) / 2);
  boidLayer.scale(sc);
  for (Boid b : liveSim.boids) {
    b.showOn(boidLayer, liveSim.v, liveSim.a);
  }
  boidLayer.popMatrix();
}

void drawLeftScreen() {
  // 绘制上一次会话的Boids
  for (Boid b : boidsLeft) {
    b.show(lastSessionData.get(currentFrameInLastSession).valence, 
           lastSessionData.get(currentFrameInLastSession).arousal);
  }
}

void drawRightScreen() {
  // 绘制当前会话的Boids
  for (Boid b : boidsRight) {
    b.show(valence, arousal);
  }
  
  // 原来的UI在右上角
  drawEmotionUI();
}

void drawScreenLabels() {
  // 右屏标签
  fill(100, 150, 255);
  textSize(18);
  textAlign(LEFT);
  text("現在のセッション", 70, 40);
  
  fill(200);
  textSize(12);
  text("A: " + nf(arousal, 1, 2) + "  V: " + nf(valence, 1, 2), 70, 65);
  text("Boids: " + boidsRight.size(), 70, 85);
  
  // 底部提示
  fill(150);
  textSize(10);
  textAlign(CENTER);
  text("Press X to exit and save", width/2, height - 20);
}
