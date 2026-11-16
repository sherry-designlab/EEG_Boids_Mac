// ===== 噪声处理 =====
// 实时录制与 CSV 导入共用同一套判定。一个样本（某一时刻 5 频段 × 4 电极的值）满足以下任一条件即视为噪声，整行丢弃：
//   1. NaN / 无穷大            ：Mind Monitor 在电极异常时会发送 NaN
//   2. 范围外                  ：absolute band power（log10）超出 [NOISE_BAND_MIN, NOISE_BAND_MAX]
//                                （实测正常值约 -0.6 ~ 1.9；-9 之类的尖峰会被排除）
//   3. 接触不良                ：horseshoe / HSI 有任一电极为 4（= bad）
//   4. 冻结值                  ：θ/α/β 中有电极的值与上一个样本完全相同
//                                （Mind Monitor 掉包时会重复发送上一个值；真实 EEG 隔 1 秒完全相同几乎不可能）
// 另外，咬牙（jaw clench）前后 rejectWindowSec 秒内的数据也不使用（原有处理）。
// 注意：A / V 为 ±1.0 本身不算噪声——那是正规化后超过 ±2σ 被截断的结果，多数源于校准基准偏移。

float NOISE_BAND_MIN = -2.0f;
float NOISE_BAND_MAX = 3.0f;
int   NOISE_CONTACT_BAD = 4;          // horseshoe / HSI 中 >= 该值视为接触不良

// 实时录制的统计（每次开始录制时清零）
int noiseRejectedCount = 0;
String lastNoiseReason = "";
float lastNoiseCountSec = -1e9;

// 最近一次被接受的样本（冻结判定 + CSV 写入用的快照），顺序：delta, theta, alpha, beta, gamma
float[][] acceptedBands = null;
boolean sampleReadyForSave = false;  // updateEmotion() 接受了新样本 → saveCurrentData() 写一行

int lastHorseshoeMillis = -100000;

// 判定一个样本；正常返回 null，否则返回原因（日语，显示在画面上）
// bands: [5][4]，prev: 上一个被接受的样本（可为 null），contact: 4 个电极的接触质量（可为 null）
String checkNoise(float[][] bands, float[][] prev, float[] contact) {
  for (int b = 0; b < bands.length; b++) {
    for (int i = 0; i < 4; i++) {
      float x = bands[b][i];
      if (Float.isNaN(x) || Float.isInfinite(x)) return "NaN";
      if (x < NOISE_BAND_MIN || x > NOISE_BAND_MAX) return "範囲外の値";
    }
  }
  if (contact != null) {
    for (int i = 0; i < 4; i++) {
      if (contact[i] >= NOISE_CONTACT_BAD) return "接触不良";
    }
  }
  if (prev != null) {
    // θ(1), α(2), β(3) —— A/V 计算实际使用的频段
    for (int b = 1; b <= 3; b++) {
      for (int i = 0; i < 4; i++) {
        if (bands[b][i] == prev[b][i]) return "値の固定（フリーズ）";
      }
    }
  }
  return null;
}

float[][] copyBands(float[][] src) {
  float[][] c = new float[src.length][];
  for (int i = 0; i < src.length; i++) c[i] = src[i].clone();
  return c;
}

// 实时：horseshoe 最近 2 秒内收到过才用于判定（没有 horseshoe 的数据源时不因此全部丢弃）
float[] recentContact() {
  if (millis() - lastHorseshoeMillis < 2000) return horseshoe.clone();
  return null;
}

void resetNoiseStats() {
  noiseRejectedCount = 0;
  lastNoiseReason = "";
  lastNoiseCountSec = -1e9;
}
