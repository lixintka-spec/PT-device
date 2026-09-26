// Tiny signed-distance-field toolkit used to sculpt the anatomy procedurally.
// Shapes are built from round cones, ellipsoids and rounded boxes that are
// blended together with a polynomial smooth-min, then clipped by planes.

const DEG = Math.PI / 180;

function rotationMatrix([rx, ry, rz]) {
  // R = Rz * Ry * Rx (row-major). We store its transpose to go world -> local.
  const cx = Math.cos(rx * DEG), sx = Math.sin(rx * DEG);
  const cy = Math.cos(ry * DEG), sy = Math.sin(ry * DEG);
  const cz = Math.cos(rz * DEG), sz = Math.sin(rz * DEG);
  const r00 = cz * cy, r01 = cz * sy * sx - sz * cx, r02 = cz * sy * cx + sz * sx;
  const r10 = sz * cy, r11 = sz * sy * sx + cz * cx, r12 = sz * sy * cx - cz * sx;
  const r20 = -sy, r21 = cy * sx, r22 = cy * cx;
  return [r00, r10, r20, r01, r11, r21, r02, r12, r22];
}

function smin(a, b, k) {
  if (k <= 0) return Math.min(a, b);
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return Math.min(a, b) - h * h * k * 0.25;
}

function smax(a, b, k) {
  return -smin(-a, -b, k);
}

// Round cone between a (radius r1) and b (radius r2) — Inigo Quilez.
function roundCone(a, b, r1, r2) {
  const bax = b[0] - a[0], bay = b[1] - a[1], baz = b[2] - a[2];
  const l2 = bax * bax + bay * bay + baz * baz;
  const rr = r1 - r2;
  const a2 = l2 - rr * rr;
  const il2 = 1 / l2;
  return (x, y, z) => {
    const pax = x - a[0], pay = y - a[1], paz = z - a[2];
    const py = pax * bax + pay * bay + paz * baz;
    const pz = py - l2;
    const qx = pax * l2 - bax * py, qy = pay * l2 - bay * py, qz = paz * l2 - baz * py;
    const x2 = qx * qx + qy * qy + qz * qz;
    const y2 = py * py * l2;
    const z2 = pz * pz * l2;
    const k = Math.sign(rr) * rr * rr * x2;
    if (Math.sign(pz) * a2 * z2 > k) return Math.sqrt(x2 + z2) * il2 - r2;
    if (Math.sign(py) * a2 * y2 < k) return Math.sqrt(x2 + y2) * il2 - r1;
    return (Math.sqrt(x2 * a2 * il2) + py * rr) * il2 - r1;
  };
}

function ellipsoid(c, r, rot) {
  const m = rotationMatrix(rot);
  const [rx, ry, rz] = r;
  return (x, y, z) => {
    const px = x - c[0], py = y - c[1], pz = z - c[2];
    const lx = m[0] * px + m[1] * py + m[2] * pz;
    const ly = m[3] * px + m[4] * py + m[5] * pz;
    const lz = m[6] * px + m[7] * py + m[8] * pz;
    const ax = lx / rx, ay = ly / ry, az = lz / rz;
    const k0 = Math.sqrt(ax * ax + ay * ay + az * az);
    const bx = ax / rx, by = ay / ry, bz = az / rz;
    const k1 = Math.sqrt(bx * bx + by * by + bz * bz);
    return k1 > 1e-9 ? (k0 * (k0 - 1)) / k1 : -Math.min(rx, ry, rz);
  };
}

function roundBox(c, half, round, rot) {
  const m = rotationMatrix(rot);
  const hx = half[0] - round, hy = half[1] - round, hz = half[2] - round;
  return (x, y, z) => {
    const px = x - c[0], py = y - c[1], pz = z - c[2];
    const qx = Math.abs(m[0] * px + m[1] * py + m[2] * pz) - hx;
    const qy = Math.abs(m[3] * px + m[4] * py + m[5] * pz) - hy;
    const qz = Math.abs(m[6] * px + m[7] * py + m[8] * pz) - hz;
    const ox = Math.max(qx, 0), oy = Math.max(qy, 0), oz = Math.max(qz, 0);
    return Math.sqrt(ox * ox + oy * oy + oz * oz) + Math.min(Math.max(qx, qy, qz), 0) - round;
  };
}

export class ShapeBuilder {
  constructor() {
    this.prims = [];
    this.planes = [];
  }

  // Each primitive keeps a bounding sphere so far-away evaluations are skipped.
  // `box` is a tight [min, max] AABB used for the sampling grid.
  #add(fn, cx, cy, cz, radius, k, box) {
    this.prims.push({ fn, cx, cy, cz, br: radius, k, box });
    return this;
  }

  cone(a, b, r1, r2, k = 0.02) {
    const cx = (a[0] + b[0]) / 2, cy = (a[1] + b[1]) / 2, cz = (a[2] + b[2]) / 2;
    const half = Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]) / 2;
    const r = Math.max(r1, r2);
    const box = [0, 1, 2].map((i) => [Math.min(a[i], b[i]) - r, Math.max(a[i], b[i]) + r]);
    return this.#add(roundCone(a, b, r1, r2), cx, cy, cz, half + r, k, box);
  }

  // Polyline of round cones: points[i] with radii[i].
  chain(points, radii, k = 0.01) {
    for (let i = 0; i < points.length - 1; i++) {
      this.cone(points[i], points[i + 1], radii[i], radii[i + 1], k);
    }
    return this;
  }

  ellipsoid(c, r, rot = [0, 0, 0], k = 0.02) {
    const m = rotationMatrix(rot);
    // Exact AABB of a rotated ellipsoid: sqrt(sum_j (R_ij r_j)^2) per axis.
    const box = c.map((v, i) => {
      const e = Math.hypot(m[i] * r[0], m[i + 3] * r[1], m[i + 6] * r[2]);
      return [v - e, v + e];
    });
    return this.#add(ellipsoid(c, r, rot), c[0], c[1], c[2], Math.max(...r), k, box);
  }

  box(c, half, round, rot = [0, 0, 0], k = 0.02) {
    const m = rotationMatrix(rot);
    const box = c.map((v, i) => {
      const e = Math.abs(m[i] * half[0]) + Math.abs(m[i + 3] * half[1]) + Math.abs(m[i + 6] * half[2]);
      return [v - e, v + e];
    });
    return this.#add(roundBox(c, half, round, rot), c[0], c[1], c[2], Math.hypot(...half), k, box);
  }

  // Keep the half-space where dot(n, p) <= offset.
  clip(normal, offset, k = 0) {
    const l = Math.hypot(...normal);
    this.planes.push({ nx: normal[0] / l, ny: normal[1] / l, nz: normal[2] / l, o: offset / l, k });
    return this;
  }

  build() {
    const prims = this.prims;
    const planes = this.planes;
    const n = prims.length;

    const sdf = (x, y, z) => {
      let d = 1e9;
      for (let i = 0; i < n; i++) {
        const p = prims[i];
        const dx = x - p.cx, dy = y - p.cy, dz = z - p.cz;
        const lowerBound = Math.sqrt(dx * dx + dy * dy + dz * dz) - p.br;
        if (lowerBound >= d + p.k) continue;
        d = smin(d, p.fn(x, y, z), p.k);
      }
      for (let i = 0; i < planes.length; i++) {
        const q = planes[i];
        d = smax(d, q.nx * x + q.ny * y + q.nz * z - q.o, q.k);
      }
      return d;
    };

    const min = [Infinity, Infinity, Infinity];
    const max = [-Infinity, -Infinity, -Infinity];
    for (const p of prims) {
      for (let a = 0; a < 3; a++) {
        min[a] = Math.min(min[a], p.box[a][0]);
        max[a] = Math.max(max[a], p.box[a][1]);
      }
    }
    return { sdf, bounds: { min, max } };
  }
}

// Tetrahedral finite-difference gradient (4 evaluations).
export function gradient(sdf, x, y, z, out, h = 1e-4) {
  const a = sdf(x + h, y - h, z - h);
  const b = sdf(x - h, y - h, z + h);
  const c = sdf(x - h, y + h, z - h);
  const d = sdf(x + h, y + h, z + h);
  out[0] = a - b - c + d;
  out[1] = -a - b + c + d;
  out[2] = -a + b - c + d;
  const l = Math.hypot(out[0], out[1], out[2]) || 1;
  out[0] /= l; out[1] /= l; out[2] /= l;
  return out;
}
