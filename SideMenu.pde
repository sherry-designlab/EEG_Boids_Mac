// ===== 左侧悬停菜单（三横线图标） =====
// 鼠标移到屏幕左缘或图标上时，菜单从左侧滑出；移开后自动收回。
// 两个模式：Real-time（实时，启动时默认）与 Gallery（全屏日历画廊）。
// galleryOpen = false → Real-time 模式；true → Gallery 模式。

float menuSlide = 0;              // 0 = 收起，1 = 完全拉出
float MENU_W = 200;               // 菜单宽度
float MENU_HOT_ZONE = 40;         // 鼠标距左缘多少px以内时拉出
float menuIconX = 18, menuIconY = 18, menuIconW = 26, menuIconH = 20;
float menuBtnY = 80, menuBtnH = 40, menuBtnGap = 10;
String[] MENU_ITEMS = { "Real-time", "Gallery", "Data Management" };
boolean menuMouseSeen = false;    // 鼠标移动过之后才响应（避免启动时 mouseX=0 误触发）

boolean menuShouldOpen() {
  if (!menuMouseSeen || replayActive) return false;
  boolean overIcon = mouseX >= menuIconX - 8 && mouseX <= menuIconX + menuIconW + 8
                  && mouseY >= menuIconY - 8 && mouseY <= menuIconY + menuIconH + 8;
  boolean overEdge = mouseX <= MENU_HOT_ZONE;
  boolean overPanel = menuSlide > 0.05f && mouseX <= MENU_W * menuSlide;
  return overIcon || overEdge || overPanel;
}

// 返回鼠标所在的菜单按钮序号（0 = Real-time, 1 = Gallery），不在按钮上返回 -1
int menuHoveredItem() {
  if (menuSlide < 0.9f) return -1;
  float px = -MENU_W + MENU_W * menuSlide;
  float bx = px + 16, bw = MENU_W - 32;
  if (mouseX < bx || mouseX > bx + bw) return -1;
  for (int i = 0; i < MENU_ITEMS.length; i++) {
    float by = menuBtnY + i * (menuBtnH + menuBtnGap);
    if (mouseY >= by && mouseY <= by + menuBtnH) return i;
  }
  return -1;
}

void drawSideMenu() {
  float targetSlide = menuShouldOpen() ? 1 : 0;
  menuSlide = lerp(menuSlide, targetSlide, 0.2f);
  if (abs(menuSlide - targetSlide) < 0.001f) menuSlide = targetSlide;

  float px = -MENU_W + MENU_W * menuSlide;   // 菜单面板左边界

  if (menuSlide > 0.001f) {
    // 面板
    noStroke();
    fill(18, 235);
    rect(px, 0, MENU_W, height);
    stroke(60);
    strokeWeight(1);
    line(px + MENU_W, 0, px + MENU_W, height);

    // 模式按钮
    float bx = px + 16, bw = MENU_W - 32;
    int hovered = menuHoveredItem();
    for (int i = 0; i < MENU_ITEMS.length; i++) {
      float by = menuBtnY + i * (menuBtnH + menuBtnGap);
      boolean active = (i == 0 && isRealtimeMode()) || (i == 1 && galleryOpen) || (i == 2 && dataOpen);
      noStroke();
      if (active) {
        fill(100, 200, 100, 60);
        rect(bx, by, bw, menuBtnH, 6);
      } else if (hovered == i) {
        fill(255, 30);
        rect(bx, by, bw, menuBtnH, 6);
      }
      if (active) fill(100, 200, 100); else fill(210);
      textSize(15);
      textAlign(LEFT, CENTER);
      text(MENU_ITEMS[i], bx + 14, by + menuBtnH / 2);
    }
  }

  // 三横线图标（始终在最上层）
  stroke(menuSlide > 0.5f ? 230 : 160);
  strokeWeight(3);
  for (int i = 0; i < 3; i++) {
    float y = menuIconY + i * (menuIconH / 2);
    line(menuIconX, y, menuIconX + menuIconW, y);
  }
  noStroke();
  textAlign(LEFT);
}
