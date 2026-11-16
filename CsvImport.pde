// ===== 外部 CSV 导入（Data Management → 外部からインポート）=====
// 读取 Mind Monitor 录制的 CSV（也接受本系统的新格式 CSV），按以下步骤处理后保存到 sketch 文件夹：
//   1. 按列名找到 5 频段 × 4 电极（Delta_TP9 … Gamma_TP10，大小写不限）、时刻列、HSI_*、HeadBandOn、Elements
//      时刻列可选：TimeStamp（日期时间）/ timestamps（Unix 秒）/ t_ms（旧 demo 系统，Unix 毫秒）/ time / time_ms 等；
//      没有时刻列时，询问"每行的间隔"（例：1 秒、0.1 秒），按等间隔处理
//   2. 逐行噪声判定（NoiseFilter.pde 的 checkNoise：NaN / 范围外 / 接触不良）＋ 未佩戴（HeadBandOn=0）＋ 咬牙前后 1.5 秒
//   3. 按 1 秒分箱取平均（与实时录制的 1Hz 对齐），并做冻结值判定
//   4. 用与实时相同的公式计算 arousal_raw / valence_raw，以 calibration.json 为基准正规化
//      （尚未校准时，用该文件自身的平均值和标准差作为基准）
//   5. 保存为 eeg_session_<录制开始时刻>_mm.csv（25 列，与实时录制相同）
// 可以一次选择多个文件（依次处理）。只导入 1 个文件时，完成后自动回放。
// 处理在后台线程进行，大文件也不会卡住画面。

volatile boolean importBusy = false;
volatile String importProgress = "";
volatile String importResultFile = null;   // 完成后由主线程处理（刷新列表、回放）
volatile String importResultMsg = null;
volatile String importError = null;

String[] IMPORT_BANDS = { "delta", "theta", "alpha", "beta", "gamma" };
String[] IMPORT_ELECTRODES = { "tp9", "af7", "af8", "tp10" };

void startImportDialog() {
  if (importBusy) {
    showToast("インポート処理中です。しばらくお待ちください");
    return;
  }
  importBusy = true;
  importProgress = "ファイルを選択中…";
  // macOS 标准的文件选择窗口，可以按住 ⌘ 或 Shift 一次选择多个 CSV
  Thread t = new Thread(() -> {
    try {
      java.awt.FileDialog fd = new java.awt.FileDialog((java.awt.Frame)null, "インポートする CSV ファイルを選択（複数選択可）", java.awt.FileDialog.LOAD);
      fd.setMultipleMode(true);
      fd.setFilenameFilter((dir, name) -> name.toLowerCase().endsWith(".csv"));
      fd.setVisible(true);
      File[] files = fd.getFiles();
      if (files == null || files.length == 0) {
        importProgress = "";
        importBusy = false;
        return;
      }
      runImportBatch(files);
    } catch (Exception ex) {
      importError = "インポートに失敗しました：" + ex.getMessage();
      ex.printStackTrace();
    }
    importProgress = "";
    importBusy = false;
  });
  t.setDaemon(true);
  t.start();
}

// 依次导入多个文件，最后汇总结果
int importIntervalMs = -1;   // 没有时刻列的文件：每行的间隔（这一批共用，只问一次）
String lastImportOut, lastImportMsg, lastImportErr;

void runImportBatch(File[] files) {
  importIntervalMs = -1;
  ArrayList<String> ok = new ArrayList<String>();
  ArrayList<String> failed = new ArrayList<String>();
  for (int i = 0; i < files.length; i++) {
    File f = files[i];
    importPrefix = files.length > 1 ? "（" + (i + 1) + " / " + files.length + "）" : "";
    lastImportOut = null; lastImportMsg = null; lastImportErr = null;
    try {
      runImport(f);
    } catch (Exception ex) {
      lastImportErr = ex.getMessage();
      ex.printStackTrace();
    }
    if (lastImportOut != null) ok.add(lastImportOut);
    else failed.add(f.getName() + "：" + (lastImportErr != null ? lastImportErr : "不明なエラー"));
  }
  importPrefix = "";
  for (String fl : failed) println("インポート失敗 " + fl);
  if (files.length == 1) {
    if (lastImportOut != null) {
      importResultMsg = lastImportMsg;
      importResultFile = lastImportOut;
      importReplay = true;
    } else {
      importError = "インポートに失敗しました：" + failed.get(0);
    }
    return;
  }
  // 多个文件：不自动回放，显示汇总
  String msg = ok.size() + " 件をインポートしました";
  if (failed.size() > 0) msg += "（失敗 " + failed.size() + " 件：" + failed.get(0) + (failed.size() > 1 ? " ほか" : "") + "）";
  importResultMsg = msg;
  importReplay = false;
  if (ok.size() > 0) importResultFile = ok.get(ok.size() - 1);
  else importError = msg;
}

String importPrefix = "";
volatile boolean importReplay = true;

// 没有时刻列时：询问每行的间隔（Swing 对话框；一批文件只问一次）
int askRowInterval(final String fileName) {
  final String[] labels = { "1 秒", "0.5 秒", "0.2 秒（5 Hz）", "0.1 秒（10 Hz）", "1/256 秒（256 Hz）" };
  final int[] ms = { 1000, 500, 200, 100, -256 };   // -256 = 256Hz（毫秒不是整数，特别处理）
  final int[] result = { 0 };
  try {
    javax.swing.SwingUtilities.invokeAndWait(() -> {
      Object sel = javax.swing.JOptionPane.showInputDialog(null,
        fileName + "\nには時刻の列がありません。\n1 行あたりの記録間隔を選んでください（Mind Monitor の Recording Interval）。",
        "記録間隔", javax.swing.JOptionPane.QUESTION_MESSAGE, null, labels, labels[0]);
      if (sel == null) { result[0] = 0; return; }
      for (int i = 0; i < labels.length; i++) if (labels[i].equals(sel)) result[0] = ms[i];
    });
  } catch (Exception ex) {
    result[0] = 1000;
  }
  return result[0];
}

// 时刻列的解析：日期时间字符串 / Unix 秒・毫秒 / 相对秒
SimpleDateFormat[] IMPORT_DATE_FMTS = {
  new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS"), new SimpleDateFormat("yyyy-MM-dd HH:mm:ss"),
  new SimpleDateFormat("yyyy/MM/dd HH:mm:ss.SSS"), new SimpleDateFormat("yyyy/MM/dd HH:mm:ss")
};

long parseTimeCell(String s, long baseEpoch, boolean isMs) throws Exception {
  if (isMs) return baseEpoch + (long)Double.parseDouble(s);
  if (s.indexOf('-') > 0 || s.indexOf('/') > 0) {
    for (SimpleDateFormat f : IMPORT_DATE_FMTS) {
      try {
        java.text.ParsePosition pp = new java.text.ParsePosition(0);
        Date d = f.parse(s, pp);
        if (d != null && pp.getIndex() == s.length()) return d.getTime();
      } catch (Exception ex) { }
    }
    throw new Exception("date");
  }
  double v = Double.parseDouble(s);
  if (v > 1e11) return (long)v;                // Unix 毫秒
  if (v > 1e8) return (long)(v * 1000);         // Unix 秒
  return baseEpoch + (long)(v * 1000);          // 相对秒
}

// 主线程每帧调用：处理导入完成 / 失败
void checkImportDone() {
  if (importError != null) {
    showToast(importError, 7000);
    importError = null;
  }
  if (importResultFile != null) {
    String name = importResultFile;
    importResultFile = null;
    refreshDataList();
    dmSelected = name;
    showToast(importResultMsg, 8000);
    if (importReplay) openReplay(sessionFile(name), "インポート：" + name);
  }
}

// ----- 导入本体（后台线程）-----
void runImport(File src) throws Exception {
  long fileSize = Math.max(1L, src.length());
  java.io.BufferedReader br = new java.io.BufferedReader(
    new java.io.InputStreamReader(new java.io.FileInputStream(src), "UTF-8"));
  String header = br.readLine();
  if (header == null) {
    br.close();
    lastImportErr = "空のファイルです";
    return;
  }
  if (header.length() > 0 && header.charAt(0) == '﻿') header = header.substring(1);   // BOM
  String[] cols = split(header, ',');
  HashMap<String, Integer> idx = new HashMap<String, Integer>();
  for (int i = 0; i < cols.length; i++) idx.put(cols[i].trim().toLowerCase(), i);

  // 频段列
  int[][] bandCol = new int[5][4];
  for (int b = 0; b < 5; b++) {
    for (int e = 0; e < 4; e++) {
      Integer c = idx.get(IMPORT_BANDS[b] + "_" + IMPORT_ELECTRODES[e]);
      if (c == null) {
        br.close();
        lastImportErr = "周波数帯の列（例：Alpha_AF7）が見つかりません。Mind Monitor の CSV を選んでください";
        return;
      }
      bandCol[b][e] = c;
    }
  }
  // 时刻列（可选）
  Integer tsCol = null;
  boolean tsIsMs = false;
  // t_ms：旧 demo 系统的记录（Unix 毫秒）
  for (String nm : new String[] { "timestamp", "timestamps", "t_ms", "unix_ms", "time", "time_s", "datetime", "date_time" }) {
    if (tsCol == null && idx.get(nm) != null) tsCol = idx.get(nm);
  }
  if (tsCol == null) {
    for (String nm : new String[] { "time_ms", "timestamp_ms", "elapsed_ms" }) {
      if (tsCol == null && idx.get(nm) != null) { tsCol = idx.get(nm); tsIsMs = true; }
    }
  }
  // 没有时刻列：按等间隔处理（间隔询问一次，这一批文件共用）
  double rowStepMs = 0;
  if (tsCol == null) {
    if (importIntervalMs < 0) importIntervalMs = askRowInterval(src.getName());
    if (importIntervalMs == 0) {
      br.close();
      lastImportErr = "記録間隔が選ばれなかったためスキップしました";
      return;
    }
    rowStepMs = importIntervalMs == -256 ? 1000.0 / 256 : importIntervalMs;
  }
  long rowIndex = 0;
  int[] hsiCol = new int[4];
  boolean hasHsi = true;
  for (int e = 0; e < 4; e++) {
    Integer c = idx.get("hsi_" + IMPORT_ELECTRODES[e]);
    if (c == null) hasHsi = false; else hsiCol[e] = c;
  }
  Integer headOnCol = idx.get("headbandon");
  Integer elemCol = idx.get("elements");

  // 本系统格式（time_ms）时：开始时刻取自文件名，没有则取文件修改时间
  long baseEpoch = src.lastModified();
  String[] m = match(src.getName(), "(\\d{8}_\\d{6})");
  if (m != null) {
    try {
      baseEpoch = new SimpleDateFormat("yyyyMMdd_HHmmss").parse(m[1]).getTime();
    } catch (Exception ex) { }
  }

  // 统计
  int rawRows = 0, usedRows = 0;
  int nRange = 0, nContact = 0, nOff = 0, nJaw = 0, nFrozen = 0;
  long t0 = -1;
  long lastJaw = Long.MIN_VALUE / 2;

  // 1 秒分箱
  long curBin = Long.MIN_VALUE;
  float[][] binSum = new float[5][4];
  int binCount = 0;
  float[][] prevBinMean = null;
  ArrayList<long[]> outTime = new ArrayList<long[]>();      // {bin}
  ArrayList<float[][]> outBands = new ArrayList<float[][]>();

  long bytesRead = header.length();
  String line;
  while ((line = br.readLine()) != null) {
    bytesRead += line.length() + 1;
    if ((rawRows & 4095) == 0) importProgress = "読み込み中" + importPrefix + "… " + round(100.0f * bytesRead / fileSize) + "%";
    if (line.trim().length() == 0) continue;
    String[] p = split(line, ',');

    // 时刻
    long t;
    if (tsCol != null) {
      try {
        String s = tsCol < p.length ? p[tsCol].trim() : "";
        if (s.length() == 0) continue;
        t = parseTimeCell(s, baseEpoch, tsIsMs);
      } catch (Exception ex) {
        continue;
      }
    } else {
      t = baseEpoch + (long)(rowIndex * rowStepMs);   // 等间隔（有频段值的行才前进，见下）
    }

    // 咬牙标记行（Elements 列）
    if (elemCol != null && elemCol < p.length && p[elemCol].toLowerCase().indexOf("jaw_clench") >= 0) {
      lastJaw = t;
      continue;
    }

    // 频段值（空 = 标记行等，不计入）
    float[][] bands = new float[5][4];
    boolean empty = false;
    for (int b = 0; b < 5 && !empty; b++) {
      for (int e = 0; e < 4; e++) {
        int c = bandCol[b][e];
        if (c >= p.length || p[c].trim().length() == 0) { empty = true; break; }
        try { bands[b][e] = Float.parseFloat(p[c].trim()); }
        catch (NumberFormatException ex) { bands[b][e] = Float.NaN; }
      }
    }
    if (empty) continue;
    rowIndex++;
    rawRows++;
    if (t0 < 0) t0 = t;

    // 逐行噪声判定
    if (headOnCol != null && headOnCol < p.length && p[headOnCol].trim().equals("0")) { nOff++; continue; }
    if (t - lastJaw <= (long)(rejectWindowSec * 1000)) { nJaw++; continue; }
    float[] contact = null;
    if (hasHsi) {
      contact = new float[4];
      for (int e = 0; e < 4; e++) {
        try { contact[e] = Float.parseFloat(p[hsiCol[e]].trim()); } catch (Exception ex) { contact[e] = 1; }
      }
    }
    String noise = checkNoise(bands, null, contact);
    if (noise != null) {
      if (noise.equals("接触不良")) nContact++; else nRange++;
      continue;
    }
    usedRows++;

    // 分箱
    long bin = (t - t0) / 1000;
    if (bin != curBin) {
      if (binCount > 0) {
        float[][] mean = binMean(binSum, binCount);
        if (prevBinMean != null && checkNoise(mean, prevBinMean, null) != null) nFrozen++;
        else {
          outTime.add(new long[] { curBin });
          outBands.add(mean);
          prevBinMean = mean;
        }
      }
      curBin = bin;
      binSum = new float[5][4];
      binCount = 0;
    }
    for (int b = 0; b < 5; b++) for (int e = 0; e < 4; e++) binSum[b][e] += bands[b][e];
    binCount++;
  }
  br.close();
  if (binCount > 0) {
    float[][] mean = binMean(binSum, binCount);
    if (prevBinMean != null && checkNoise(mean, prevBinMean, null) != null) nFrozen++;
    else {
      outTime.add(new long[] { curBin });
      outBands.add(mean);
    }
  }

  int n = outBands.size();
  if (n < 2) {
    lastImportErr = "有効なデータが不足しています（ノイズ除去後 " + n + " 秒分）";
    return;
  }

  // A / V（与 EmotionCalc.pde 相同的公式）
  importProgress = "覚醒度・快度を計算中" + importPrefix + "…";
  float[] aRaw = new float[n], vRaw = new float[n];
  for (int i = 0; i < n; i++) {
    float[][] bd = outBands.get(i);
    vRaw[i] = bd[2][2] - bd[2][1];   // alpha AF8 - AF7
    float mTheta = 0.25f * (bd[1][0] + bd[1][1] + bd[1][2] + bd[1][3]);
    float mAlpha = 0.25f * (bd[2][0] + bd[2][1] + bd[2][2] + bd[2][3]);
    float mBeta  = 0.25f * (bd[3][0] + bd[3][1] + bd[3][2] + bd[3][3]);
    aRaw[i] = pow10(mBeta) / (pow10(mAlpha) + pow10(mTheta) + 1e-12f);
  }

  // 正规化基准
  float muA, sdA, muV, sdV;
  String baseNote;
  if (normalization.isCalibrated) {
    muA = normalization.baselineMeanArousal;
    sdA = normalization.baselineSDDArousal;
    muV = normalization.baselineMeanValence;
    sdV = normalization.baselineSDValence;
    baseNote = "calibration.json を基準に正規化";
  } else {
    muA = meanOf(aRaw); sdA = sdOf(aRaw, muA);
    muV = meanOf(vRaw); sdV = sdOf(vRaw, muV);
    baseNote = "キャリブレーション未実施のため、このファイル自身の平均を基準に正規化";
  }

  // 保存
  String startName = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date(t0));
  String outName = "eeg_session_" + startName + "_mm.csv";
  File out = sessionFile(outName);
  if (out.exists()) {
    if (tsCol != null) {
      lastImportErr = "既にインポートされています：" + outName;
      return;
    }
    // 没有时刻列时开始时刻来自文件名或修改时间，可能与其他文件相同：加编号区分
    int k = 2;
    while (out.exists()) {
      outName = "eeg_session_" + startName + "_" + k + "_mm.csv";
      out = sessionFile(outName);
      k++;
    }
  }
  PrintWriter w = new PrintWriter(out, "UTF-8");
  w.println("time_ms,arousal_raw,valence_raw,arousal_norm,valence_norm," + bandHeader());
  for (int i = 0; i < n; i++) {
    float aZ = sdA < 1e-6f ? 0 : constrain((aRaw[i] - muA) / sdA, -2, 2);
    float vZ = sdV < 1e-6f ? 0 : constrain((vRaw[i] - muV) / sdV, -2, 2);
    StringBuilder sb = new StringBuilder();
    sb.append(outTime.get(i)[0] * 1000).append(',').append(aRaw[i]).append(',').append(vRaw[i]).append(',')
      .append(constrain(aZ / 2.0f, -1, 1)).append(',').append(constrain(vZ / 2.0f, -1, 1));
    float[][] bd = outBands.get(i);
    for (int b = 0; b < 5; b++) for (int e = 0; e < 4; e++) sb.append(',').append(bd[b][e]);
    w.println(sb.toString());
  }
  w.close();

  int removedRows = nRange + nContact + nOff + nJaw;
  lastImportMsg = "インポート完了：" + n + " 秒分を保存（元データ " + rawRows + " 行、除去 " + removedRows + " 行"
    + "［範囲外/NaN " + nRange + "・接触不良 " + nContact + "・未装着 " + nOff + "・咬合 " + nJaw + "］、フリーズ " + nFrozen + " 秒）。" + baseNote;
  if (tsCol == null) lastImportMsg += "（時刻の列なし：" + (importIntervalMs == -256 ? "256 Hz" : (importIntervalMs / 1000.0f) + " 秒間隔") + "として処理）";
  println(lastImportMsg);
  lastImportOut = outName;
}

float[][] binMean(float[][] sum, int count) {
  float[][] m = new float[5][4];
  for (int b = 0; b < 5; b++) for (int e = 0; e < 4; e++) m[b][e] = sum[b][e] / count;
  return m;
}

float meanOf(float[] x) {
  double s = 0;
  for (float v : x) s += v;
  return (float)(s / x.length);
}

float sdOf(float[] x, float mu) {
  double s = 0;
  for (float v : x) s += (v - mu) * (v - mu);
  return (float)Math.sqrt(s / max(1, x.length - 1));
}
