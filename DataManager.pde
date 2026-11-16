// ===== Data Management（菜单第 3 项）=====
// 仿照电脑文件夹（Finder）的列表视图：
//   左侧栏：「外部からインポート」（选择电脑中的 CSV 导入）／「既存の CSV」（文件列表）
//   右侧：文件列表（名前・日時・長さ・行数・種類・帯域・平均A・平均V・推定），可滚动
//   单击选中，双击或点击「▶ 再生」进行回放（回放结束后过渡为光绘）
// 本次录制中的 CSV 不显示（录制结束后才出现）。

boolean dataOpen = false;
ArrayList<GalleryEntry> dmFiles = new ArrayList<GalleryEntry>();
String dmSelected = null;
GalleryEntry dmPendingDelete = null;   // 删除确认窗口中的对象
float dmScroll = 0;
int dmLastClickMs = 0;
String dmLastClickName = null;
ArrayList<GalleryHot> dmHots = new ArrayList<GalleryHot>();

float DM_SIDEBAR_X = 60, DM_SIDEBAR_W = 220;
float DM_ROW_H = 30;

boolean isRealtimeMode() {
  return !galleryOpen && !dataOpen;
}

void refreshDataList() {
  dmFiles.clear();
  File folder = sessionsDir();
  File[] files = folder.listFiles((dir, name) -> name.startsWith("eeg_session_") && name.endsWith(".csv"));
  if (files == null) return;
  Arrays.sort(files, (a, b) -> b.getName().compareTo(a.getName()));   // 新→旧
  for (File f : files) {
    if (f.getName().equals(currentSessionFile)) continue;
    GalleryEntry e = galleryCache.get(f.getName());
    if (e == null) {
      e = new GalleryEntry(f);
      galleryCache.put(f.getName(), e);
    }
    dmFiles.add(e);
  }
}

void drawDataManager() {
  dmHots.clear();
  background(14);

  // 标题
  noStroke();
  fill(100, 200, 100);
  textSize(22);
  textAlign(LEFT, CENTER);
  text("Data Management", 70, 36);
  if (isRecording) {
    fill(255, 150, 150);
    textSize(12);
    textAlign(RIGHT, CENTER);
    text("● REC  " + recordingElapsedText(), width - 40, 38);
  }

  float top = 76;
  float bottom = height - 40;

  // ---- 左侧栏 ----
  fill(20);
  rect(DM_SIDEBAR_X, top, DM_SIDEBAR_W, bottom - top, 8);
  fill(120);
  textSize(11);
  textAlign(LEFT, CENTER);
  text("操作", DM_SIDEBAR_X + 16, top + 22);
  drawDmSideItem(top + 40, "＋  外部からインポート", "import", false);
  drawDmSideItem(top + 80, "▤  既存の CSV", "list", true);

  fill(110);
  textSize(10);
  text("保存場所：", DM_SIDEBAR_X + 16, bottom - 44);
  String folderName = dataRoot().getName() + "/" + sessionsDir().getName();
  text(folderName, DM_SIDEBAR_X + 16, bottom - 28);
  if (importBusy) {
    fill(200, 200, 120);
    textSize(11);
    text(importProgress, DM_SIDEBAR_X + 16, top + 130);
  }

  // ---- 右侧：工具栏 ----
  float mx = DM_SIDEBAR_X + DM_SIDEBAR_W + 20;
  float mw = width - 40 - mx;
  fill(200);
  textSize(15);
  textAlign(LEFT, CENTER);
  text("既存の CSV", mx, top + 16);
  fill(120);
  textSize(11);
  text(dmFiles.size() + " 項目", mx + textWidth("既存の CSV") + 60, top + 17);

  GalleryEntry sel = dmFind(dmSelected);
  boolean canPlay = sel != null && sel.rows >= 2;
  drawDmButton(mx + mw - 120, top + 2, 120, 28, "▶  再生", "play", canPlay);
  drawDmButton(mx + mw - 230, top + 2, 100, 28, "削除", "delete", sel != null);
  drawDmButton(mx + mw - 410, top + 2, 170, 28, "＋  外部からインポート", "import", !importBusy);

  // ---- 列表 ----
  float lx = mx, ly = top + 44, lw = mw, lh = bottom - ly - 30;
  fill(18);
  rect(lx, ly, lw, lh, 6);

  // 列定义：标题与相对宽度
  String[] heads = { "名前", "日時", "長さ", "行数", "種類", "帯域", "平均 A", "平均 V", "推定" };
  float[] ws = { 0.27f, 0.14f, 0.07f, 0.06f, 0.10f, 0.06f, 0.08f, 0.08f, 0.14f };
  float[] cx = new float[ws.length];
  float acc = lx + 12;
  for (int i = 0; i < ws.length; i++) { cx[i] = acc; acc += ws[i] * (lw - 24); }

  // 表头
  fill(26);
  rect(lx, ly, lw, DM_ROW_H, 6, 6, 0, 0);
  fill(140);
  textSize(11);
  textAlign(LEFT, CENTER);
  for (int i = 0; i < heads.length; i++) text(heads[i], cx[i], ly + DM_ROW_H / 2);

  // 行
  float rowsTop = ly + DM_ROW_H;
  float rowsH = lh - DM_ROW_H;
  float contentH = dmFiles.size() * DM_ROW_H;
  dmScroll = constrain(dmScroll, 0, max(0, contentH - rowsH));
  clip(lx, rowsTop, lw, rowsH);
  for (int i = 0; i < dmFiles.size(); i++) {
    float ry = rowsTop + i * DM_ROW_H - dmScroll;
    if (ry + DM_ROW_H < rowsTop || ry > rowsTop + rowsH) continue;
    GalleryEntry e = dmFiles.get(i);
    boolean isSel = e.name.equals(dmSelected);
    boolean hover = mouseX >= lx && mouseX <= lx + lw && mouseY >= max(ry, rowsTop) && mouseY <= min(ry + DM_ROW_H, rowsTop + rowsH);
    noStroke();
    if (isSel) fill(40, 72, 120);
    else if (hover) fill(32);
    else fill(i % 2 == 0 ? 18 : 22);
    rect(lx, ry, lw, DM_ROW_H);

    boolean imported = e.name.endsWith("_mm.csv");
    boolean playable = e.rows >= 2;
    // 文件图标
    drawFileIcon(cx[0] + 6, ry + DM_ROW_H / 2, imported ? color(110, 170, 255) : color(110, 210, 130), playable);

    fill(playable ? 225 : 120);
    textSize(12);
    textAlign(LEFT, CENTER);
    float ty = ry + DM_ROW_H / 2;
    text(e.name, cx[0] + 22, ty);
    fill(playable ? 180 : 110);
    text(e.label, cx[1], ty);
    text(formatDuration(e.durationMs), cx[2], ty);
    text(str(e.rows), cx[3], ty);
    text(imported ? "インポート" : "記録", cx[4], ty);
    text(e.columns >= 25 ? "あり" : "なし", cx[5], ty);
    if (playable) {
      text(signed(e.meanA), cx[6], ty);
      text(signed(e.meanV), cx[7], ty);
      fill(moodColor(e.moodIndex));
      ellipse(cx[8] + 4, ty, 8, 8);
      fill(180);
      text(e.mood + " " + round(e.moodRatio * 100) + "%", cx[8] + 14, ty);
    } else {
      fill(110);
      text("データなし", cx[6], ty);
    }
    if (ry >= rowsTop - DM_ROW_H) dmHots.add(new GalleryHot(lx, max(ry, rowsTop), lw, min(ry + DM_ROW_H, rowsTop + rowsH) - max(ry, rowsTop), "row", e.name));
  }
  noClip();

  if (dmFiles.size() == 0) {
    fill(120);
    textSize(13);
    textAlign(CENTER, CENTER);
    text("CSV ファイルがありません。「外部からインポート」から追加できます", lx + lw / 2, rowsTop + rowsH / 2);
  }

  // 滚动条
  if (contentH > rowsH) {
    float barH = max(30, rowsH * rowsH / contentH);
    float barY = rowsTop + (rowsH - barH) * (dmScroll / (contentH - rowsH));
    fill(70);
    rect(lx + lw - 6, barY, 4, barH, 2);
  }

  // 状态栏
  fill(120);
  textSize(11);
  textAlign(LEFT, CENTER);
  String status = sel != null ? "選択中：" + sel.name + "　（ダブルクリックで再生）" : "ファイルをクリックで選択、ダブルクリックで再生";
  text(status, lx, bottom - 12);
  textAlign(LEFT);

  if (dmPendingDelete != null) drawDeleteDialog(dmHots, dmPendingDelete);
}

void drawDmSideItem(float y, String label, String action, boolean active) {
  float x = DM_SIDEBAR_X + 8, w = DM_SIDEBAR_W - 16, h = 32;
  boolean hover = mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  noStroke();
  if (active) fill(40, 72, 120);
  else if (hover) fill(34);
  else fill(20);
  rect(x, y, w, h, 6);
  fill(active ? 235 : 200);
  textSize(13);
  textAlign(LEFT, CENTER);
  text(label, x + 12, y + h / 2);
  dmHots.add(new GalleryHot(x, y, w, h, action, null));
}

void drawDmButton(float x, float y, float w, float h, String label, String action, boolean enabled) {
  boolean hover = enabled && mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  noStroke();
  fill(enabled ? (hover ? 60 : 42) : 28);
  rect(x, y, w, h, 6);
  fill(enabled ? 225 : 100);
  textSize(12);
  textAlign(CENTER, CENTER);
  text(label, x + w / 2, y + h / 2);
  textAlign(LEFT);
  if (enabled) dmHots.add(new GalleryHot(x, y, w, h, action, null));
}

void drawFileIcon(float x, float y, int c, boolean solid) {
  float w = 12, h = 15;
  noStroke();
  fill(red(c), green(c), blue(c), solid ? 200 : 90);
  beginShape();
  vertex(x - w / 2, y - h / 2);
  vertex(x + w / 2 - 4, y - h / 2);
  vertex(x + w / 2, y - h / 2 + 4);
  vertex(x + w / 2, y + h / 2);
  vertex(x - w / 2, y + h / 2);
  endShape(CLOSE);
  fill(0, 80);
  triangle(x + w / 2 - 4, y - h / 2, x + w / 2, y - h / 2 + 4, x + w / 2 - 4, y - h / 2 + 4);
}

GalleryEntry dmFind(String name) {
  if (name == null) return null;
  for (GalleryEntry e : dmFiles) if (e.name.equals(name)) return e;
  return null;
}

void dmPlay(GalleryEntry e) {
  if (e == null) return;
  if (e.rows < 2) {
    showToast("データが不足しているため再生できません");
    return;
  }
  openReplay(e.csv, e.label + "（" + (e.name.endsWith("_mm.csv") ? "インポート" : "記録") + "）");
}

boolean dmHandleClick(float mx, float my) {
  if (!dataOpen) return false;
  // 确认窗口打开时：只响应窗口内的两个按钮
  if (dmPendingDelete != null) {
    for (GalleryHot h : dmHots) {
      if (!h.contains(mx, my)) continue;
      if (h.action.equals("confirmDelete")) {
        deleteSession(dmPendingDelete.csv);
        dmSelected = null;
        dmPendingDelete = null;
        refreshDataList();
      } else if (h.action.equals("cancelDelete")) {
        dmPendingDelete = null;
      }
      return true;
    }
    return true;
  }
  for (GalleryHot h : dmHots) {
    if (!h.contains(mx, my)) continue;
    if (h.action.equals("delete")) {
      dmPendingDelete = dmFind(dmSelected);
    } else if (h.action.equals("import")) {
      startImportDialog();
    } else if (h.action.equals("play")) {
      dmPlay(dmFind(dmSelected));
    } else if (h.action.equals("row")) {
      int now = millis();
      boolean dbl = h.key.equals(dmLastClickName) && now - dmLastClickMs < 450;
      dmSelected = h.key;
      dmLastClickName = h.key;
      dmLastClickMs = now;
      if (dbl) dmPlay(dmFind(h.key));
    }
    return true;
  }
  return false;
}

void mouseWheel(MouseEvent event) {
  if (dataOpen && !replayActive) dmScroll += event.getCount() * DM_ROW_H;
}
