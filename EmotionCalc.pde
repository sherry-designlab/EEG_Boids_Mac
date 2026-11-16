// ===== 情绪计算 =====
void updateEmotion() {
  float now = millis() / 1000.0f;

  // EEG 未连接：不计算（避免用全 0 的频段数据算出假的 A/V）。
  // A / V 缓慢回到 0 的处理在模拟内部进行（SwarmSim.step），回放时可以同样重现
  if (!eegConnected) return;

  if (abs(now - lastJawClenchSec) <= rejectWindowSec) return;
  if (now - lastAcceptedSec < acceptIntervalSec) return;

  // ===== 噪声判定（NoiseFilter.pde）=====
  // 先取快照：OSC 在另一个线程更新数组，快照保证"判定、计算、写入 CSV"用的是同一组值
  float[][] snap = copyBands(new float[][] { delta, theta, alpha, beta, gamma });
  String noise = checkNoise(snap, acceptedBands, recentContact());
  if (noise != null) {
    // 不更新 lastAcceptedSec → 下一帧继续等待干净的数据；每秒最多计数一次
    if (now - lastNoiseCountSec >= acceptIntervalSec) {
      noiseRejectedCount++;
      lastNoiseCountSec = now;
    }
    lastNoiseReason = noise;
    return;
  }
  acceptedBands = snap;
  lastAcceptedSec = now;

  // 4电极data（0=TP9, 1=AF7, 2=AF8, 3=TP10）—— 使用快照
  float aTP9 = snap[2][0], aAF7 = snap[2][1], aAF8 = snap[2][2], aTP10 = snap[2][3];
  float bTP9 = snap[3][0], bAF7 = snap[3][1], bAF8 = snap[3][2], bTP10 = snap[3][3];
  float tTP9 = snap[1][0], tAF7 = snap[1][1], tAF8 = snap[1][2], tTP10 = snap[1][3];

  valenceRaw = (aAF8 - aAF7);

  float meanAlpha = 0.25f * (aTP9 + aAF7 + aAF8 + aTP10);
  float meanBeta  = 0.25f * (bTP9 + bAF7 + bAF8 + bTP10);
  float meanTheta = 0.25f * (tTP9 + tAF7 + tAF8 + tTP10);

  float pAlpha = pow10(meanAlpha);
  float pBeta  = pow10(meanBeta);
  float pTheta = pow10(meanTheta);

  arousalRaw = pBeta / (pAlpha + pTheta + 1e-12f);

  // ===== 校准阶段处理 =====
  long currentTimeMs = System.currentTimeMillis();
  long elapsedSinceCalibStart = currentTimeMs - calibrationStartTime;
  
  if (!normalization.isCalibrated) {
    // 校准阶段：收集数据
    if (elapsedSinceCalibStart < normalization.calibrationTimeMs) {
      normalization.addCalibrationSample(arousalRaw, valenceRaw);
      // 校准期间显示为0
      arousal = 0;
      valence = 0;
      liveSim.setInput(0, 0, simThetaRatio(snap));
      return;
    } else {
      // 校准完成！
      normalization.finishCalibration();
    }
  }

  // ===== 用固定基准进行正规化 =====
  float aZ = constrain(normalization.normalizeArousal(arousalRaw), -2, 2);
  float vZ = constrain(normalization.normalizeValence(valenceRaw), -2, 2);

  arousal = constrain(aZ / 2.0f, -1, 1);
  valence = constrain(vZ / 2.0f, -1, 1);

  // 送入实时鱼群（从下一步开始生效）；录制中同一个值和步数会写进 CSV
  liveSim.setInput(arousal, valence, simThetaRatio(snap));

  // 通知 saveCurrentData()：有一个新的干净样本可以写入
  sampleReadyForSave = true;
}

float computeThetaRatio() {
  float aTP9 = alpha[0], aAF7 = alpha[1], aAF8 = alpha[2], aTP10 = alpha[3];
  float bTP9 = beta[0],  bAF7 = beta[1],  bAF8 = beta[2],  bTP10 = beta[3];
  float tTP9 = theta[0], tAF7 = theta[1], tAF8 = theta[2], tTP10 = theta[3];

  float meanAlpha = 0.25f * (aTP9 + aAF7 + aAF8 + aTP10);
  float meanBeta  = 0.25f * (bTP9 + bAF7 + bAF8 + bTP10);
  float meanTheta = 0.25f * (tTP9 + tAF7 + tAF8 + tTP10);

  float pAlpha = pow10(meanAlpha);
  float pBeta  = pow10(meanBeta);
  float pTheta = pow10(meanTheta);

  return pTheta / (pAlpha + pBeta + pTheta + 1e-12f);
}

float pow10(float x) {
  return (float)Math.pow(10, x);
}
