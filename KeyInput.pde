// ===== 快捷键 =====
void keyPressed() {
  // 回放窗口打开时：ESC = 关闭回放（不退出程序），其他按键忽略
  if (replayActive) {
    if (key == ESC) {
      key = 0;
      closeReplay();
    }
    return;
  }

  // 作品查看画面：← → 切换，ESC 返回（Viewer.pde）
  if (galleryOpen && viewerHandleKey()) return;
  if (galleryMemoPopup != null) {
    if (key == ESC) { key = 0; galleryMemoPopup = null; }
    return;
  }

  // 删除确认窗口打开时：ESC = 取消（不退出程序），其他按键忽略
  if (galleryPendingDelete != null || dmPendingDelete != null) {
    if (key == ESC) {
      key = 0;
      galleryPendingDelete = null;
      dmPendingDelete = null;
    }
    return;
  }

  // M：冥想中做标记（名称在结束后的メモ中补写；Diary.pde）
  if ((key == 'm' || key == 'M') && isRecording) {
    addMarker();
    return;
  }

  // E：进化面板（EvolutionUI.pde）
  if (key == 'e' || key == 'E') {
    evoPanelOpen = !evoPanelOpen;
    return;
  }

  // Space：开始 / 结束瞑想（录制）
  if (key == ' ') {
    toggleRecording();
    return;
  }

  if (key == 'x' || key == 'X') {
    println("保存并退出...");
    stopRecording(false);   // 录制中则正常结束并保存（退出时不回放）
    exit();
  }
  
// ===== 新增：按R键重新校准（删除calibration.json） =====
  if (key == 'r' || key == 'R') {
    stopRecording(false);   // 重新校准前先结束录制
    if (deleteCalibrationFile()) {
      println("キャリブレーションデータは削除されました.次回の起動時に再キャリブレーションが行われます.");
      // 重置校准状态
      normalization.isCalibrated = false;
      normalization.calibrationArousal.clear();
      normalization.calibrationValence.clear();
      calibrationStartTime = System.currentTimeMillis();
      println("再キャリブレーションが開始されました。しばらく静かにしておいてください.");
    } else {
      println("✗削除に失敗しました.");
    }
  }
}
