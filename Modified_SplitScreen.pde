import oscP5.*;
import netP5.*;
import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.*;

// ===== 全局Boids和目标 =====
ArrayList<Boid> boidsRight;   // 右屏：当前会话
ArrayList<Boid> boidsLeft;    // 左屏：上一次会话
PVector targetRight, targetLeft;
PVector centerRight, centerLeft;

OscP5 oscP5;

float[] delta  = new float[4];
float[] theta  = new float[4];
float[] alpha  = new float[4];
float[] beta   = new float[4];
float[] gamma  = new float[4];

// Raw metrics (physically meaningful)
float arousalRaw = 0.0;
float valenceRaw = 0.0;

// Normalized metrics for UI & mapping [-1, 1]
float arousal = 0.0;
float valence = 0.0;

// state machine
int state = 0;
int stateLeft = 0;  // 左屏的state

// ---- artifact rejection around jaw clench ----
float lastJawClenchSec = -1e9;
float rejectWindowSec = 1.5f;

// ---- downsample to ~1Hz ----
float lastAcceptedSec = -1e9;
float acceptIntervalSec = 1.0f;

// ---- online stats for normalization ----
FixedNormalization normalization = new FixedNormalization();
long calibrationStartTime = 0;

// ---- theta-based switching with hysteresis ----
float thetaOn = 0.46f;
float thetaOff = 0.40f;

// ---- population dynamics ----
int popMin = 120;
int popMax = 520;
float popTickSec = 0.25f;
float lastPopTick = -1e9;

// ===== 新增：历史数据回放 =====
ArrayList<SessionFrame> lastSessionData = new ArrayList<SessionFrame>();  // 上一次的数据
String currentSessionFile = "";
String lastSessionFile = "";
long sessionStartTime = 0;
PrintWriter csvWriter;

int currentFrameInLastSession = 0;  // 上一次数据的当前播放位置
long timeBase = 0;  // 两屏时间对齐的基准
int lastSaveTime = 0;  // 最后保存时间


// 普通窗口（可以拖动改变大小），可以和其他应用同时使用。
// Boids 在固定的虚拟世界（1600×1000）中运动，窗口大小不影响运动（SwarmSim.pde）。
void settings() {
  int w = min(1600, displayWidth - 80);
  int h = round(w * 10 / 16.0f);
  if (h > displayHeight - 120) {
    h = displayHeight - 120;
    w = round(h * 16 / 10.0f);
  }
  size(w, h);
}

void setup() {
  surface.setResizable(true);
  surface.setTitle("EEG Boids（pink）");
  initDataDirs();   // 数据文件夹（DataPaths.pde）：第一次启动时自动搬移旧数据
  
textFont(createFont("PingFang SC", 14));      // 中
textFont(createFont("Hiragino Sans", 14));    // 日
textFont(createFont("Noto Sans CJK SC", 14)); // 通用
  
  // 左屏（旧版的上一次会话回放）已不再使用
  boidsLeft = new ArrayList<Boid>();
  centerLeft = new PVector(LP_WORLD_W / 4, LP_WORLD_H / 2);
  targetLeft = centerLeft.copy();

  // 实时鱼群：从上次结束时的状态继续（BoidControl.pde）
  initLiveSim();

  oscP5 = new OscP5(this, 8000);
  background(0);
  
  // ===== 改动：初始化正规化，尝试加载已保存的校准 =====
  normalization = new FixedNormalization();
  normalization.initialize();  // 检查是否存在calibration.json
  
  // 记录校准开始时间
  calibrationStartTime = System.currentTimeMillis();
  
  // CSV 不再在启动时创建：只有点击"瞑想を始める"（EEG 已连接）时才开始记录（Recording.pde）
  loadPreviousSession();
  sessionStartTime = System.currentTimeMillis();
  timeBase = sessionStartTime;

  runLightPaintingSelfTest();   // 只在控制台输出
}

void draw() {
  // EEG 连接判定（未连接时不计算、不记录、校准暂停）
  updateEEGConnection();

  // 拖尾效果已移到 Boids 图层（SplitScreenView.pde 的 drawBoidLayer），
  // 主画布每帧完整重绘，UI 不再留下残影

  // 更新右屏（当前会话）的EEG数据
  updateEmotion();
  
  // 保存当前数据
  saveCurrentData();
  
  // ===== 实时EEG数据驱动Boids（固定步长：每秒 SIM_HZ 步）=====
  stepLiveSim();
  
  // 绘制全屏Boids、实时折线图、画廊等
  drawSplitScreen();

  // ===== 最上层：校准提示和帮助信息（最后绘制，不被Boids和左屏遮挡） =====
  if (isRealtimeMode()) {
    drawCalibrationOverlay();
    drawHelpInfo();
  }

  // ===== 左侧悬停菜单 =====
  if (!(galleryOpen && viewerPure)) drawSideMenu();   // 纯享模式只显示作品

  // ===== 回放窗口、导入完成处理、通知（最上层） =====
  drawReplay();
  checkImportDone();
  checkDiarySaved();
  drawToast();
}
