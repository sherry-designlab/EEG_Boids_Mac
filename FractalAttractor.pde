// ===== Fractal吸引子 =====
void updateAttractorWithFractal(PVector target, float v, float a) {
  float zx = map((frameCount * 3) % width, 0, width, -2, 2);
  float zy = map((frameCount * 2) % height, 0, height, -2, 2);

  float cx = -0.7 + 0.10f * v;
  float cy = 0.27015 + 0.06f * a;

  int iter = 0;
  while (zx * zx + zy * zy < 4 && iter < 100) {
    float xtemp = zx * zx - zy * zy + cx;
    zy = 2 * zx * zy + cy;
    zx = xtemp;
    iter++;
  }

  target.x = map(zx, -2, 2, 0, width);
  target.y = map(zy, -2, 2, 0, height);
}
