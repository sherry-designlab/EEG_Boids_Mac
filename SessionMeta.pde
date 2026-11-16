// ===== 会话 JSON（与 CSV 同名、放在同一文件夹）=====
// 内容：swarm_seed / swarm_start（录制开始时的鱼群）/ events（EEG 连接变化）/ end_step 等。
File sessionMetaFile(File csv) {
  return new File(csv.getParentFile(), csv.getName().replace(".csv", ".json"));
}

JSONObject sessionMetaLoad(File csv) {
  File f = sessionMetaFile(csv);
  if (!f.exists()) return null;
  try {
    return loadJSONObject(f.getAbsolutePath());
  } catch (Exception e) {
    println("JSON 読み込み失敗: " + f.getName());
    return null;
  }
}
