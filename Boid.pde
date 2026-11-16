// ===== Boid类 =====
final int BOID_TRAIL_MAX = 10;

// 鱼的配色（实时画面・回放・光绘共用）
final float BOID_WARM_R = 255, BOID_WARM_G = 102, BOID_WARM_B = 204;   // 粉色（愉悦度高）
final float BOID_COLD_R = 102, BOID_COLD_G = 204, BOID_COLD_B = 255;   // 天蓝（愉悦度低）
final float BOID_SIZE_MIN = 4.0f;   // 愉悦度 -1 时的粗细（旧 demo 为 2，太细）
final float BOID_SIZE_MAX = 9.0f;   // 愉悦度 +1 时的粗细

// 同一时刻所有鱼相同的粗细：愉悦度越低越细
float boidSize(float v) {
  return map(constrain(v, -1, 1), -1, 1, BOID_SIZE_MIN, BOID_SIZE_MAX);
}
class Boid {
  PVector position, velocity, acceleration;
  int id = 0;   // 模拟内的个体编号
  // 回放时一帧内经过的位置（Replay.pde 用来画连续的身体）
  float[] trX = new float[BOID_TRAIL_MAX], trY = new float[BOID_TRAIL_MAX];
  int trN = 0;

  float maxSpeed = 4;
  float maxForce = 0.2;

  float attractStrength = 0.5f;
  float jitterStrength = 0.02f;

  float cohesionRadius = 50f;
  float separateRadius = 30f;

  // 光绘・回放用的专用随机数（为 null 时使用全局随机数 = 实时画面，与以前相同）
  java.util.Random rng = null;
  // 光绘・回放用的虚拟画布尺寸（0 = 使用屏幕尺寸 = 实时画面，与以前相同）
  float worldW = 0, worldH = 0;

  Boid(float x, float y) {
    position = new PVector(x, y);
    velocity = PVector.random2D();
    velocity.setMag(random(2, 4));
    acceleration = new PVector();
  }

  // 光绘・回放用：所有随机数都来自传入的 rng，同一个种子 → 完全相同的运动
  Boid(float x, float y, java.util.Random r, float worldW, float worldH) {
    rng = r;
    this.worldW = worldW;
    this.worldH = worldH;
    position = new PVector(x, y);
    velocity = strictFromAngle(r.nextFloat() * TWO_PI);
    velocity.setMag(2 + r.nextFloat() * 2);
    acceleration = new PVector();
  }

  void applyForce(PVector f) { acceleration.add(f); }

  void seek(PVector t) {
    PVector desired = PVector.sub(t, position);
    float d = desired.mag();
    if (d < 1e-6f) return;

    desired.setMag(maxSpeed);
    PVector steer = PVector.sub(desired, velocity);
    steer.limit(maxForce);
    steer.mult(attractStrength);
    applyForce(steer);
  }

  void flock(ArrayList<Boid> boids, float aW, float cW, float sW) {
    PVector a = align(boids).mult(aW);
    PVector c = cohere(boids).mult(cW);
    PVector s = separate(boids).mult(sW);
    applyForce(a);
    applyForce(c);
    applyForce(s);
  }

  void update() {
    position.add(velocity);
    velocity.add(acceleration);

    if (jitterStrength > 0) {
      if (rng != null) velocity.add(strictFromAngle(rng.nextFloat() * TWO_PI).mult(jitterStrength));
      else velocity.add(PVector.random2D().mult(jitterStrength));
    }

    velocity.limit(maxSpeed);
    acceleration.mult(0);
    edges();
  }

  void show(float v, float a) {
    float speedFactor = velocity.mag() / maxSpeed;

    color cold = color(150, 180, 255);
    color warm = color(255, 160, 60);
    color base = lerpColor(cold, warm, (v + 1) * 0.5f);

    float alphaNow = map(a, -1, 1, 120, 220);

    float r = map(speedFactor, 0, 1, 3, 8);

    noStroke();
    fill(base, alphaNow);
    ellipse(position.x, position.y, r, r);
  }

  // 与 show() 相同的外观，但画到指定图层上（全屏实时模式使用）
  // 画法（来自 SystemModified260601 的 demo）：
  //   颜色：愉悦度低 → 天蓝，高 → 粉色；游得越快越接近白色（最多 80%）→ 快的鱼有发白的亮芯
  //   粗细：同一时刻所有鱼相同，随愉悦度变化（心情变差 → 变细；最细 BOID_SIZE_MIN）
  //   透明度固定 200
  void showOn(PGraphics pg, float v, float a) {
    pg.noStroke();
    pg.fill(boidColor(v), 200);
    float s = boidSize(v);
    pg.ellipse(position.x, position.y, s, s);
  }

  int boidColor(float v) {
    float t = constrain((v + 1) * 0.5f, 0, 1);
    int base = color(lerp(BOID_COLD_R, BOID_WARM_R, t), lerp(BOID_COLD_G, BOID_WARM_G, t), lerp(BOID_COLD_B, BOID_WARM_B, t));
    float speedRatio = constrain(velocity.mag() / max(maxSpeed, 1e-6f), 0, 1);
    return lerpColor(base, color(255), speedRatio * 0.8f);
  }

  void edges() {
    float w = worldW > 0 ? worldW : width;
    float h = worldH > 0 ? worldH : height;
    if (position.x > w) position.x = 0;
    if (position.x < 0) position.x = w;
    if (position.y > h) position.y = 0;
    if (position.y < 0) position.y = h;
  }

  // 与 PVector.fromAngle 相同，但用 StrictMath：在任何电脑（Intel / Apple Silicon 等）上结果逐位相同
  PVector strictFromAngle(float a) {
    return new PVector((float)StrictMath.cos(a), (float)StrictMath.sin(a));
  }

  PVector align(ArrayList<Boid> boids) {
    float perception = 50;
    PVector steering = new PVector();
    int count = 0;
    for (Boid other : boids) {
      float d = PVector.dist(position, other.position);
      if (other != this && d < perception) {
        steering.add(other.velocity);
        count++;
      }
    }
    if (count > 0) {
      steering.div(count);
      steering.setMag(maxSpeed);
      steering.sub(velocity);
      steering.limit(maxForce);
    }
    return steering;
  }

  PVector cohere(ArrayList<Boid> boids) {
    float perception = cohesionRadius;
    PVector steering = new PVector();
    int count = 0;
    for (Boid other : boids) {
      float d = PVector.dist(position, other.position);
      if (other != this && d < perception) {
        steering.add(other.position);
        count++;
      }
    }
    if (count > 0) {
      steering.div(count);
      steering.sub(position);
      steering.setMag(maxSpeed);
      steering.sub(velocity);
      steering.limit(maxForce);
    }
    return steering;
  }

  PVector separate(ArrayList<Boid> boids) {
    float perception = separateRadius;
    PVector steering = new PVector();
    int count = 0;
    for (Boid other : boids) {
      float d = PVector.dist(position, other.position);
      if (other != this && d < perception) {
        PVector diff = PVector.sub(position, other.position);
        diff.div(d * d);
        steering.add(diff);
        count++;
      }
    }
    if (count > 0) {
      steering.div(count);
      steering.setMag(maxSpeed);
      steering.sub(velocity);
      steering.limit(maxForce);
    }
    return steering;
  }
}
