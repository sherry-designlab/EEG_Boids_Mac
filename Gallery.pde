// ===== 画廊（全屏 + 日历） =====
// Gallery 模式独占全屏（不显示 Boids 和实时折线图，EEG 仍在后台记录）。
// 左：月历。有记录的日期显示当天最后一张光绘缩图、次数和每次的心情色点。
// 右：选中日期的全部光绘，按时间先后排列（3 列 × 2 行，超过时可翻页）。
// 鼠标悬停在光绘上时，在旁边显示 A / V 平均值与心情推测；右上角出现删除按钮（×）。
// 删除时弹出日语确认窗口，确认后同时删除 CSV、JSON、作品和缩略图（Artwork.pde 的 deleteSession）。
// 缩略图来自作品存档（artworks/），生成一次后不再重新计算。

boolean galleryOpen = false;

ArrayList<GalleryEntry> galleryEntries = new ArrayList<GalleryEntry>();          // 新→旧
HashMap<String, ArrayList<GalleryEntry>> galleryByDay =
  new HashMap<String, ArrayList<GalleryEntry>>();                                // 日期 → 当天会话（早→晚）
HashMap<String, GalleryEntry> galleryCache = new HashMap<String, GalleryEntry>();
java.util.concurrent.LinkedBlockingQueue<GalleryEntry> galleryQueue =
  new java.util.concurrent.LinkedBlockingQueue<GalleryEntry>();
Thread galleryWorker = null;

int calYear = 0, calMonth = 0;          // 日历当前显示的年月（calMonth: 1-12）
String gallerySelectedDay = null;       // 选中的日期 yyyyMMdd
int galleryDayPage = 0;                 // 当天光绘的页码
final int DAY_COLS = 3, DAY_ROWS = 2;   // 当天光绘每页 3 列 × 2 行

String[] WEEK_JP = { "日", "月", "火", "水", "木", "金", "土" };
String[] MOOD_NAMES = { "Excited", "Alerted", "Relax", "Tired" };

// 可点击区域：每帧绘制时登记，点击时判定
class GalleryHot {
  float x, y, w, h;
  String action, key;
  GalleryHot(float x, float y, float w, float h, String action, String key) {
    this.x = x; this.y = y; this.w = w; this.h = h;
    this.action = action; this.key = key;
  }
  boolean contains(float mx, float my) {
    return mx >= x && mx <= x + w && my >= y && my <= y + h;
  }
}
ArrayList<GalleryHot> galleryHots = new ArrayList<GalleryHot>();

GalleryEntry galleryPendingDelete = null;   // 删除确认窗口中的对象（null = 窗口未打开）
GalleryEntry galleryMemoPopup = null;       // 显示メモ全文的浮动框

int moodColor(int idx) {
  if (idx == 0) return color(255, 170, 70);    // Excited：橙
  if (idx == 1) return color(255, 100, 100);   // Alerted：红
  if (idx == 2) return color(110, 210, 150);   // Relax：绿
  if (idx == 3) return color(130, 150, 255);   // Tired：蓝
  return color(120);
}

class GalleryEntry {
  File csv;
  String name;
  String label = "";       // 例：2026/10/30 14:17
  String dateKey = "";     // 例：20261030（日历分组用）
  String timeLabel = "";   // 例：14:17
  int rows = 0;            // 有效数据行数
  int columns = 0;         // 列数（25 = 带频段数据的新格式）
  long durationMs = 0;     // 记录时长
  float meanA = 0, meanV = 0;   // 整场 A / V 平均值（正规化值）
  String mood = "-";            // 停留最久的象限
  int moodIndex = -1;           // 0 Excited, 1 Alerted, 2 Relax, 3 Tired
  float moodRatio = 0;          // 该象限所占时间比例
  volatile PImage img = null;
  volatile boolean failed = false;
  volatile boolean queued = false;
  volatile boolean deleted = false;   // 已删除（后台线程据此放弃生成/保存）
  String diaryText = "";        // 心情日记（Diary.pde）
  String[] tags = new String[0];
  ArrayList<long[]> markers = new ArrayList<long[]>();   // {ms, step}
  ArrayList<String> markerLabels = new ArrayList<String>();

  void loadDiary() {
    JSONObject m = sessionMetaLoad(csv);
    diaryText = diaryTextOf(m);
    tags = diaryTagsOf(m);
    markers.clear();
    markerLabels.clear();
    if (m != null && m.hasKey("markers")) {
      JSONArray arr = m.getJSONArray("markers");
      for (int i = 0; i < arr.size(); i++) {
        JSONObject k = arr.getJSONObject(i);
        markers.add(new long[] { k.getLong("ms", 0), k.getInt("step", 0) });
        markerLabels.add(k.getString("label", ""));
      }
    }
  }

  boolean hasDiary() { return diaryText.length() > 0 || tags.length > 0; }

  GalleryEntry(File f) {
    csv = f;
    name = f.getName();
    String ts = name.substring("eeg_session_".length(), name.length() - 4);  // yyyyMMdd_HHmmss
    if (ts.length() >= 13) {
      label = ts.substring(0, 4) + "/" + ts.substring(4, 6) + "/" + ts.substring(6, 8)
            + " " + ts.substring(9, 11) + ":" + ts.substring(11, 13);
      dateKey = ts.substring(0, 8);
      timeLabel = ts.substring(9, 11) + ":" + ts.substring(11, 13);
    } else {
      label = ts;
    }
    String[] lines = loadStrings(f.getAbsolutePath());
    if (lines == null) return;
    if (lines.length > 0) columns = split(lines[0], ',').length;
    long first = -1, last = -1;
    float sumA = 0, sumV = 0;
    int nAV = 0;
    int[] quad = new int[4];   // 0 Excited(A+V+), 1 Alerted(A+V-), 2 Relax(A-V+), 3 Tired(A-V-)
    for (int i = 1; i < lines.length; i++) {
      String[] p = split(lines[i], ',');
      if (p.length < 5) continue;
      try {
        long t = Long.parseLong(p[0]);
        if (first < 0) first = t;
        last = t;
        rows++;
        float a = Float.parseFloat(p[3]);
        float v = Float.parseFloat(p[4]);
        if (!Float.isNaN(a) && !Float.isNaN(v)) {
          sumA += a;
          sumV += v;
          nAV++;
          if (a >= 0 && v >= 0) quad[0]++;
          else if (a >= 0)      quad[1]++;
          else if (v >= 0)      quad[2]++;
          else                  quad[3]++;
        }
      } catch (NumberFormatException e) {
        continue;
      }
    }
    loadDiary();
    if (first >= 0) durationMs = last - first;
    if (nAV > 0) {
      meanA = sumA / nAV;
      meanV = sumV / nAV;
      // 心情推测：逐秒判断所在象限，取停留时间最长的象限
      String[] names = { "Excited", "Alerted", "Relax", "Tired" };
      int best = 0;
      for (int q = 1; q < 4; q++) if (quad[q] > quad[best]) best = q;
      mood = names[best];
      moodIndex = best;
      moodRatio = quad[best] / (float)nAV;
    }
  }
}

// 扫描以往会话（排除本次正在记录的文件、以及只有表头/数据不足的文件），并按日期分组
void refreshGalleryList() {
  File folder = sessionsDir();
  File[] files = folder.listFiles((dir, name) ->
    name.startsWith("eeg_session_") && name.endsWith(".csv")
  );
  galleryEntries.clear();
  galleryByDay.clear();
  if (files != null) {
    // 文件名含时间戳，按名称倒序 = 新→旧
    Arrays.sort(files, (a, b) -> b.getName().compareTo(a.getName()));
    for (File f : files) {
      if (f.getName().equals(currentSessionFile)) continue;
      GalleryEntry e = galleryCache.get(f.getName());
      if (e == null) {
        e = new GalleryEntry(f);
        galleryCache.put(f.getName(), e);
      }
      if (e.rows < 2 || e.dateKey.length() != 8) continue;
      galleryEntries.add(e);
      ArrayList<GalleryEntry> list = galleryByDay.get(e.dateKey);
      if (list == null) {
        list = new ArrayList<GalleryEntry>();
        galleryByDay.put(e.dateKey, list);
      }
      list.add(0, e);   // 倒序遍历时插到最前 → 当天内 早→晚
    }
  }

  // 默认选中最近有记录的一天，并显示它所在的月份
  if (gallerySelectedDay == null || !galleryByDay.containsKey(gallerySelectedDay)) {
    gallerySelectedDay = galleryEntries.size() > 0 ? galleryEntries.get(0).dateKey : null;
    galleryDayPage = 0;
  }
  if (gallerySelectedDay != null) {
    calYear = Integer.parseInt(gallerySelectedDay.substring(0, 4));
    calMonth = Integer.parseInt(gallerySelectedDay.substring(4, 6));
  } else {
    calYear = year();
    calMonth = month();
  }
  println("Gallery: " + galleryEntries.size() + " 件 / " + galleryByDay.size() + " 日");
}

void galleryRequest(GalleryEntry e) {
  if (e.img == null && !e.failed && !e.queued) {
    e.queued = true;
    ensureGalleryWorker();
    galleryQueue.add(e);
  }
}

// 后台生成线程（只启动一次）
void ensureGalleryWorker() {
  if (galleryWorker != null) return;
  galleryWorker = new Thread(() -> {
    while (true) {
      GalleryEntry e;
      try {
        e = galleryQueue.take();
      } catch (InterruptedException ex) {
        return;
      }
      try {
        galleryBuildImage(e);
      } catch (Exception ex) {
        e.failed = true;
        println("生成に失敗しました: " + e.name + " " + ex);
      }
    }
  });
  galleryWorker.setDaemon(true);
  galleryWorker.start();
}

// 缩略图：从作品存档缩小得到（作品还没有时先生成作品，Artwork.pde）
void galleryBuildImage(GalleryEntry e) {
  if (e.deleted) return;
  PImage img = loadThumb(e.csv);
  if (e.deleted) return;
  if (img == null) {
    e.failed = true;
    return;
  }
  e.img = img;
}

// ===== 全屏画廊 =====
void drawGallery() {
  // 作品查看画面（Viewer.pde）打开时：只显示它
  if (viewerEntry != null) {
    drawViewer();
    return;
  }
  galleryHots.clear();
  background(8);

  // 标题
  noStroke();
  fill(100, 200, 100);
  textSize(22);
  textAlign(LEFT, CENTER);
  text("Gallery", 70, 36);
  float tw = textWidth("Gallery");
  fill(140);
  textSize(12);
  text(galleryEntries.size() + " セッション / " + galleryByDay.size() + " 日", 70 + tw + 16, 38);

  // 录制在后台继续时的提示
  if (isRecording) {
    fill(255, 150, 150);
    textAlign(RIGHT, CENTER);
    text("● REC  " + recordingElapsedText(), width - 40, 60);
  }

  // 校准进行中的小提示（画廊模式下不显示大的校准进度条）
  if (!normalization.isCalibrated) {
    float p = (System.currentTimeMillis() - calibrationStartTime) / normalization.calibrationTimeMs;
    fill(200, 200, 120);
    textAlign(RIGHT, CENTER);
    text("キャリブレーション中 " + nf(constrain(p, 0, 1) * 100, 1, 0) + "%", width - 40, 38);
  }

  float top = 80;
  float bottomPad = 50;
  float calX = 70;
  float calW = width * 0.40f - calX;
  float panelX = width * 0.45f;
  float panelW = width - 50 - panelX;

  // 先画右侧当天面板（让它的缩图优先生成），再画日历
  GalleryEntry[] hover = new GalleryEntry[1];
  float[] hoverRect = new float[4];
  drawDayPanel(panelX, top, panelW, height - top - bottomPad, hover, hoverRect);
  drawCalendar(calX, top, calW, height - top - bottomPad);

  // 中间分隔线
  stroke(40);
  strokeWeight(1);
  line(width * 0.425f, top, width * 0.425f, height - bottomPad);

  if (galleryMemoPopup != null) {
    drawMemoPopup(galleryMemoPopup);
  } else if (galleryPendingDelete != null) {
    drawDeleteDialog(galleryHots, galleryPendingDelete);   // 确认窗口打开时：只显示窗口，其余点击无效
  } else if (hover[0] != null) {
    drawGalleryHoverInfo(hover[0], hoverRect[0], hoverRect[1], hoverRect[2], hoverRect[3]);
  }
  textAlign(LEFT);
}

// ----- 月历 -----
void drawCalendar(float x, float y, float w, float h) {
  // 月份标题与切换箭头
  float titleY = y + 18;
  float cx = x + w / 2;
  noStroke();
  fill(220);
  textSize(18);
  textAlign(CENTER, CENTER);
  String title = calYear + "年 " + calMonth + "月";
  text(title, cx, titleY);
  float half = textWidth(title) / 2 + 30;
  drawGalleryArrow(cx - half, titleY, 2, "prevMonth");
  drawGalleryArrow(cx + half, titleY, 3, "nextMonth");

  // 星期
  float headY = y + 56;
  float cell = min(w / 7.0f, (h - 70 - 70) / 6.0f);
  float gridX = x + (w - cell * 7) / 2;
  textSize(12);
  for (int i = 0; i < 7; i++) {
    if (i == 0) fill(230, 120, 120); else if (i == 6) fill(130, 160, 240); else fill(150);
    text(WEEK_JP[i], gridX + i * cell + cell / 2, headY);
  }

  java.util.Calendar c = java.util.Calendar.getInstance();
  c.set(calYear, calMonth - 1, 1);
  int firstDow = c.get(java.util.Calendar.DAY_OF_WEEK) - 1;   // 0 = 日曜
  int days = c.getActualMaximum(java.util.Calendar.DAY_OF_MONTH);
  String todayKey = String.format("%04d%02d%02d", year(), month(), day());

  float gridY = headY + 18;
  int monthCount = 0;
  for (int d = 1; d <= days; d++) {
    int idx = firstDow + d - 1;
    float bx = gridX + (idx % 7) * cell + 3;
    float by = gridY + (idx / 7) * cell + 3;
    float bs = cell - 6;
    String key = String.format("%04d%02d%02d", calYear, calMonth, d);
    ArrayList<GalleryEntry> list = galleryByDay.get(key);
    boolean has = list != null && list.size() > 0;
    boolean hovered = mouseX >= bx && mouseX <= bx + bs && mouseY >= by && mouseY <= by + bs;

    // 格子底色
    noStroke();
    fill(has ? 22 : 14);
    rect(bx, by, bs, bs, 6);

    if (has) {
      monthCount += list.size();
      // 当天最后一张光绘作为缩图（按格子裁切铺满）
      GalleryEntry latest = list.get(list.size() - 1);
      galleryRequest(latest);
      PImage im = latest.img;
      if (im != null) {
        float s = max(bs / im.width, bs / im.height);
        float iw = im.width * s, ih = im.height * s;
        clip(bx, by, bs, bs);
        tint(255, hovered ? 230 : 170);
        image(im, bx + (bs - iw) / 2, by + (bs - ih) / 2, iw, ih);
        noTint();
        noClip();
        fill(0, 70);
        rect(bx, by, bs, bs, 6);
      }
      // 次数
      fill(230);
      textSize(11);
      textAlign(RIGHT, TOP);
      text(list.size() + "回", bx + bs - 6, by + 5);
      // 每次的心情色点（最多 8 个）
      float dot = max(5, bs * 0.08f);
      int nDots = min(list.size(), 8);
      float dx0 = bx + 7;
      for (int i = 0; i < nDots; i++) {
        fill(moodColor(list.get(i).moodIndex));
        ellipse(dx0 + i * (dot + 3) + dot / 2, by + bs - 8 - dot / 2, dot, dot);
      }
      // 这一天有メモ：右下角一个小小的笔记标记
      boolean anyDiary = false;
      for (GalleryEntry ge : list) if (ge.hasDiary()) anyDiary = true;
      if (anyDiary) {
        float mx = bx + bs - 9, my = by + bs - 9;
        stroke(220, 200);
        strokeWeight(1.2f);
        line(mx - 4, my + 3, mx + 3, my - 4);
        line(mx - 4, my + 3, mx - 5, my + 4);
        noStroke();
      }
      galleryHots.add(new GalleryHot(bx, by, bs, bs, "day", key));
    }

    // 日期数字（今天用绿色圆圈标出）
    int dow = idx % 7;
    float nx = bx + 13, ny = by + 13;
    if (key.equals(todayKey)) {
      noFill();
      stroke(100, 200, 100);
      strokeWeight(1.5f);
      ellipse(nx, ny, 22, 22);
      noStroke();
    }
    if (dow == 0) fill(230, 120, 120, has ? 255 : 120);
    else if (dow == 6) fill(130, 160, 240, has ? 255 : 120);
    else fill(has ? 235 : 100);
    textSize(12);
    textAlign(CENTER, CENTER);
    text(d, nx, ny);

    // 选中 / 悬停边框
    noFill();
    if (key.equals(gallerySelectedDay)) {
      stroke(100, 200, 100);
      strokeWeight(2);
      rect(bx, by, bs, bs, 6);
    } else if (has && hovered) {
      stroke(170);
      strokeWeight(1);
      rect(bx, by, bs, bs, 6);
    }
    noStroke();
  }

  // 图例与当月合计
  float legY = gridY + 6 * cell + 22;
  textSize(11);
  textAlign(LEFT, CENTER);
  float lx = gridX;
  for (int i = 0; i < 4; i++) {
    fill(moodColor(i));
    ellipse(lx + 5, legY, 9, 9);
    fill(170);
    text(MOOD_NAMES[i], lx + 14, legY);
    lx += textWidth(MOOD_NAMES[i]) + 34;
  }
  fill(150);
  textAlign(RIGHT, CENTER);
  text("今月 " + monthCount + " セッション", gridX + cell * 7, legY);
  textAlign(LEFT);
}

// ----- 选中日期的光绘列表 -----
void drawDayPanel(float x, float y, float w, float h, GalleryEntry[] hoverOut, float[] hoverRect) {
  ArrayList<GalleryEntry> list = gallerySelectedDay == null ? null : galleryByDay.get(gallerySelectedDay);
  noStroke();
  textAlign(CENTER, CENTER);
  if (list == null || list.size() == 0) {
    fill(120);
    textSize(14);
    text(galleryEntries.size() == 0 ? "過去のセッションがありません" : "カレンダーから日付を選んでください",
         x + w / 2, y + h / 2);
    textAlign(LEFT);
    return;
  }

  // 日期标题
  int yy = Integer.parseInt(gallerySelectedDay.substring(0, 4));
  int mm = Integer.parseInt(gallerySelectedDay.substring(4, 6));
  int dd = Integer.parseInt(gallerySelectedDay.substring(6, 8));
  java.util.Calendar c = java.util.Calendar.getInstance();
  c.set(yy, mm - 1, dd);
  String wk = WEEK_JP[c.get(java.util.Calendar.DAY_OF_WEEK) - 1];
  long totalMs = 0;
  for (GalleryEntry e : list) totalMs += e.durationMs;

  fill(230);
  textSize(20);
  textAlign(LEFT, CENTER);
  text(yy + "年" + mm + "月" + dd + "日（" + wk + "）", x, y + 18);
  fill(150);
  textSize(12);
  text(list.size() + " セッション ・ 合計 " + formatDuration(totalMs), x, y + 46);

  // 网格
  int perPage = DAY_COLS * DAY_ROWS;
  int pages = max(1, ceil(list.size() / (float)perPage));
  galleryDayPage = constrain(galleryDayPage, 0, pages - 1);
  float gridY = y + 72;
  float gridH = h - 72 - (pages > 1 ? 40 : 0);
  float cellW = w / DAY_COLS;
  float cellH = gridH / DAY_ROWS;
  float aspect = LP_WORLD_W / LP_WORLD_H;   // 光绘的比例（虚拟画布，16:10）

  int start = galleryDayPage * perPage;
  for (int k = 0; k < perPage; k++) {
    int idx = start + k;
    if (idx >= list.size()) break;
    GalleryEntry e = list.get(idx);
    galleryRequest(e);

    float maxW = cellW - 24, maxH = cellH - 100;   // 下方留出：时间・按钮 / 标签 / メモ
    float tw = maxW, th = tw / aspect;
    if (th > maxH) { th = maxH; tw = th * aspect; }
    float tx = x + (k % DAY_COLS) * cellW;
    float ty = gridY + (k / DAY_COLS) * cellH;

    PImage im = e.img;
    if (im != null) {
      image(im, tx, ty, tw, th);
    } else {
      noStroke();
      fill(22);
      rect(tx, ty, tw, th);
      fill(120);
      textSize(11);
      textAlign(CENTER, CENTER);
      text(e.failed ? "生成失敗" : "生成中...", tx + tw / 2, ty + th / 2);
    }

    boolean hover = mouseX >= tx && mouseX <= tx + tw && mouseY >= ty && mouseY <= ty + th;
    if (hover) {
      hoverOut[0] = e;
      hoverRect[0] = tx; hoverRect[1] = ty; hoverRect[2] = tw; hoverRect[3] = th;
    }
    noFill();
    stroke(hover ? 150 : 55);
    strokeWeight(1);
    rect(tx, ty, tw, th);

    // 删除按钮（悬停时出现在右上角）
    if (hover && galleryPendingDelete == null) {
      float dx = tx + tw - 16, dy = ty + 16;
      boolean overDel = dist(mouseX, mouseY, dx, dy) < 12;
      noStroke();
      if (overDel) fill(200, 70, 70, 230); else fill(0, 170);
      ellipse(dx, dy, 24, 24);
      stroke(235);
      strokeWeight(1.6f);
      line(dx - 5, dy - 5, dx + 5, dy + 5);
      line(dx + 5, dy - 5, dx - 5, dy + 5);
      noStroke();
      galleryHots.add(new GalleryHot(dx - 12, dy - 12, 24, 24, "delete", e.name));
    }
    // 点击光绘 → 作品查看画面（Viewer.pde）
    if (galleryPendingDelete == null) galleryHots.add(new GalleryHot(tx, ty, tw, th, "view", e.name));

    // 时间、时长、心情色点
    noStroke();
    fill(moodColor(e.moodIndex));
    ellipse(tx + 5, ty + th + 16, 8, 8);
    fill(225);
    textSize(14);
    textAlign(LEFT, CENTER);
    text(e.timeLabel, tx + 16, ty + th + 16);
    float tlw = textWidth(e.timeLabel);
    fill(140);
    textSize(11);
    text(formatDuration(e.durationMs), tx + 16 + tlw + 10, ty + th + 17);

    // 右侧两个小按钮：⤢ 看大图 / ▶ 再生
    float bsz = 24, by = ty + th + 4;
    drawThumbButton(tx + tw - bsz, by, bsz, "play", e.name);
    drawThumbButton(tx + tw - bsz * 2 - 6, by, bsz, "view", e.name);

    // 标签（一行，放不下的省略）
    float ly = ty + th + 34;
    if (e.tags.length > 0) drawTagChipsLine(e.tags, tx, ly, tw);
    // メモ（一行；点击展开全文 / 没有时点击新写）
    float my = ly + (e.tags.length > 0 ? 26 : 0);
    textSize(12);
    textAlign(LEFT, TOP);
    boolean overMemo = mouseX >= tx && mouseX <= tx + tw && mouseY >= my && mouseY <= my + 18 && galleryPendingDelete == null && galleryMemoPopup == null;
    if (e.diaryText.length() > 0) {
      String one = ellipsize(e.diaryText, tw - 18);
      fill(overMemo ? 230 : 185);
      text(one, tx, my);
      if (!one.equals(e.diaryText.replace('\n', ' '))) {
        // 展开记号（小的向下箭头）
        stroke(150);
        strokeWeight(1.3f);
        line(tx + tw - 11, my + 6, tx + tw - 7, my + 10);
        line(tx + tw - 7, my + 10, tx + tw - 3, my + 6);
        noStroke();
      }
    } else {
      fill(overMemo ? 170 : 95);
      text("＋ メモ", tx, my);
    }
    if (galleryPendingDelete == null && galleryMemoPopup == null) galleryHots.add(new GalleryHot(tx, my, tw, 18, "memo", e.name));
    textAlign(LEFT, CENTER);
  }

  // 翻页
  if (pages > 1) {
    float py = y + h - 16;
    float pcx = x + w / 2;
    fill(150);
    textSize(12);
    textAlign(CENTER, CENTER);
    text((galleryDayPage + 1) + " / " + pages, pcx, py);
    if (galleryDayPage > 0) drawGalleryArrow(pcx - 50, py, 2, "prevPage");
    if (galleryDayPage < pages - 1) drawGalleryArrow(pcx + 50, py, 3, "nextPage");
  }
  textAlign(LEFT);
}

// 悬停信息：默认显示在图片右侧，放不下时显示在左侧
void drawGalleryHoverInfo(GalleryEntry e, float ix, float iy, float iw, float ih) {
  String[] lines = {
    "Arousal 平均  " + signed(e.meanA),
    "Valence 平均  " + signed(e.meanV),
    "推定  " + e.mood + "  " + round(e.moodRatio * 100) + "%",
    e.name.endsWith("_mm.csv") ? "Mind Monitor から取り込み ・ クリックで再生" : "クリックで再生"
  };
  textSize(12);
  float lineH = 18;
  float boxW = 0;
  for (String l : lines) boxW = max(boxW, textWidth(l));
  boxW += 18;
  float boxH = lines.length * lineH + 12;
  float bx = ix + iw + 10;
  if (bx + boxW > width - 10) bx = ix - 10 - boxW;
  float by = iy + (ih - boxH) / 2;

  noStroke();
  fill(0, 220);
  rect(bx, by, boxW, boxH, 5);
  stroke(70);
  noFill();
  rect(bx, by, boxW, boxH, 5);
  noStroke();
  fill(moodColor(e.moodIndex));
  rect(bx, by + 6, 3, boxH - 12);
  fill(220);
  textAlign(LEFT, TOP);
  for (int i = 0; i < lines.length; i++) {
    text(lines[i], bx + 10, by + 7 + i * lineH);
  }
  textAlign(LEFT);
}

String signed(float v) {
  return (v >= 0 ? "+" : "") + nf(v, 1, 2);
}

// 三角箭头（dir: 0 上, 1 下, 2 左, 3 右），同时登记点击区域
void drawGalleryArrow(float x, float y, int dir, String action) {
  boolean hover = abs(mouseX - x) < 16 && abs(mouseY - y) < 14;
  noStroke();
  if (hover) fill(100, 200, 100); else fill(170);
  float s = 8;
  if (dir == 0)      triangle(x - s, y + s * 0.5f, x + s, y + s * 0.5f, x, y - s * 0.6f);
  else if (dir == 1) triangle(x - s, y - s * 0.5f, x + s, y - s * 0.5f, x, y + s * 0.6f);
  else if (dir == 2) triangle(x + s * 0.5f, y - s, x + s * 0.5f, y + s, x - s * 0.6f, y);
  else               triangle(x - s * 0.5f, y - s, x - s * 0.5f, y + s, x + s * 0.6f, y);
  galleryHots.add(new GalleryHot(x - 16, y - 14, 32, 28, action, null));
}

// 返回 true 表示点击已被画廊处理
boolean galleryHandleClick(float mx, float my) {
  if (!galleryOpen) return false;
  if (viewerEntry != null) return viewerHandleClick(mx, my);

  // メモ全文的浮动框：点「編集」打开编辑窗口，点其他地方关闭
  if (galleryMemoPopup != null) {
    for (GalleryHot hs : galleryHots) {
      if (hs.action.equals("memoEdit") && hs.contains(mx, my)) {
        openDiaryEditor(galleryMemoPopup.csv, galleryMemoPopup.label + " のメモ");
      }
    }
    galleryMemoPopup = null;
    return true;
  }

  // 确认窗口打开时：只响应窗口内的两个按钮
  if (galleryPendingDelete != null) {
    for (GalleryHot hs : galleryHots) {
      if (!hs.contains(mx, my)) continue;
      if (hs.action.equals("confirmDelete")) {
        deleteGalleryEntry(galleryPendingDelete);
        galleryPendingDelete = null;
      } else if (hs.action.equals("cancelDelete")) {
        galleryPendingDelete = null;
      }
      return true;
    }
    return true;
  }

  // 删除按钮优先（它在缩图之上）
  for (GalleryHot hs : galleryHots) {
    if (hs.action.equals("delete") && hs.contains(mx, my)) {
      galleryPendingDelete = galleryCache.get(hs.key);
      return true;
    }
  }

  for (GalleryHot hs : galleryHots) {
    if (!hs.contains(mx, my)) continue;
    if (hs.action.equals("prevMonth")) {
      calMonth--;
      if (calMonth < 1) { calMonth = 12; calYear--; }
    } else if (hs.action.equals("nextMonth")) {
      calMonth++;
      if (calMonth > 12) { calMonth = 1; calYear++; }
    } else if (hs.action.equals("day")) {
      gallerySelectedDay = hs.key;
      galleryDayPage = 0;
    } else if (hs.action.equals("play")) {
      GalleryEntry re = galleryCache.get(hs.key);
      if (re != null) openReplay(re.csv, re.label + "（" + formatDuration(re.durationMs) + "）");
    } else if (hs.action.equals("view")) {
      openViewer(galleryCache.get(hs.key));
    } else if (hs.action.equals("memo")) {
      GalleryEntry me = galleryCache.get(hs.key);
      if (me != null) {
        if (me.diaryText.length() == 0 && me.tags.length == 0) openDiaryEditor(me.csv, me.label + " のメモ");
        else galleryMemoPopup = me;
      }
    } else if (hs.action.equals("prevPage")) {
      galleryDayPage--;
    } else if (hs.action.equals("nextPage")) {
      galleryDayPage++;
    }
    return true;
  }
  return false;
}

String formatDuration(long ms) {
  long sec = Math.max(0L, ms / 1000);
  return nf((int)(sec / 60), 2) + ":" + nf((int)(sec % 60), 2);
}

// ===== 删除确认窗口（日语；画廊和 Data Management 共用）=====
void drawDeleteDialog(ArrayList<GalleryHot> hots, GalleryEntry e) {
  hots.clear();   // 只保留窗口内的按钮
  PImage thumb = e.img;
  GalleryEntry ge = galleryCache.get(e.name);
  if (thumb == null && ge != null) {
    thumb = ge.img;
    galleryRequest(ge);
  }

  noStroke();
  fill(0, 170);
  rect(0, 0, width, height);

  float w = 440, h = 330;
  float x = (width - w) / 2, y = (height - h) / 2;
  fill(22);
  stroke(70);
  strokeWeight(1);
  rect(x, y, w, h, 10);

  // 缩图
  float iw = 220, ih = iw * LP_WORLD_H / LP_WORLD_W;   // 光绘的比例（虚拟画布）
  float ix = x + (w - iw) / 2, iy = y + 24;
  if (thumb != null) image(thumb, ix, iy, iw, ih);
  else { noStroke(); fill(35); rect(ix, iy, iw, ih); }

  noStroke();
  textAlign(CENTER, CENTER);
  fill(235);
  textSize(17);
  text("この記録を削除しますか？", x + w / 2, iy + ih + 28);
  fill(170);
  textSize(13);
  text(e.label + "（" + formatDuration(e.durationMs) + "）", x + w / 2, iy + ih + 54);
  fill(200, 140, 140);
  textSize(11);
  text("光絵・元データ（CSV）・メモがまとめて削除されます。この操作は取り消せません。", x + w / 2, iy + ih + 78);

  // 按钮
  float bw = 150, bh = 38, by = y + h - bh - 20;
  float cx1 = x + w / 2 - bw - 10, cx2 = x + w / 2 + 10;
  boolean hCancel = mouseX >= cx1 && mouseX <= cx1 + bw && mouseY >= by && mouseY <= by + bh;
  boolean hDel = mouseX >= cx2 && mouseX <= cx2 + bw && mouseY >= by && mouseY <= by + bh;

  fill(hCancel ? 70 : 50);
  rect(cx1, by, bw, bh, 6);
  fill(220);
  textSize(14);
  text("キャンセル", cx1 + bw / 2, by + bh / 2);

  fill(hDel ? color(215, 75, 75) : color(170, 55, 55));
  rect(cx2, by, bw, bh, 6);
  fill(255);
  text("削除する", cx2 + bw / 2, by + bh / 2);

  hots.add(new GalleryHot(cx1, by, bw, bh, "cancelDelete", null));
  hots.add(new GalleryHot(cx2, by, bw, bh, "confirmDelete", null));
  textAlign(LEFT);
}

// 删除一次记录：CSV + JSON + 作品 + 缩略图（Artwork.pde 的 deleteSession，与 Data Management 共用）
void deleteGalleryEntry(GalleryEntry e) {
  if (e == null) return;
  e.deleted = true;
  deleteSession(e.csv);

  String day = gallerySelectedDay;
  refreshGalleryList();
  // 当天还有其他记录则停留在当天；当天已空则 refreshGalleryList 会选中最近有记录的一天
  if (day != null && galleryByDay.containsKey(day)) gallerySelectedDay = day;
}

// 缩略图下方的小按钮：view = ⤢（看大图），play = ▶（再生）
void drawThumbButton(float x, float y, float s, String action, String key) {
  boolean hover = mouseX >= x && mouseX <= x + s && mouseY >= y && mouseY <= y + s && galleryPendingDelete == null && galleryMemoPopup == null;
  noStroke();
  fill(hover ? 70 : 36);
  rect(x, y, s, s, 5);
  float cx = x + s / 2, cy = y + s / 2;
  if (action.equals("play")) {
    fill(hover ? 240 : 190);
    triangle(cx - 4, cy - 6, cx - 4, cy + 6, cx + 6, cy);
  } else {
    stroke(hover ? 240 : 190);
    strokeWeight(1.4f);
    noFill();
    float d = 5;
    line(cx - d, cy - d, cx - d + 4, cy - d); line(cx - d, cy - d, cx - d, cy - d + 4);
    line(cx + d, cy + d, cx + d - 4, cy + d); line(cx + d, cy + d, cx + d, cy + d - 4);
    line(cx - d, cy - d, cx + d, cy + d);
    noStroke();
  }
  if (galleryPendingDelete == null && galleryMemoPopup == null) galleryHots.add(new GalleryHot(x, y, s, s, action, key));
}

// 标签一行（放不下的显示 +N）
void drawTagChipsLine(String[] tags, float x, float y, float w) {
  textSize(11);
  textAlign(LEFT, CENTER);
  float cx = x, h = 20;
  for (int i = 0; i < tags.length; i++) {
    float tw = textWidth(tags[i]) + 14;
    if (cx + tw > x + w - 30 && i < tags.length - 1 || cx + tw > x + w) {
      fill(140);
      text("+" + (tags.length - i), cx + 2, y + h / 2);
      break;
    }
    noStroke();
    fill(37, 42, 54);
    rect(cx, y, tw, h, h / 2);
    fill(175, 185, 205);
    text(tags[i], cx + 7, y + h / 2);
    cx += tw + 5;
  }
}

// メモ全文的浮动框（浮在画廊上层，不推开下面的画）
void drawMemoPopup(GalleryEntry e) {
  galleryHots.clear();
  noStroke();
  fill(0, 120);
  rect(0, 0, width, height);
  float w = min(420, width - 80);
  textSize(13);
  ArrayList<String> lines = wrapChars(e.diaryText, w - 32);
  float tagH = 0;
  if (e.tags.length > 0) tagH = 34;
  float h = 70 + tagH + lines.size() * 20 + 50;
  float x = (width - w) / 2, y = (height - h) / 2;
  fill(24);
  stroke(70);
  strokeWeight(1);
  rect(x, y, w, h, 10);
  noStroke();
  fill(230);
  textSize(15);
  textAlign(LEFT, TOP);
  text(e.label + " のメモ", x + 16, y + 16);
  float yy = y + 48;
  if (e.tags.length > 0) {
    drawTagChips(e.tags, x + 16, yy, w - 32, 12);
    yy += tagH;
  }
  fill(210);
  textSize(13);
  textAlign(LEFT, TOP);
  for (String l : lines) { text(l, x + 16, yy); yy += 20; }
  float bw = 110, bh = 30, bx = x + w - bw - 16, by = y + h - bh - 14;
  boolean hover = mouseX >= bx && mouseX <= bx + bw && mouseY >= by && mouseY <= by + bh;
  fill(hover ? 70 : 48);
  rect(bx, by, bw, bh, 6);
  fill(230);
  textAlign(CENTER, CENTER);
  text("編集", bx + bw / 2, by + bh / 2);
  galleryHots.add(new GalleryHot(bx, by, bw, bh, "memoEdit", null));
  textAlign(LEFT);
}
