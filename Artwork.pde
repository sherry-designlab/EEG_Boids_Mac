// ===== 作品存档 =====
// 每个会话只有一张作品：artworks/<会话名>.png（3840×2400）。
// 第一次需要时生成一次，之后画廊、回放结尾、看图界面都只读取这张图，不再重新计算。
// 缩略图（cache/<会话名>_960.png）由作品直接缩小得到，与作品是同一张图。
// 作品参数记录在会话 JSON（sessions/<会话名>.json）的 "render" 部分。
//
// 光绘风格编号：有意改变光绘风格时把它加 1。启动后，风格编号不同的作品会被移到
// artworks/_old_style<旧编号>/（保留给你挑选），然后全部用新风格重新生成。
//   1 = 11/14 版（时间压缩 2000 步的模拟）
//   2 = 11/16 版（用实时鱼群的真实轨迹；线条过强，已放弃）
//   3 = 11/16 恢复 11/14 版的算法（与 1 相同的画面，4K 存档）
final int LP_STYLE_VERSION = 3;

final int THUMB_W = 960;   // 缩略图宽（= 作品 3840 的 1/4）

File artworkFile(String csvName) { return new File(artworksDir(), stemOf(csvName) + ".png"); }
File thumbFile(String csvName)   { return new File(cacheDir(), stemOf(csvName) + "_" + THUMB_W + ".png"); }

// ---- 会话 JSON 的读写（多个线程可能同时写：统一加锁）----
final Object metaLock = new Object();

void sessionMetaSave(File csv, JSONObject o) {
  synchronized (metaLock) {
    try {
      PrintWriter w = createWriter(sessionMetaFile(csv).getAbsolutePath());
      w.println(o.format(2));
      w.close();
    } catch (Exception e) {
      println("JSON 保存失敗: " + e.getMessage());
    }
  }
}

// 读取 → 修改 → 写回
interface MetaEdit { void apply(JSONObject o); }
void sessionMetaUpdate(File csv, MetaEdit edit) {
  synchronized (metaLock) {
    JSONObject o = sessionMetaLoad(csv);
    if (o == null) o = new JSONObject();
    edit.apply(o);
    sessionMetaSave(csv, o);
  }
}

int artworkStyleOf(File csv) {
  JSONObject m = sessionMetaLoad(csv);
  if (m == null || !m.hasKey("render")) return -1;
  return m.getJSONObject("render").getInt("style", -1);
}

boolean artworkUpToDate(File csv) {
  return artworkFile(csv.getName()).exists() && artworkStyleOf(csv) == LP_STYLE_VERSION;
}

// 确保作品存在（后台线程调用）；返回 false = 数据不足无法生成
// 同一时刻只生成一张（4K 生成需要较多内存）
final Object artworkLock = new Object();
boolean ensureArtwork(File csv) {
  synchronized (artworkLock) {
    if (!csv.exists()) return false;
    if (artworkUpToDate(csv)) return true;
    File png = artworkFile(csv.getName());
    if (png.exists()) {
      // 旧风格的作品：保留在 _old_style<N>/ 中
      int old = artworkStyleOf(csv);
      File keep = new File(artworksDir(), "_old_style" + (old < 0 ? "?" : str(old)));
      keep.mkdirs();
      moveFile(png, new File(keep, png.getName()));
      thumbFile(csv.getName()).delete();
    }
    ArrayList<float[]> data = lpLoadSession(csv);
    if (data.size() < 2) return false;
    long t0 = System.currentTimeMillis();
    final long seed = lpSeedFor(csv.getName());
    PImage img = lpRender(data, seed, LP_EXPORT_W);
    if (!csv.exists()) return false;   // 生成期间被删除
    img.save(png.getAbsolutePath());
    final String md5 = fileMd5(csv);
    sessionMetaUpdate(csv, o -> {
      JSONObject r = new JSONObject();
      r.setInt("style", LP_STYLE_VERSION);
      r.setString("seed", Long.toString(seed));
      r.setString("pop_scale", Float.toString(LP_POP_SCALE));
      r.setInt("step_budget", LP_STEP_BUDGET);
      r.setInt("warmup", LP_WARMUP);
      r.setInt("world_w", (int)LP_WORLD_W);
      r.setInt("world_h", (int)LP_WORLD_H);
      r.setInt("width", LP_EXPORT_W);
      r.setInt("height", lpHeightFor(LP_EXPORT_W));
      r.setString("csv_md5", md5);
      r.setString("created", new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date()));
      o.setJSONObject("render", r);
    });
    println("作品を生成しました: " + png.getName() + "（" + (System.currentTimeMillis() - t0) + " ms）");
    return true;
  }
}

// 缩略图：有就读取；没有就从作品缩小（作品也没有时先生成作品）
PImage loadThumb(File csv) {
  File th = thumbFile(csv.getName());
  File png = artworkFile(csv.getName());
  if (th.exists() && png.exists() && th.lastModified() >= png.lastModified() && artworkStyleOf(csv) == LP_STYLE_VERSION) {
    PImage t = loadImage(th.getAbsolutePath());
    if (t != null && t.width > 0) return t;
  }
  if (!ensureArtwork(csv)) return null;
  PImage big = loadImage(png.getAbsolutePath());
  if (big == null || big.width <= 0) return null;
  PImage small = downscale(big, THUMB_W);
  small.save(th.getAbsolutePath());
  return small;
}

// 读取完整作品（看图界面、回放结尾用）
PImage loadArtwork(File csv) {
  if (!ensureArtwork(csv)) return null;
  return loadImage(artworkFile(csv.getName()).getAbsolutePath());
}

// 按整数倍做区域平均缩小（3840 → 960 = 4×4 平均），结果固定
PImage downscale(PImage src, int outW) {
  int f = max(1, src.width / outW);
  int W = src.width / f, H = src.height / f;
  src.loadPixels();
  PImage out = createImage(W, H, RGB);
  out.loadPixels();
  int n = f * f;
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      int r = 0, g = 0, b = 0;
      for (int yy = 0; yy < f; yy++) {
        int row = (y * f + yy) * src.width + x * f;
        for (int xx = 0; xx < f; xx++) {
          int c = src.pixels[row + xx];
          r += (c >> 16) & 255; g += (c >> 8) & 255; b += c & 255;
        }
      }
      out.pixels[y * W + x] = 0xFF000000 | ((r / n) << 16) | ((g / n) << 8) | (b / n);
    }
  }
  out.updatePixels();
  return out;
}

String fileMd5(File f) {
  try {
    java.security.MessageDigest md = java.security.MessageDigest.getInstance("MD5");
    byte[] d = md.digest(java.nio.file.Files.readAllBytes(f.toPath()));
    StringBuilder sb = new StringBuilder();
    for (byte b : d) sb.append(String.format("%02x", b));
    return sb.toString();
  } catch (Exception e) {
    return "";
  }
}

// ===== 删除一次会话：CSV + JSON + 作品 + 缩略图（画廊和 Data Management 共用）=====
boolean deleteSession(File csv) {
  String name = csv.getName();
  boolean ok = true;
  synchronized (artworkLock) {
    File[] fs = { csv, sessionMetaFile(csv), artworkFile(name), thumbFile(name) };
    for (File f : fs) if (f.exists() && !f.delete()) ok = false;
  }
  galleryCache.remove(name);
  println((ok ? "✓ 削除しました: " : "⚠ 一部削除できませんでした: ") + name);
  return ok;
}

// ===== 光绘的自检（只在控制台输出，不显示给用户）=====
// 用一段固定的测试数据画一张小图，与记录的结果比较。
// 没有改变风格编号却出现差异 → 某处修改无意中影响了光绘。
final String LP_SELFTEST_EXPECTED = "aeb4525685e44a3";   // 风格 3（= 11/14 版算法）的结果

void runLightPaintingSelfTest() {
  Thread t = new Thread(() -> {
    String h = lpSelfTestHash();
    if (LP_SELFTEST_EXPECTED.length() == 0) println("[光絵セルフテスト] hash = " + h);
    else if (h.equals(LP_SELFTEST_EXPECTED)) println("[光絵セルフテスト] OK");
    else println("[光絵セルフテスト] ⚠ 結果が変わりました（スタイル番号を変えずに光絵が変化しています）: " + h);
  });
  t.setDaemon(true);
  t.start();
}

String lpSelfTestHash() {
  ArrayList<float[]> data = new ArrayList<float[]>();
  for (int i = 0; i < 40; i++) data.add(new float[] { ((i * 37) % 21 - 10) / 10.0f, ((i * 53) % 21 - 10) / 10.0f });
  PImage img = lpRender(data, 20261116L, 240);
  img.loadPixels();
  long h = 1125899906842597L;
  for (int p : img.pixels) h = 31 * h + p;
  return Long.toHexString(h);
}
