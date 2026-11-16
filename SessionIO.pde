// SessionFrame用来存储一帧数据
class SessionFrame {
  long timeMs;
  float arousal;
  float valence;
  
  SessionFrame(long t, float a, float v) {
    timeMs = t;
    arousal = a;
    valence = v;
  }
}

// ===== CSV保存和读取 =====
void initializeSave() {
  String timestamp = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date());
  currentSessionFile = "eeg_session_" + timestamp + ".csv";
  csvWriter = createWriter(sessionFile(currentSessionFile).getAbsolutePath());
  // 前 5 列与旧版相同（画廊、光绘只读取这 5 列，旧 CSV 仍可正常使用）；
  // 之后追加 5 个频段 × 4 个电极（TP9, AF7, AF8, TP10）的 absolute band power，供以后回放使用
  // 最后一列 sim_step：这一行的 A / V 在实时鱼群的第几步生效（回放用；SwarmSim.pde）
  csvWriter.println("time_ms,arousal_raw,valence_raw,arousal_norm,valence_norm," + bandHeader() + ",sim_step");
  csvWriter.flush();
  
  println("保存を開始：" + currentSessionFile);
}

void loadPreviousSession() {
  File folder = sessionsDir();
  File[] files = folder.listFiles((dir, name) -> 
    name.startsWith("eeg_session_") && name.endsWith(".csv")
  );
  
  if (files == null || files.length < 2) {
    println("⚠ 初めての実行の場合、または前回のデータがない");
    lastSessionFile = "";
    return;
  }
  
  Arrays.sort(files, (a, b) -> Long.compare(b.lastModified(), a.lastModified()));
  lastSessionFile = files[1].getName();
  println("前回のデータを読み込む：" + lastSessionFile);
  
  String[] lines = loadStrings(files[1].getAbsolutePath());
  
  if (lines != null && lines.length > 1) {
    for (int i = 1; i < lines.length; i++) {
      String[] parts = split(lines[i], ',');
      if (parts.length >= 5) {
        try {
          long timeMs = Long.parseLong(parts[0]);
          float arousalRaw = Float.parseFloat(parts[1]);
          float valenceRaw = Float.parseFloat(parts[2]);
          float arousalNorm = Float.parseFloat(parts[3]);
          float valenceNorm = Float.parseFloat(parts[4]);
          
          lastSessionData.add(new SessionFrame(timeMs, arousalNorm, valenceNorm));
        } catch (NumberFormatException e) {
          continue;
        }
      }
    }
    println("   加载了 " + lastSessionData.size() + " 个数据点");
  }
}

void saveCurrentData() {
  // 只在"录制中 + EEG 已连接"时写入（见 Recording.pde / EEGConnection.pde）
  if (!isRecording || csvWriter == null || !eegConnected) {
    return;
  }
  // Exclude data from calibration
  if(!normalization.isCalibrated){
    return;
  }
  // 只在 updateEmotion() 接受了新的干净样本时写一行（噪声样本、咬牙期间都不会产生新样本 → 对应的行被去除）
  if (!sampleReadyForSave) return;
  sampleReadyForSave = false;
  
  long timeMs = System.currentTimeMillis() - sessionStartTime;
  csvWriter.println(timeMs + "," + arousalRaw + "," + valenceRaw + "," + arousal + "," + valence + "," + bandValues() + "," + liveSim.step);
  csvWriter.flush();
  recordedRows++;
}

// ===== 频段数据列 =====
String[] BAND_NAMES = { "delta", "theta", "alpha", "beta", "gamma" };
String[] ELECTRODES = { "TP9", "AF7", "AF8", "TP10" };

// 例：delta_TP9,delta_AF7,delta_AF8,delta_TP10,theta_TP9,...,gamma_TP10（共 20 列）
String bandHeader() {
  StringBuilder sb = new StringBuilder();
  for (String b : BAND_NAMES) {
    for (String e : ELECTRODES) {
      if (sb.length() > 0) sb.append(",");
      sb.append(b).append("_").append(e);
    }
  }
  return sb.toString();
}

// 写入"被接受的那个样本"的各频段值（与计算 A/V 所用的是同一组；log 尺度）
String bandValues() {
  float[][] bands = acceptedBands != null ? acceptedBands : new float[][] { delta, theta, alpha, beta, gamma };
  StringBuilder sb = new StringBuilder();
  for (float[] arr : bands) {
    for (int i = 0; i < 4; i++) {
      if (sb.length() > 0) sb.append(",");
      sb.append(arr[i]);
    }
  }
  return sb.toString();
}
