// ===== OSC =====
void oscEvent(OscMessage msg) {
  // 收到任何 Muse 数据 → 更新连接判定（见 EEGConnection.pde）
  if (msg.addrPattern().startsWith("/muse/")) markOscReceived();

  if (msg.checkAddrPattern("/muse/elements/alpha_absolute")) {
    for (int i = 0; i < 4; i++) alpha[i] = msg.get(i).floatValue();
  } else if (msg.checkAddrPattern("/muse/elements/beta_absolute")) {
    for (int i = 0; i < 4; i++) beta[i] = msg.get(i).floatValue();
  } else if (msg.checkAddrPattern("/muse/elements/theta_absolute")) {
    for (int i = 0; i < 4; i++) theta[i] = msg.get(i).floatValue();
  } else if (msg.checkAddrPattern("/muse/elements/delta_absolute")) {
    for (int i = 0; i < 4; i++) delta[i] = msg.get(i).floatValue();
  } else if (msg.checkAddrPattern("/muse/elements/gamma_absolute")) {
    for (int i = 0; i < 4; i++) gamma[i] = msg.get(i).floatValue();
  } else if (msg.checkAddrPattern("/muse/elements/horseshoe")) {
    for (int i = 0; i < 4; i++) horseshoe[i] = msg.get(i).floatValue();
    lastHorseshoeMillis = millis();
  } else if (msg.checkAddrPattern("/muse/elements/jaw_clench")) {
    if (msg.get(0).floatValue() > 0.5f) {
      lastJawClenchSec = millis() / 1000.0f;
    }
  }
}
