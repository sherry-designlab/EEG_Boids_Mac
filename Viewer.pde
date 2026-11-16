// ===== 作品查看画面（画廊中点击缩略图或 ⤢）=====
// A：左边是作品，右边是信息（日期・时长・A/V 平均・推定・标签・メモ・标记），按钮：再生・メモを編集・削除。
//    ← → 切换到同一天的上一张 / 下一张。
// 点击作品 → 纯享模式：窗口里只显示作品；右键「画像を保存…」可保存 4K 原图；点击或 ESC 返回。

GalleryEntry viewerEntry = null;
boolean viewerPure = false;
volatile PImage viewerImg = null;      // 作品（缩小到 1920 宽用于显示）
String viewerImgName = null;
int viewerGen = 0;
ArrayList<GalleryHot> viewerHots = new ArrayList<GalleryHot>();
float vImgX, vImgY, vImgW, vImgH;
boolean viewerMenuOpen = false;        // 纯享模式的右键菜单
float viewerMenuX, viewerMenuY;
int viewerPureStart = 0;

void openViewer(GalleryEntry e) {
  if (e == null) return;
  viewerEntry = e;
  viewerPure = false;
  viewerMenuOpen = false;
  loadViewerImage(e);
}

void closeViewer() {
  viewerEntry = null;
  viewerPure = false;
  viewerImg = null;
  viewerImgName = null;
  viewerGen++;
}

void loadViewerImage(GalleryEntry e) {
  viewerImg = null;
  viewerImgName = e.name;
  final int gen = ++viewerGen;
  final File f = e.csv;
  Thread t = new Thread(() -> {
    PImage big = loadArtwork(f);
    if (big != null && gen == viewerGen) viewerImg = downscale(big, 1920);
  });
  t.setDaemon(true);
  t.start();
}

// 同一天的上一张 / 下一张
GalleryEntry viewerNeighbor(int dir) {
  if (viewerEntry == null) return null;
  ArrayList<GalleryEntry> list = galleryByDay.get(viewerEntry.dateKey);
  if (list == null) return null;
  int i = list.indexOf(viewerEntry) + dir;
  return (i >= 0 && i < list.size()) ? list.get(i) : null;
}

void drawViewer() {
  viewerHots.clear();
  GalleryEntry e = viewerEntry;
  PImage show = viewerImg != null ? viewerImg : e.img;

  if (viewerPure) {
    drawViewerPure(show);
    return;
  }

  background(8);
  float pad = 40, panelW = min(340, width * 0.28f);
  float areaX = pad, areaY = 70, areaW = width - pad * 3 - panelW, areaH = height - areaY - pad;
  float aspect = LP_WORLD_W / LP_WORLD_H;
  vImgW = areaW; vImgH = vImgW / aspect;
  if (vImgH > areaH) { vImgH = areaH; vImgW = vImgH * aspect; }
  vImgX = areaX + (areaW - vImgW) / 2;
  vImgY = areaY + (areaH - vImgH) / 2;

  if (show != null) image(show, vImgX, vImgY, vImgW, vImgH);
  else { noStroke(); fill(20); rect(vImgX, vImgY, vImgW, vImgH); fill(120); textSize(12); textAlign(CENTER, CENTER); text("準備中…", vImgX + vImgW / 2, vImgY + vImgH / 2); }
  boolean overImg = mouseX >= vImgX && mouseX <= vImgX + vImgW && mouseY >= vImgY && mouseY <= vImgY + vImgH;
  noFill();
  stroke(overImg ? 110 : 45);
  strokeWeight(1);
  rect(vImgX, vImgY, vImgW, vImgH);
  viewerHots.add(new GalleryHot(vImgX, vImgY, vImgW, vImgH, "pure", null));

  // 左右切换
  if (viewerNeighbor(-1) != null) drawViewerArrow(vImgX - 22, vImgY + vImgH / 2, -1);
  if (viewerNeighbor(1) != null) drawViewerArrow(vImgX + vImgW + 22, vImgY + vImgH / 2, 1);

  // 右上角的关闭按钮（×）：返回画廊
  float cx = width - 32, cy = 32;
  boolean overX = dist(mouseX, mouseY, cx, cy) < 14 && galleryPendingDelete == null;
  noStroke();
  fill(overX ? 70 : 38);
  ellipse(cx, cy, 26, 26);
  stroke(overX ? 245 : 190);
  strokeWeight(1.6f);
  line(cx - 5, cy - 5, cx + 5, cy + 5);
  line(cx + 5, cy - 5, cx - 5, cy + 5);
  noStroke();
  viewerHots.add(new GalleryHot(cx - 14, cy - 14, 28, 28, "close", null));

  // ---- 右侧信息 ----
  float px = width - pad - panelW, py = areaY;
  fill(235);
  textSize(20);
  textAlign(LEFT, TOP);
  text(e.label.length() >= 10 ? e.label.substring(0, 10) : e.label, px, py);
  fill(160);
  textSize(13);
  text(e.timeLabel + "　・　" + formatDuration(e.durationMs) + (e.name.endsWith("_mm.csv") ? "　・　インポート" : ""), px, py + 32);

  float y = py + 66;
  stroke(40);
  line(px, y, px + panelW, y);
  noStroke();
  y += 14;
  textSize(13);
  fill(200);
  text("Arousal 平均", px, y);
  text(signed(e.meanA), px + 120, y);
  y += 22;
  text("Valence 平均", px, y);
  text(signed(e.meanV), px + 120, y);
  y += 22;
  fill(moodColor(e.moodIndex));
  ellipse(px + 5, y + 8, 8, 8);
  fill(200);
  text("推定  " + e.mood + "  " + round(e.moodRatio * 100) + "%", px + 16, y);
  y += 34;
  stroke(40);
  line(px, y, px + panelW, y);
  noStroke();
  y += 14;

  // 标签
  if (e.tags.length > 0) {
    y = drawTagChips(e.tags, px, y, panelW, 12) + 12;
  }
  // メモ（全文）
  textSize(13);
  textAlign(LEFT, TOP);
  if (e.diaryText.length() > 0) {
    fill(215);
    ArrayList<String> lines = wrapChars(e.diaryText, panelW);
    for (String l : lines) {
      if (y > height - 170) { text("…", px, y); y += 20; break; }
      text(l, px, y);
      y += 20;
    }
  } else {
    fill(110);
    text(e.tags.length > 0 ? "" : "メモはまだありません", px, y);
    y += 20;
  }
  // 标记
  if (e.markers.size() > 0) {
    y += 10;
    fill(140);
    textSize(11);
    text("瞑想中のマーク", px, y);
    y += 18;
    textSize(12);
    for (int i = 0; i < e.markers.size() && y < height - 150; i++) {
      fill(170);
      text(formatDuration(e.markers.get(i)[0]), px, y);
      fill(210);
      String lb = e.markerLabels.get(i);
      text(lb.length() > 0 ? ellipsize(lb, panelW - 60) : "（名前なし）", px + 56, y);
      y += 18;
    }
  }

  // 按钮
  float bw = (panelW - 16) / 3, bh = 34, by = height - pad - bh;
  drawViewerButton(px, by, bw, bh, "▶  再生", "replay", true);
  drawViewerButton(px + bw + 8, by, bw, bh, "メモを編集", "edit", false);
  drawViewerButton(px + (bw + 8) * 2, by, bw, bh, "削除", "delete", false);
  textAlign(LEFT);

  if (galleryPendingDelete != null) drawDeleteDialog(viewerHots, galleryPendingDelete);
}

// 标签：小圆角块，自动换行；返回下一行的 y
float drawTagChips(String[] tags, float x, float y, float w, float ts) {
  textSize(ts);
  textAlign(LEFT, CENTER);
  float cx = x, h = ts + 10;
  for (String t : tags) {
    float tw = textWidth(t) + 14;
    if (cx + tw > x + w && cx > x) { cx = x; y += h + 6; }
    noStroke();
    fill(37, 42, 54);
    rect(cx, y, tw, h, h / 2);
    fill(175, 185, 205);
    text(t, cx + 7, y + h / 2);
    cx += tw + 6;
  }
  return y + h;
}

void drawViewerButton(float x, float y, float w, float h, String label, String action, boolean primary) {
  boolean hover = mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h && galleryPendingDelete == null;
  noStroke();
  if (action.equals("delete")) fill(hover ? color(150, 60, 60) : color(55, 35, 35));
  else if (primary) fill(hover ? color(70, 140, 80) : color(45, 95, 55));
  else fill(hover ? 70 : 45);
  rect(x, y, w, h, 6);
  fill(230);
  textSize(13);
  textAlign(CENTER, CENTER);
  text(label, x + w / 2, y + h / 2);
  viewerHots.add(new GalleryHot(x, y, w, h, action, null));
}

void drawViewerArrow(float x, float y, int dir) {
  boolean hover = dist(mouseX, mouseY, x, y) < 16;
  noStroke();
  fill(hover ? 200 : 110);
  if (dir < 0) triangle(x + 6, y - 10, x + 6, y + 10, x - 8, y);
  else triangle(x - 6, y - 10, x - 6, y + 10, x + 8, y);
  viewerHots.add(new GalleryHot(x - 16, y - 20, 32, 40, dir < 0 ? "prev" : "next", null));
}

// ---- 纯享模式 ----
void drawViewerPure(PImage show) {
  background(0);
  float aspect = LP_WORLD_W / LP_WORLD_H;
  float w = width, h = w / aspect;
  if (h > height) { h = height; w = h * aspect; }
  float x = (width - w) / 2, y = (height - h) / 2;
  if (show != null) image(show, x, y, w, h);
  // 提示：几秒后淡出
  float t = (millis() - viewerPureStart) / 1000.0f;
  float a = constrain(3 - t, 0, 1);
  if (a > 0) {
    fill(170, 170, 170, 200 * a);
    textSize(12);
    textAlign(CENTER, CENTER);
    text("右クリックで画像を保存 ・ クリック / ESC で戻る", width / 2, height - 24);
  }
  if (viewerMenuOpen) {
    float mw = 170, mh = 34;
    float mx = min(viewerMenuX, width - mw - 4), my = min(viewerMenuY, height - mh - 4);
    boolean hover = mouseX >= mx && mouseX <= mx + mw && mouseY >= my && mouseY <= my + mh;
    noStroke();
    fill(hover ? 60 : 36);
    rect(mx, my, mw, mh, 6);
    fill(230);
    textSize(13);
    textAlign(LEFT, CENTER);
    text("画像を保存…（4K）", mx + 14, my + mh / 2);
    viewerHots.add(new GalleryHot(mx, my, mw, mh, "save", null));
  }
  textAlign(LEFT);
}

// 返回 true = 已处理
boolean viewerHandleClick(float mx, float my) {
  if (viewerEntry == null) return false;
  if (viewerPure) {
    if (mouseButton == RIGHT) {
      viewerMenuOpen = true;
      viewerMenuX = mx;
      viewerMenuY = my;
      return true;
    }
    if (viewerMenuOpen) {
      for (GalleryHot h : viewerHots) if (h.action.equals("save") && h.contains(mx, my)) saveArtworkAs(viewerEntry);
      viewerMenuOpen = false;
      return true;
    }
    viewerPure = false;
    return true;
  }
  if (galleryPendingDelete != null) {
    for (GalleryHot h : viewerHots) {
      if (!h.contains(mx, my)) continue;
      if (h.action.equals("confirmDelete")) {
        GalleryEntry next = viewerNeighbor(1);
        if (next == null) next = viewerNeighbor(-1);
        deleteGalleryEntry(galleryPendingDelete);
        galleryPendingDelete = null;
        if (next != null) openViewer(next); else closeViewer();
      } else if (h.action.equals("cancelDelete")) {
        galleryPendingDelete = null;
      }
      return true;
    }
    return true;
  }
  for (GalleryHot h : viewerHots) {
    if (!h.contains(mx, my)) continue;
    if (h.action.equals("pure")) {
      viewerPure = true;
      viewerMenuOpen = false;
      viewerPureStart = millis();
    } else if (h.action.equals("close")) {
      closeViewer();
    } else if (h.action.equals("prev")) {
      openViewer(viewerNeighbor(-1));
    } else if (h.action.equals("next")) {
      openViewer(viewerNeighbor(1));
    } else if (h.action.equals("replay")) {
      openReplay(viewerEntry.csv, viewerEntry.label + "（" + formatDuration(viewerEntry.durationMs) + "）");
    } else if (h.action.equals("edit")) {
      openDiaryEditor(viewerEntry.csv, viewerEntry.label + " のメモ");
    } else if (h.action.equals("delete")) {
      galleryPendingDelete = viewerEntry;
    }
    return true;
  }
  return true;
}

// 键盘：← → 切换，ESC 返回
boolean viewerHandleKey() {
  if (viewerEntry == null) return false;
  if (key == ESC) {
    key = 0;
    if (galleryPendingDelete != null) galleryPendingDelete = null;
    else if (viewerPure) { viewerPure = false; viewerMenuOpen = false; }
    else closeViewer();
    return true;
  }
  if (key == CODED && !viewerPure && galleryPendingDelete == null) {
    if (keyCode == LEFT && viewerNeighbor(-1) != null) openViewer(viewerNeighbor(-1));
    if (keyCode == RIGHT && viewerNeighbor(1) != null) openViewer(viewerNeighbor(1));
  }
  return key == CODED;
}

// 右键「画像を保存…」：把 4K 作品复制到用户选择的位置
GalleryEntry saveAsEntry = null;
void saveArtworkAs(GalleryEntry e) {
  saveAsEntry = e;
  File def = new File(System.getProperty("user.home"), "Desktop/" + stemOf(e.name) + ".png");
  selectOutput("画像の保存先を選んでください", "saveArtworkSelected", def);
}

void saveArtworkSelected(File out) {
  if (out == null || saveAsEntry == null) return;
  if (!out.getName().toLowerCase().endsWith(".png")) out = new File(out.getParentFile(), out.getName() + ".png");
  try {
    if (!ensureArtwork(saveAsEntry.csv)) throw new Exception("作品がありません");
    java.nio.file.Files.copy(artworkFile(saveAsEntry.name).toPath(), out.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
    showToast("保存しました：" + out.getName());
  } catch (Exception ex) {
    showToast("保存できませんでした：" + ex.getMessage());
  }
}
