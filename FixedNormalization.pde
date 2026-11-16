// ===== 在线统计（Welford） =====
// ===== 固定基准正规化类（支持保存/读取） =====
class FixedNormalization {
  // 校准期间收集的基准值
  float baselineMeanArousal = 0;
  float baselineSDDArousal = 1;
  float baselineMeanValence = 0;
  float baselineSDValence = 1;
  
  // 用来收集校准数据
  ArrayList<Float> calibrationArousal = new ArrayList<Float>();
  ArrayList<Float> calibrationValence = new ArrayList<Float>();
  
  boolean isCalibrated = false;
  float calibrationTimeMs = 300000;  // 300秒校准期
  
  String calibrationFile = "calibration.json";  // 保存位置
  
  // ===== 新增：初始化时尝试读取已保存的基准 =====
  void initialize() {
    if (loadCalibrationFromFile()) {
      // 成功读取文件
      isCalibrated = true;
      println("✓ 加载已保存的校准数据");
      println("  Arousal: μ=" + nf(baselineMeanArousal, 1, 4) + " σ=" + nf(baselineSDDArousal, 1, 4));
      println("  Valence: μ=" + nf(baselineMeanValence, 1, 4) + " σ=" + nf(baselineSDValence, 1, 4));
    } else {
      // 文件不存在或读取失败，需要校准
      println("⚠ 未找到校准数据，需要进行初始校准");
      println("📊 请在接下来300秒内保持自然状态...");
    }
  }
  
  // 添加校准数据点
  void addCalibrationSample(float a, float v) {
    if (!isCalibrated) {
      calibrationArousal.add(a);
      calibrationValence.add(v);
    }
  }
  
  // 完成校准，计算固定基准
  void finishCalibration() {
    if (calibrationArousal.size() > 0) {
      // 计算Arousal的平均和标准差
      float sumA = 0, sumV = 0;
      for (float a : calibrationArousal) sumA += a;
      for (float v : calibrationValence) sumV += v;
      
      baselineMeanArousal = sumA / calibrationArousal.size();
      baselineMeanValence = sumV / calibrationValence.size();
      
      // 计算标准差
      float varA = 0, varV = 0;
      for (float a : calibrationArousal) varA += sq(a - baselineMeanArousal);
      for (float v : calibrationValence) varV += sq(v - baselineMeanValence);
      
      baselineSDDArousal = sqrt(varA / max(1, calibrationArousal.size() - 1));
      baselineSDValence = sqrt(varV / max(1, calibrationValence.size() - 1));
      
      isCalibrated = true;
      
      // 保存到文件
      saveCalibrationToFile();
      
      println("✓ キャリブレーションが完了しました。保存されました");
      println("  Arousal: μ=" + nf(baselineMeanArousal, 1, 4) + " σ=" + nf(baselineSDDArousal, 1, 4));
      println("  Valence: μ=" + nf(baselineMeanValence, 1, 4) + " σ=" + nf(baselineSDValence, 1, 4));
      println("  サンプル数: " + calibrationArousal.size());
    }
  }
  
  // ===== 新增：保存校准数据到JSON文件 =====
  void saveCalibrationToFile() {
    try {
      JSONObject calibData = new JSONObject();
      calibData.setFloat("baselineMeanArousal", baselineMeanArousal);
      calibData.setFloat("baselineSDDArousal", baselineSDDArousal);
      calibData.setFloat("baselineMeanValence", baselineMeanValence);
      calibData.setFloat("baselineSDValence", baselineSDValence);
      calibData.setLong("savedTime", System.currentTimeMillis());
      
      // 获取sketches目录路径
      File sketchDir = dataRoot();
      File calibFile = new File(sketchDir, calibrationFile);
      
      PrintWriter writer = new PrintWriter(calibFile);
      writer.println(calibData.toString());  // 格式化JSON
      writer.close();
      
      println("ファイルが保存されました." + calibFile.getAbsolutePath());
    } catch (Exception e) {
      println("✗キャリブレーションファイルの保存に失敗しました." + e.getMessage());
    }
  }
  
  // ===== 新增：从JSON文件读取校准数据 =====
  boolean loadCalibrationFromFile() {
    try {
      File sketchDir = dataRoot();
      File calibFile = new File(sketchDir, calibrationFile);
      
      if (!calibFile.exists()) {
        return false;  // 文件不存在
      }
      
      String content = new String(java.nio.file.Files.readAllBytes(calibFile.toPath()));
      JSONObject calibData = JSONObject.parse(content);
      
      baselineMeanArousal = calibData.getFloat("baselineMeanArousal");
      baselineSDDArousal = calibData.getFloat("baselineSDDArousal");
      baselineMeanValence = calibData.getFloat("baselineMeanValence");
      baselineSDValence = calibData.getFloat("baselineSDValence");
      
      return true;
    } catch (Exception e) {
      println("✗キャリブレーションファイルの読み込みに失敗しました: " + e.getMessage());
      return false;
    }
  }
  
  // 用固定基准进行正规化
  float normalizeArousal(float rawValue) {
    if (baselineSDDArousal < 1e-6) return 0;
    return (rawValue - baselineMeanArousal) / baselineSDDArousal;
  }
  
  float normalizeValence(float rawValue) {
    if (baselineSDValence < 1e-6) return 0;
    return (rawValue - baselineMeanValence) / baselineSDValence;
  }
}

// ===== 新增：删除校准文件的方法 =====
boolean deleteCalibrationFile() {
  try {
    File sketchDir = dataRoot();
    File calibFile = new File(sketchDir, "calibration.json");
    
    if (calibFile.exists()) {
      boolean success = calibFile.delete();
      if (success) {
        println("ファイルを削除しました: " + calibFile.getAbsolutePath());
        return true;
      }
    } else {
      println("⚠ファイルが存在しません");
      return false;
    }
  } catch (Exception e) {
    println("✗ファイルの削除に失敗しました: " + e.getMessage());
    return false;
  }
  return false;
}
