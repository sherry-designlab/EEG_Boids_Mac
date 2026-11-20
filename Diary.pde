// ===== 心情日记（文字 + 标签）与冥想中的标记 =====
// 保存在会话 JSON（sessions/<会话名>.json）的 "diary" 与 "markers" 中，
// 因此每个会话仍然只有 CSV・JSON・作品 三个文件，删除时一起删除。
//
// 输入窗口使用 Java 标准组件（Swing）：Processing 的画面无法正常使用日语・中文输入法。
// 标签：初始只有 4 个通用标签（脑电研究中常被提到、会影响 α/β 波的日常因素），全部可以删除、可以自己添加；
// 按使用次数排序，常用的排在前面。标签列表保存在数据文件夹的 tags.json。

final int DIARY_MAX_CHARS = 200;
String[] DEFAULT_TAGS = { "睡眠不足", "疲れ", "カフェイン", "運動後" };

// 编辑完成后由主线程处理（刷新画廊的显示）
volatile String diarySavedName = null;
volatile javax.swing.JDialog diaryDialog = null;   // 正在打开的メモ窗口（再次点击时把它提到最前面）

// ---- 标签列表 ----
class TagInfo {
  String name;
  int uses;
  TagInfo(String n, int u) { name = n; uses = u; }
}

ArrayList<TagInfo> loadTags() {
  ArrayList<TagInfo> list = new ArrayList<TagInfo>();
  File f = dataRootFile("tags.json");
  if (f.exists()) {
    try {
      JSONArray arr = loadJSONObject(f.getAbsolutePath()).getJSONArray("tags");
      for (int i = 0; i < arr.size(); i++) {
        JSONObject t = arr.getJSONObject(i);
        list.add(new TagInfo(t.getString("name"), t.getInt("uses", 0)));
      }
      return list;
    } catch (Exception e) {
      println("tags.json を読み込めませんでした: " + e.getMessage());
    }
  }
  for (String n : DEFAULT_TAGS) list.add(new TagInfo(n, 0));
  return list;
}

void saveTags(ArrayList<TagInfo> list) {
  JSONArray arr = new JSONArray();
  for (TagInfo t : list) {
    JSONObject o = new JSONObject();
    o.setString("name", t.name);
    o.setInt("uses", t.uses);
    arr.append(o);
  }
  JSONObject root = new JSONObject();
  root.setJSONArray("tags", arr);
  saveJSONObject(root, dataRootFile("tags.json").getAbsolutePath());
}

// ---- 读取某个会话的日记 ----
String diaryTextOf(JSONObject meta) {
  if (meta == null || !meta.hasKey("diary")) return "";
  return meta.getJSONObject("diary").getString("text", "");
}

String[] diaryTagsOf(JSONObject meta) {
  if (meta == null || !meta.hasKey("diary")) return new String[0];
  JSONObject d = meta.getJSONObject("diary");
  if (!d.hasKey("tags")) return new String[0];
  return d.getJSONArray("tags").getStringArray();
}

// ---- 编辑窗口（Swing）----
void openDiaryEditor(File csv, String title) {
  if (csv == null || !csv.exists()) return;
  final File f = csv;
  final String ttl = title;
  javax.swing.SwingUtilities.invokeLater(() -> {
    // 已经打开着：关掉旧的，打开这一次的（以前这里直接忽略，窗口被红色按钮关掉后就再也打不开）
    if (diaryDialog != null) {
      diaryDialog.dispose();
      diaryDialog = null;
    }
    try {
      buildDiaryDialog(f, ttl);
    } catch (Exception ex) {
      ex.printStackTrace();
      showToast("メモを開けませんでした：" + ex.getMessage());
    }
  });
}

void buildDiaryDialog(final File csv, String title) {
  final JSONObject meta = sessionMetaLoad(csv);
  final ArrayList<TagInfo> tags = loadTags();
  tags.sort((x, y) -> y.uses - x.uses);
  final String[] oldTags = diaryTagsOf(meta);
  final java.util.LinkedHashSet<String> selected = new java.util.LinkedHashSet<String>(java.util.Arrays.asList(oldTags));
  java.awt.Font font = new java.awt.Font("Hiragino Sans", java.awt.Font.PLAIN, 14);
  java.awt.Font small = font.deriveFont(12f);

  final javax.swing.JDialog dlg = new javax.swing.JDialog((java.awt.Frame)null, "メモ", false);
  dlg.setAlwaysOnTop(true);
  dlg.setDefaultCloseOperation(javax.swing.WindowConstants.DISPOSE_ON_CLOSE);
  javax.swing.JPanel root = new javax.swing.JPanel();
  root.setLayout(new javax.swing.BoxLayout(root, javax.swing.BoxLayout.Y_AXIS));
  root.setBorder(javax.swing.BorderFactory.createEmptyBorder(14, 16, 14, 16));

  javax.swing.JLabel head = new javax.swing.JLabel(title);
  head.setFont(font.deriveFont(java.awt.Font.BOLD, 15f));
  head.setAlignmentX(0);
  root.add(head);
  root.add(javax.swing.Box.createVerticalStrut(10));

  // 文字（最多 200 字）
  final javax.swing.JTextArea area = new javax.swing.JTextArea(6, 32);
  area.setFont(font);
  area.setLineWrap(true);
  area.setWrapStyleWord(false);
  ((javax.swing.text.AbstractDocument)area.getDocument()).setDocumentFilter(new javax.swing.text.DocumentFilter() {
    public void insertString(FilterBypass fb, int off, String s, javax.swing.text.AttributeSet a) throws javax.swing.text.BadLocationException {
      replace(fb, off, 0, s, a);
    }
    public void replace(FilterBypass fb, int off, int len, String s, javax.swing.text.AttributeSet a) throws javax.swing.text.BadLocationException {
      if (s == null) s = "";
      int room = DIARY_MAX_CHARS - (fb.getDocument().getLength() - len);
      if (room <= 0) return;
      if (s.length() > room) s = s.substring(0, room);
      super.replace(fb, off, len, s, a);
    }
  });
  area.setText(diaryTextOf(meta));
  javax.swing.JScrollPane sp = new javax.swing.JScrollPane(area);
  sp.setAlignmentX(0);
  root.add(sp);
  final javax.swing.JLabel count = new javax.swing.JLabel();
  count.setFont(small);
  count.setAlignmentX(0);
  Runnable upd = () -> count.setText(area.getText().length() + " / " + DIARY_MAX_CHARS + " 字");
  upd.run();
  area.getDocument().addDocumentListener(new javax.swing.event.DocumentListener() {
    public void insertUpdate(javax.swing.event.DocumentEvent e) { upd.run(); }
    public void removeUpdate(javax.swing.event.DocumentEvent e) { upd.run(); }
    public void changedUpdate(javax.swing.event.DocumentEvent e) { upd.run(); }
  });
  root.add(count);
  root.add(javax.swing.Box.createVerticalStrut(12));

  // 标签
  javax.swing.JLabel tl = new javax.swing.JLabel("タグ（クリックで選択・右クリックで一覧から削除）");
  tl.setFont(small);
  tl.setAlignmentX(0);
  root.add(tl);
  final TagFlowPanel tagPanel = new TagFlowPanel();
  final Runnable[] rebuild = new Runnable[1];
  rebuild[0] = () -> {
    tagPanel.removeAll();
    for (final TagInfo t : tags) {
      final javax.swing.JToggleButton b = new javax.swing.JToggleButton(t.name, selected.contains(t.name));
      b.setFont(small);
      b.addActionListener(e -> {
        if (b.isSelected()) selected.add(t.name); else selected.remove(t.name);
      });
      b.addMouseListener(new java.awt.event.MouseAdapter() {
        public void mousePressed(java.awt.event.MouseEvent e) { popup(e); }
        public void mouseReleased(java.awt.event.MouseEvent e) { popup(e); }
        void popup(java.awt.event.MouseEvent e) {
          if (!e.isPopupTrigger()) return;
          javax.swing.JPopupMenu m = new javax.swing.JPopupMenu();
          javax.swing.JMenuItem del = new javax.swing.JMenuItem("「" + t.name + "」を一覧から削除");
          del.addActionListener(ev -> {
            tags.remove(t);
            selected.remove(t.name);
            rebuild[0].run();
          });
          m.add(del);
          m.show(b, e.getX(), e.getY());
        }
      });
      tagPanel.add(b);
    }
    tagPanel.revalidate();
    tagPanel.repaint();
  };
  rebuild[0].run();
  // 标签多时可以上下滚动（数量没有上限）
  javax.swing.JScrollPane tagScroll = new javax.swing.JScrollPane(tagPanel,
    javax.swing.ScrollPaneConstants.VERTICAL_SCROLLBAR_AS_NEEDED,
    javax.swing.ScrollPaneConstants.HORIZONTAL_SCROLLBAR_NEVER);
  tagScroll.setBorder(javax.swing.BorderFactory.createEmptyBorder());
  tagScroll.getVerticalScrollBar().setUnitIncrement(12);
  tagScroll.setPreferredSize(new java.awt.Dimension(400, 120));
  tagScroll.setAlignmentX(0);
  root.add(tagScroll);

  javax.swing.JPanel addRow = new javax.swing.JPanel(new java.awt.FlowLayout(java.awt.FlowLayout.LEFT, 0, 0));
  addRow.setAlignmentX(0);
  final javax.swing.JTextField newTag = new javax.swing.JTextField(14);
  newTag.setFont(small);
  javax.swing.JButton addBtn = new javax.swing.JButton("タグを追加");
  addBtn.setFont(small);
  java.awt.event.ActionListener addAct = e -> {
    String n = newTag.getText().trim();
    if (n.length() == 0) return;
    if (n.length() > 12) n = n.substring(0, 12);
    boolean exists = false;
    for (TagInfo t : tags) if (t.name.equals(n)) exists = true;
    if (!exists) tags.add(new TagInfo(n, 0));
    selected.add(n);
    newTag.setText("");
    rebuild[0].run();
    // 新标签加在最后：滚动到底部让它可见
    javax.swing.SwingUtilities.invokeLater(() -> tagPanel.scrollRectToVisible(new java.awt.Rectangle(0, tagPanel.getPreferredSize().height - 1, 1, 1)));
  };
  addBtn.addActionListener(addAct);
  newTag.addActionListener(addAct);
  addRow.add(newTag);
  addRow.add(javax.swing.Box.createHorizontalStrut(6));
  addRow.add(addBtn);
  root.add(addRow);

  // 冥想中的标记（M キー）：名称在这里补写
  final JSONArray markers = (meta != null && meta.hasKey("markers")) ? meta.getJSONArray("markers") : new JSONArray();
  final ArrayList<javax.swing.JTextField> markerFields = new ArrayList<javax.swing.JTextField>();
  if (markers.size() > 0) {
    root.add(javax.swing.Box.createVerticalStrut(12));
    javax.swing.JLabel ml = new javax.swing.JLabel("瞑想中のマーク（M キー）");
    ml.setFont(small);
    ml.setAlignmentX(0);
    root.add(ml);
    for (int i = 0; i < markers.size(); i++) {
      JSONObject mk = markers.getJSONObject(i);
      javax.swing.JPanel row = new javax.swing.JPanel(new java.awt.FlowLayout(java.awt.FlowLayout.LEFT, 0, 2));
      row.setAlignmentX(0);
      javax.swing.JLabel tlab = new javax.swing.JLabel(formatDuration(mk.getLong("ms", 0)) + "  ");
      tlab.setFont(small);
      javax.swing.JTextField tf = new javax.swing.JTextField(mk.getString("label", ""), 22);
      tf.setFont(small);
      markerFields.add(tf);
      row.add(tlab);
      row.add(tf);
      root.add(row);
    }
  }

  // 保存 / キャンセル
  root.add(javax.swing.Box.createVerticalStrut(14));
  javax.swing.JPanel btns = new javax.swing.JPanel(new java.awt.FlowLayout(java.awt.FlowLayout.RIGHT, 8, 0));
  btns.setAlignmentX(0);
  javax.swing.JButton cancel = new javax.swing.JButton("キャンセル");
  javax.swing.JButton save = new javax.swing.JButton("保存");
  cancel.setFont(font);
  save.setFont(font);
  btns.add(cancel);
  btns.add(save);
  root.add(btns);

  cancel.addActionListener(e -> dlg.dispose());
  save.addActionListener(e -> {
    final String text = area.getText();
    final java.util.ArrayList<String> sel = new java.util.ArrayList<String>(selected);
    // 使用次数：新加上的标签 +1，去掉的 -1
    java.util.HashSet<String> before = new java.util.HashSet<String>(java.util.Arrays.asList(oldTags));
    for (TagInfo t : tags) {
      if (sel.contains(t.name) && !before.contains(t.name)) t.uses++;
      if (!sel.contains(t.name) && before.contains(t.name)) t.uses = max(0, t.uses - 1);
    }
    saveTags(tags);
    sessionMetaUpdate(csv, o -> {
      JSONObject d = new JSONObject();
      d.setString("text", text);
      JSONArray ta = new JSONArray();
      for (String s : sel) ta.append(s);
      d.setJSONArray("tags", ta);
      d.setString("updated", new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date()));
      o.setJSONObject("diary", d);
      if (o.hasKey("markers")) {
        JSONArray mk = o.getJSONArray("markers");
        for (int i = 0; i < mk.size() && i < markerFields.size(); i++) {
          mk.getJSONObject(i).setString("label", markerFields.get(i).getText().trim());
        }
      }
    });
    diarySavedName = csv.getName();
    dlg.dispose();
  });
  dlg.addWindowListener(new java.awt.event.WindowAdapter() {
    public void windowClosed(java.awt.event.WindowEvent e) { if (diaryDialog == dlg) diaryDialog = null; }
  });

  dlg.setContentPane(root);
  dlg.pack();
  dlg.setLocationRelativeTo(null);
  diaryDialog = dlg;
  dlg.setVisible(true);
  dlg.toFront();
  area.requestFocusInWindow();
}

// 标签面板：按窗口宽度自动换行，高度随标签数量增加（放在可滚动区域里）
class TagFlowPanel extends javax.swing.JPanel implements javax.swing.Scrollable {
  int hgap = 6, vgap = 6;
  TagFlowPanel() {
    super(new java.awt.FlowLayout(java.awt.FlowLayout.LEFT, 6, 6));
  }
  public java.awt.Dimension getPreferredSize() {
    int w = getParent() != null && getParent().getWidth() > 0 ? getParent().getWidth() : 400;
    int x = hgap, y = vgap, rowH = 0;
    for (java.awt.Component c : getComponents()) {
      java.awt.Dimension d = c.getPreferredSize();
      if (x + d.width + hgap > w && x > hgap) {
        x = hgap;
        y += rowH + vgap;
        rowH = 0;
      }
      x += d.width + hgap;
      rowH = Math.max(rowH, d.height);
    }
    return new java.awt.Dimension(w, y + rowH + vgap);
  }
  public java.awt.Dimension getPreferredScrollableViewportSize() { return getPreferredSize(); }
  public int getScrollableUnitIncrement(java.awt.Rectangle r, int o, int d) { return 12; }
  public int getScrollableBlockIncrement(java.awt.Rectangle r, int o, int d) { return 60; }
  public boolean getScrollableTracksViewportWidth() { return true; }
  public boolean getScrollableTracksViewportHeight() { return false; }
}

// 主线程每帧调用：保存后刷新画廊中该会话的显示
void checkDiarySaved() {
  if (diarySavedName == null) return;
  String n = diarySavedName;
  diarySavedName = null;
  GalleryEntry e = galleryCache.get(n);
  if (e != null) e.loadDiary();
  showToast("メモを保存しました");
}

// ===== 冥想中的标记（M キー）=====
JSONArray recMarkers = null;
int markerFlashMs = -100000;

void addMarker() {
  if (!isRecording || recMarkers == null) return;
  JSONObject m = new JSONObject();
  m.setInt("step", liveSim.step);
  m.setLong("ms", System.currentTimeMillis() - sessionStartTime);
  m.setString("label", "");
  recMarkers.append(m);
  markerFlashMs = millis();
  openMarkerNote(m);
}

// ===== 标记的简短备注（M 键之后弹出；最多 MARKER_NOTE_MAX 字）=====
// 标记的时刻在按下 M 的瞬间就已经记下；这个小窗口只是补上文字。
// Enter = 保存，Esc 或关闭 = 不写（标记本身保留，结束后也可以在メモ窗口中补写）。
// 冥想（录制）在窗口打开期间照常继续。
final int MARKER_NOTE_MAX = 20;
volatile javax.swing.JDialog markerDialog = null;

void openMarkerNote(final JSONObject marker) {
  final String timeLabel = formatDuration(marker.getLong("ms", 0));
  final File csvAtMark = sessionFile(currentSessionFile);
  final int stepAtMark = marker.getInt("step", 0);
  javax.swing.SwingUtilities.invokeLater(() -> {
    if (markerDialog != null) markerDialog.dispose();
    java.awt.Font font = new java.awt.Font("Hiragino Sans", java.awt.Font.PLAIN, 15);
    final javax.swing.JDialog d = new javax.swing.JDialog((java.awt.Frame)null, "マーク " + timeLabel, false);
    d.setAlwaysOnTop(true);
    d.setDefaultCloseOperation(javax.swing.WindowConstants.DISPOSE_ON_CLOSE);
    javax.swing.JPanel p = new javax.swing.JPanel(new java.awt.BorderLayout(0, 6));
    p.setBorder(javax.swing.BorderFactory.createEmptyBorder(12, 14, 12, 14));
    javax.swing.JLabel lb = new javax.swing.JLabel("一言メモ（" + MARKER_NOTE_MAX + " 字まで・Enter で保存、Esc で閉じる）");
    lb.setFont(font.deriveFont(12f));
    final javax.swing.JTextField tf = new javax.swing.JTextField(18);
    tf.setFont(font);
    ((javax.swing.text.AbstractDocument)tf.getDocument()).setDocumentFilter(new javax.swing.text.DocumentFilter() {
      public void insertString(FilterBypass fb, int off, String s, javax.swing.text.AttributeSet a) throws javax.swing.text.BadLocationException {
        replace(fb, off, 0, s, a);
      }
      public void replace(FilterBypass fb, int off, int len, String s, javax.swing.text.AttributeSet a) throws javax.swing.text.BadLocationException {
        if (s == null) s = "";
        s = s.replace("\n", " ");
        int room = MARKER_NOTE_MAX - (fb.getDocument().getLength() - len);
        if (room <= 0) return;
        if (s.length() > room) s = s.substring(0, room);
        super.replace(fb, off, len, s, a);
      }
    });
    tf.addActionListener(e -> {
      final String t = tf.getText().trim();
      synchronized (marker) { marker.setString("label", t); }
      // 输入前冥想已经结束（会话 JSON 已保存）：直接写进 JSON
      JSONObject meta = sessionMetaLoad(csvAtMark);
      if (meta != null && meta.hasKey("markers")) {
        sessionMetaUpdate(csvAtMark, o -> {
          JSONArray mk = o.getJSONArray("markers");
          for (int i = 0; i < mk.size(); i++) {
            if (mk.getJSONObject(i).getInt("step", -1) == stepAtMark) mk.getJSONObject(i).setString("label", t);
          }
        });
      }
      d.dispose();
    });
    tf.getInputMap().put(javax.swing.KeyStroke.getKeyStroke("ESCAPE"), "close");
    tf.getActionMap().put("close", new javax.swing.AbstractAction() {
      public void actionPerformed(java.awt.event.ActionEvent e) { d.dispose(); }
    });
    d.addWindowListener(new java.awt.event.WindowAdapter() {
      public void windowClosed(java.awt.event.WindowEvent e) { if (markerDialog == d) markerDialog = null; }
    });
    p.add(lb, java.awt.BorderLayout.NORTH);
    p.add(tf, java.awt.BorderLayout.CENTER);
    d.setContentPane(p);
    d.pack();
    d.setLocationRelativeTo(null);
    markerDialog = d;
    d.setVisible(true);
    d.toFront();
    tf.requestFocusInWindow();
  });
}

// 标记时的轻微反馈：录制按钮周围闪一下（不打扰冥想）
void drawMarkerFlash() {
  float t = (millis() - markerFlashMs) / 900.0f;
  if (t < 0 || t > 1) return;
  noFill();
  stroke(255, 255, 255, 120 * (1 - t));
  strokeWeight(1.5f);
  float r = REC_BTN_R * (1.4f + t * 1.6f);
  ellipse(recBtnX, recBtnY, r * 2, r * 2);
  noStroke();
  fill(220, 220, 220, 160 * (1 - t));
  textSize(11);
  textAlign(CENTER, CENTER);
  text("マーク " + (recMarkers != null ? recMarkers.size() : 0), recBtnX, recBtnY - REC_BTN_R - 26);
  textAlign(LEFT);
}

// 按字换行（中日文没有空格，Processing 的 text() 无法正确换行）
ArrayList<String> wrapChars(String s, float w) {
  ArrayList<String> out = new ArrayList<String>();
  for (String para : s.split("\n", -1)) {
    StringBuilder line = new StringBuilder();
    for (int i = 0; i < para.length(); i++) {
      char c = para.charAt(i);
      if (line.length() > 0 && textWidth(line.toString() + c) > w) {
        out.add(line.toString());
        line.setLength(0);
      }
      line.append(c);
    }
    out.add(line.toString());
  }
  return out;
}

// 一行显示，超出时以 … 截断
String ellipsize(String s, float w) {
  s = s.replace('\n', ' ');
  if (textWidth(s) <= w) return s;
  String e = "…";
  int n = s.length();
  while (n > 0 && textWidth(s.substring(0, n) + e) > w) n--;
  return s.substring(0, n) + e;
}
