// ===== 画面上方的简短通知 =====
String toastMsg = "";
int toastUntil = 0;

void showToast(String msg) {
  showToast(msg, 4000);
}

void showToast(String msg, int durationMs) {
  toastMsg = msg;
  toastUntil = millis() + durationMs;
  println("［通知］" + msg);
}

void drawToast() {
  if (millis() > toastUntil || toastMsg.length() == 0) return;
  float a = constrain((toastUntil - millis()) / 400.0f, 0, 1);
  textSize(13);
  float w = textWidth(toastMsg) + 36;
  float x = (width - w) / 2, y = 64;
  noStroke();
  fill(30, 230 * a);
  rect(x, y, w, 34, 17);
  fill(230, 255 * a);
  textAlign(CENTER, CENTER);
  text(toastMsg, width / 2, y + 17);
  textAlign(LEFT);
}
