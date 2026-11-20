// ===== 数据文件夹（与程序分开存放）=====
// 所有个人数据放在：書類（文稿）/EEG_Boids_Mac_Data/
//   sessions/   每次会话的 CSV + 同名 JSON（鱼群起始状态、作品参数、日记）
//   artworks/   每次会话唯一的作品（3840×2400 PNG），生成一次后只读取、永不重新计算
//   cache/      缩略图（由作品缩小得到，随时可删，删除后自动重新缩小）
//   calibration.json   校准基准
//   swarm_state.json   实时鱼群的状态（下次启动时从这里继续，"水族馆"）
//   tags.json          日记标签
// 程序文件夹里只放代码，因此更新程序、放进 GitHub 都不会碰到数据。

String DATA_ROOT_OVERRIDE = null;   // 测试用

File dataRoot() {
  if (DATA_ROOT_OVERRIDE != null) return new File(DATA_ROOT_OVERRIDE);
  return new File(System.getProperty("user.home"), "Documents/EEG_Boids_Mac_Data");
}
File sessionsDir() { return new File(dataRoot(), "sessions"); }
File artworksDir() { return new File(dataRoot(), "artworks"); }
File cacheDir()    { return new File(dataRoot(), "cache"); }
File dataRootFile(String name) { return new File(dataRoot(), name); }
final String SWARM_STATE_FILE = "swarm_state.json";   // 进化版使用 swarm_state_evo.json
File sessionFile(String csvName) { return new File(sessionsDir(), csvName); }

void initDataDirs() {
  sessionsDir().mkdirs();
  artworksDir().mkdirs();
  cacheDir().mkdirs();
  migrateFromSketchFolder();
}

// 第一次启动新版本时：把程序文件夹里的数据搬到数据文件夹
//   CSV → sessions/，calibration.json → 根目录，
//   gallery_cache/ → _old_cache/（旧的缩略图，供参考），exports/ → _old_exports/（以前保存的高清图）
// 只"移动"不删除；同名文件已存在时跳过（不覆盖）。
void migrateFromSketchFolder() {
  File sk = new File(sketchPath(""));
  if (sk.getAbsolutePath().equals(dataRoot().getAbsolutePath())) return;
  int moved = 0;
  File[] csvs = sk.listFiles((dir, name) -> name.startsWith("eeg_session_") && name.endsWith(".csv"));
  if (csvs != null) {
    for (File f : csvs) if (moveFile(f, sessionFile(f.getName()))) moved++;
  }
  File cal = new File(sk, "calibration.json");
  if (cal.exists()) moveFile(cal, dataRootFile("calibration.json"));
  File oldCache = new File(sk, "gallery_cache");
  if (oldCache.isDirectory()) moveFile(oldCache, dataRootFile("_old_cache"));
  File oldExports = new File(sk, "exports");
  if (oldExports.isDirectory()) moveFile(oldExports, dataRootFile("_old_exports"));
  if (moved > 0) println("データを移動しました：" + moved + " 件 → " + sessionsDir().getAbsolutePath());
}

boolean moveFile(File src, File dst) {
  if (dst.exists()) {
    println("移動をスキップ（同名ファイルあり）：" + dst.getName());
    return false;
  }
  try {
    java.nio.file.Files.move(src.toPath(), dst.toPath());
    return true;
  } catch (Exception e) {
    println("移動に失敗しました：" + src.getName() + "（" + e.getMessage() + "）");
    return false;
  }
}

String stemOf(String csvName) { return csvName.replace(".csv", ""); }
