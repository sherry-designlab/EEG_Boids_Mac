// ===== 鼠标操作 =====
void mousePressed() {
  // 回放窗口打开时：只处理回放窗口（Replay.pde）
  if (replayActive) {
    replayHandleClick();
    return;
  }

  // 纯享模式：只处理看图（右键菜单等）
  if (galleryOpen && viewerEntry != null && viewerPure) {
    viewerHandleClick(mouseX, mouseY);
    return;
  }

  // 菜单：切换 Real-time / Gallery / Data Management
  int item = menuHoveredItem();
  if (item >= 0) closeViewer();
  if (item == 0) {
    galleryOpen = false;
    dataOpen = false;
    return;
  }
  if (item == 1) {
    if (!galleryOpen) {
      galleryOpen = true;
      dataOpen = false;
      refreshGalleryList();
    }
    return;
  }
  if (item == 2) {
    if (!dataOpen) {
      dataOpen = true;
      galleryOpen = false;
      refreshDataList();
    }
    return;
  }

  // 实时模式：右下角的瞑想开始/结束按钮
  if (isRealtimeMode() && mouseOverRecordButton()) {
    if (isRecording || canStartRecording()) toggleRecording();
    return;
  }
  // 画廊：日历、翻页、删除、点击回放
  if (galleryOpen) {
    galleryHandleClick(mouseX, mouseY);
    return;
  }
  // Data Management：导入、选择、再生
  if (dataOpen) {
    dmHandleClick(mouseX, mouseY);
  }
}

void mouseDragged() {
  replayHandleDrag();
}

void mouseReleased() {
  replayHandleRelease();
}

void mouseMoved() {
  menuMouseSeen = true;
}
