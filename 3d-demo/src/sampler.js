// Mesh -> surface point cloud pipeline.
//
//   SDF  --surface nets-->  triangle mesh  --area-weighted sampling-->  candidates
//   candidates  --Poisson-disk selection-->  evenly spaced points  --project-->  surface + normals
//
// Blue-noise (Poisson-disk) spacing is what makes the result read as crisp
// stippling instead of the clumpy look of plain random sampling.

import { gradient } from './sdf.js';

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Naive surface nets: one vertex per sign-changing cell, one quad per
// sign-changing grid edge. Returns an indexed triangle mesh.
export function polygonize(sdf, bounds, cell) {
  const pad = cell * 2;
  const ox = bounds.min[0] - pad, oy = bounds.min[1] - pad, oz = bounds.min[2] - pad;
  const nx = Math.ceil((bounds.max[0] - bounds.min[0] + 2 * pad) / cell) + 1;
  const ny = Math.ceil((bounds.max[1] - bounds.min[1] + 2 * pad) / cell) + 1;
  const nz = Math.ceil((bounds.max[2] - bounds.min[2] + 2 * pad) / cell) + 1;

  // Coarse pass first: fine nodes far from the surface just inherit the
  // nearest coarse value (the SDF is ~1-Lipschitz, so their sign is safe).
  const F = 4;
  const gx = Math.ceil((nx - 1) / F) + 1, gy = Math.ceil((ny - 1) / F) + 1, gz = Math.ceil((nz - 1) / F) + 1;
  const coarse = new Float32Array(gx * gy * gz);
  for (let k = 0; k < gz; k++) {
    for (let j = 0; j < gy; j++) {
      for (let i = 0; i < gx; i++) coarse[i + gx * (j + gy * k)] = sdf(ox + i * F * cell, oy + j * F * cell, oz + k * F * cell);
    }
  }
  const safe = (F / 2) * Math.sqrt(3) * cell + 2 * cell;

  const vals = new Float32Array(nx * ny * nz);
  const idx = (i, j, k) => i + nx * (j + ny * k);
  for (let k = 0; k < nz; k++) {
    const z = oz + k * cell;
    const ck = Math.round(k / F);
    for (let j = 0; j < ny; j++) {
      const y = oy + j * cell;
      const cj = Math.round(j / F);
      for (let i = 0; i < nx; i++) {
        const c = coarse[Math.round(i / F) + gx * (cj + gy * ck)];
        vals[idx(i, j, k)] = Math.abs(c) > safe ? c : sdf(ox + i * cell, y, z);
      }
    }
  }

  const cnx = nx - 1, cny = ny - 1, cnz = nz - 1;
  const cellVert = new Int32Array(cnx * cny * cnz).fill(-1);
  const verts = [];
  const corner = new Float32Array(8);
  const CORNERS = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]];
  const EDGES = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];

  for (let k = 0; k < cnz; k++) {
    for (let j = 0; j < cny; j++) {
      for (let i = 0; i < cnx; i++) {
        let mask = 0;
        for (let c = 0; c < 8; c++) {
          const v = vals[idx(i + CORNERS[c][0], j + CORNERS[c][1], k + CORNERS[c][2])];
          corner[c] = v;
          if (v < 0) mask |= 1 << c;
        }
        if (mask === 0 || mask === 255) continue;
        let sx = 0, sy = 0, sz = 0, count = 0;
        for (const [a, b] of EDGES) {
          const va = corner[a], vb = corner[b];
          if ((va < 0) === (vb < 0)) continue;
          const t = va / (va - vb);
          sx += CORNERS[a][0] + t * (CORNERS[b][0] - CORNERS[a][0]);
          sy += CORNERS[a][1] + t * (CORNERS[b][1] - CORNERS[a][1]);
          sz += CORNERS[a][2] + t * (CORNERS[b][2] - CORNERS[a][2]);
          count++;
        }
        cellVert[i + cnx * (j + cny * k)] = verts.length / 3;
        verts.push(ox + (i + sx / count) * cell, oy + (j + sy / count) * cell, oz + (k + sz / count) * cell);
      }
    }
  }

  const tris = [];
  const cv = (i, j, k) => cellVert[i + cnx * (j + cny * k)];
  const quad = (a, b, c, d) => {
    if (a < 0 || b < 0 || c < 0 || d < 0) return;
    tris.push(a, b, c, a, c, d);
  };
  for (let k = 1; k < cnz; k++) {
    for (let j = 1; j < cny; j++) {
      for (let i = 1; i < cnx; i++) {
        const s = vals[idx(i, j, k)] < 0;
        if (s !== vals[idx(i + 1, j, k)] < 0) quad(cv(i, j - 1, k - 1), cv(i, j, k - 1), cv(i, j, k), cv(i, j - 1, k));
        if (s !== vals[idx(i, j + 1, k)] < 0) quad(cv(i - 1, j, k - 1), cv(i, j, k - 1), cv(i, j, k), cv(i - 1, j, k));
        if (s !== vals[idx(i, j, k + 1)] < 0) quad(cv(i - 1, j - 1, k), cv(i, j - 1, k), cv(i, j, k), cv(i - 1, j, k));
      }
    }
  }

  return { vertices: new Float32Array(verts), indices: new Uint32Array(tris) };
}

// Uniform (area-weighted) random points on a triangle mesh.
// `keep(x, y, z)` returns an acceptance probability, used to dissolve cut edges.
export function sampleCandidates(mesh, count, rand, keep) {
  const { vertices: V, indices: I } = mesh;
  const triCount = I.length / 3;
  const cdf = new Float64Array(triCount);
  let area = 0;
  for (let t = 0; t < triCount; t++) {
    const a = I[t * 3] * 3, b = I[t * 3 + 1] * 3, c = I[t * 3 + 2] * 3;
    const ux = V[b] - V[a], uy = V[b + 1] - V[a + 1], uz = V[b + 2] - V[a + 2];
    const vx = V[c] - V[a], vy = V[c + 1] - V[a + 1], vz = V[c + 2] - V[a + 2];
    const cx = uy * vz - uz * vy, cy = uz * vx - ux * vz, cz = ux * vy - uy * vx;
    area += 0.5 * Math.sqrt(cx * cx + cy * cy + cz * cz);
    cdf[t] = area;
  }

  const out = new Float32Array(count * 3);
  let n = 0, keptArea = 0, tries = 0;
  while (n < count && tries < count * 20) {
    tries++;
    const r = rand() * area;
    let lo = 0, hi = triCount - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (cdf[mid] < r) lo = mid + 1; else hi = mid;
    }
    let u = rand(), v = rand();
    if (u + v > 1) { u = 1 - u; v = 1 - v; }
    const a = I[lo * 3] * 3, b = I[lo * 3 + 1] * 3, c = I[lo * 3 + 2] * 3;
    const x = V[a] + u * (V[b] - V[a]) + v * (V[c] - V[a]);
    const y = V[a + 1] + u * (V[b + 1] - V[a + 1]) + v * (V[c + 1] - V[a + 1]);
    const z = V[a + 2] + u * (V[b + 2] - V[a + 2]) + v * (V[c + 2] - V[a + 2]);
    const p = keep(x, y, z);
    keptArea += p;
    if (rand() > p) continue;
    out[n * 3] = x; out[n * 3 + 1] = y; out[n * 3 + 2] = z;
    n++;
  }
  // Effective (density-weighted) surface area, used to size the Poisson radius.
  return { points: out.subarray(0, n * 3), area: (area * keptArea) / tries };
}

// Greedy dart throwing over pre-generated candidates, using a hashed grid.
function poissonSelect(points, radius, limit) {
  const count = points.length / 3;
  const TABLE = 1 << 20;
  const head = new Int32Array(TABLE).fill(-1);
  const next = new Int32Array(count);
  const inv = 1 / radius;
  const r2 = radius * radius;
  const hash = (i, j, k) => ((Math.imul(i, 73856093) ^ Math.imul(j, 19349663) ^ Math.imul(k, 83492791)) >>> 0) & (TABLE - 1);
  const accepted = [];

  for (let p = 0; p < count && accepted.length < limit; p++) {
    const x = points[p * 3], y = points[p * 3 + 1], z = points[p * 3 + 2];
    const ci = Math.floor(x * inv), cj = Math.floor(y * inv), ck = Math.floor(z * inv);
    let ok = true;
    search: for (let dk = -1; dk <= 1; dk++) {
      for (let dj = -1; dj <= 1; dj++) {
        for (let di = -1; di <= 1; di++) {
          for (let q = head[hash(ci + di, cj + dj, ck + dk)]; q !== -1; q = next[q]) {
            const dx = points[q * 3] - x, dy = points[q * 3 + 1] - y, dz = points[q * 3 + 2] - z;
            if (dx * dx + dy * dy + dz * dz < r2) { ok = false; break search; }
          }
        }
      }
    }
    if (!ok) continue;
    const h = hash(ci, cj, ck);
    next[p] = head[h];
    head[h] = p;
    accepted.push(p);
  }
  return accepted;
}

// Pick exactly `count` well-spaced points out of the candidates.
export function blueNoise(candidates, area, count) {
  // Maximal Poisson-disk sets cover ~55% of the plane with r/2 discs,
  // so N ≈ 0.7 · A / r². Aim slightly dense, then correct once.
  let radius = Math.sqrt((0.7 * area) / count) * 0.97;
  let picked = poissonSelect(candidates, radius, Infinity);
  if (picked.length < count || picked.length > count * 1.15) {
    radius *= Math.sqrt(picked.length / count) * 0.985;
    picked = poissonSelect(candidates, radius, Infinity);
  }
  if (picked.length > count) return picked.slice(0, count);
  // Not enough room: top up with leftover candidates (rare, tiny amounts).
  const used = new Uint8Array(candidates.length / 3);
  for (const p of picked) used[p] = 1;
  for (let p = 0; picked.length < count && p < used.length; p++) if (!used[p]) picked.push(p);
  return picked;
}

// Snap points onto the exact SDF surface and read normals from its gradient.
export function projectToSurface(sdf, candidates, picked) {
  const n = picked.length;
  const positions = new Float32Array(n * 3);
  const normals = new Float32Array(n * 3);
  const g = [0, 0, 0];
  for (let i = 0; i < n; i++) {
    const p = picked[i] * 3;
    let x = candidates[p], y = candidates[p + 1], z = candidates[p + 2];
    for (let it = 0; it < 3; it++) {
      const d = sdf(x, y, z);
      if (Math.abs(d) < 1e-6) break;
      gradient(sdf, x, y, z, g);
      x -= d * g[0]; y -= d * g[1]; z -= d * g[2];
    }
    gradient(sdf, x, y, z, g);
    positions.set([x, y, z], i * 3);
    normals.set(g, i * 3);
  }
  return { positions, normals };
}
