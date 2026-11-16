// ===== 外部 CSV 导入（Data Management → 外部からインポート）=====
// 读取 Mind Monitor 录制的 CSV（也接受本系统的新格式 CSV），按以下步骤处理后保存到 sketch 文件夹：
//   1. 按列名找到 5 频段 × 4 电极（Delta_TP9 … Gamma_TP10，大小写不限）、TimeStamp、HSI_*、HeadBandOn、Elements
//   2. 逐行噪声判定（NoiseFilter.pde 的 checkNoise：NaN / 范围外 / 接触不良）＋ 未佩戴（HeadBandOn=0）＋ 咬牙前后 1.5 秒
//   3. 按 1 秒分箱取平均（与实时录制的 1Hz 对齐），并做冻结值判定
//   4. 用与实时相同的公式计算 arousal_raw / valence_raw，以 calibration.json 为基准正规化
//      （尚未校准时，用该文件自身的平均值和标准差作为基准）
//   5. 保存为 eeg_session_<录制开始时刻>_mm.csv（25 列，与实时录制相同），之后自动回放
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
  selectInput("インポートする CSV ファイルを選択してください（Mind Monitor 形式）", "importFileSelected");
}

// selectInput のコールバック
void importFileSelected(File f) {
  if (f == null) return;   // 取消
  importBusy = true;
  importProgress = "読み込み中…";
  final File src = f;
  Thread t = new Thread(() -> {
    try {
      runImport(src);
    } catch (Exception ex) {
      importError = "インポートに失敗しました：" + ex.getMessage();
      ex.printStackTrace();
    }
    importBusy = false;
  });
  t.setDaemon(true);
  t.start();
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
    openReplay(sessionFile(name), "インポート：" + name);
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
    importError = "空のファイルです";
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
        importError = "周波数帯の列（例：Alpha_AF7）が見つかりません。Mind Monitor の CSV を選んでください";
        return;
      }
      bandCol[b][e] = c;
    }
  }
  Integer tsCol = idx.get("timestamp");
  Integer tmsCol = idx.get("time_ms");
  if (tsCol == null && tmsCol == null) {
    br.close();
    importError = "時刻の列（TimeStamp）が見つかりません";
    return;
  }
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
  SimpleDateFormat fmtMs = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS");
  SimpleDateFormat fmtS = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

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
    if ((rawRows & 4095) == 0) importProgress = "読み込み中… " + round(100.0f * bytesRead / fileSize) + "%";
    if (line.trim().length() == 0) continue;
    String[] p = split(line, ',');

    // 时刻
    long t;
    try {
      if (tsCol != null) {
        String s = p[tsCol].trim();
        if (s.length() == 0) continue;
        t = (s.indexOf('.') >= 0 ? fmtMs.parse(s) : fmtS.parse(s)).getTime();
      } else {
        t = baseEpoch + Long.parseLong(p[tmsCol].trim());
      }
    } catch (Exception ex) {
      continue;
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
    importError = "有効なデータが不足しています（ノイズ除去後 " + n + " 秒分）";
    return;
  }

  // A / V（与 EmotionCalc.pde 相同的公式）
  importProgress = "覚醒度・快度を計算中…";
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
    importError = "既にインポートされています：" + outName;
    return;
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
  importResultMsg = "インポート完了：" + n + " 秒分を保存（元データ " + rawRows + " 行、除去 " + removedRows + " 行"
    + "［範囲外/NaN " + nRange + "・接触不良 " + nContact + "・未装着 " + nOff + "・咬合 " + nJaw + "］、フリーズ " + nFrozen + " 秒）。" + baseNote;
  println(importResultMsg);
  importProgress = "";
  importResultFile = outName;
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
