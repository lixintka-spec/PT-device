// Turns a procedural limb into a normalized surface point cloud.

import { buildArm, buildLeg } from './anatomy.js';
import { blueNoise, mulberry32, polygonize, projectToSurface, sampleCandidates } from './sampler.js';

const MAX_POINTS = 60000; // matches the density slider's max
const CANDIDATES = MAX_POINTS * 5;
const BUILDERS = { arm: buildArm, leg: buildLeg };
const prepared = new Map();

function smoothstep(t) {
  const c = Math.min(Math.max(t, 0), 1);
  return c * c * (3 - 2 * c);
}

// Expensive part (mesh + candidate pool) is cached per limb; changing the
// density only re-runs the Poisson selection and projection.
function prepare(name) {
  if (prepared.has(name)) return prepared.get(name);
  const model = BUILDERS[name]();
  const { cutY, fadeLength, cell } = model;
  const bounds = { min: model.bounds.min, max: [model.bounds.max[0], Math.min(model.bounds.max[1], cutY), model.bounds.max[2]] };
  const mesh = polygonize(model.sdf, bounds, cell);

  // Drop the flat cap at the cut and thin points out as they approach it.
  const fade = (y) => smoothstep((cutY - y) / fadeLength);
  const keep = (x, y) => (y > cutY - cell * 1.5 ? 0 : fade(y) ** 2);
  const { points, area } = sampleCandidates(mesh, CANDIDATES, mulberry32(name.length * 7919), keep);

  // Fixed normalization per limb: centred, 2 units tall.
  const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < points.length; i += 3) {
    for (let a = 0; a < 3; a++) {
      min[a] = Math.min(min[a], points[i + a]);
      max[a] = Math.max(max[a], points[i + a]);
    }
  }
  const center = [(min[0] + max[0]) / 2, (min[1] + max[1]) / 2, (min[2] + max[2]) / 2];
  const scale = 2 / (max[1] - min[1]);

  const entry = { model, candidates: points, area, fade, center, scale };
  prepared.set(name, entry);
  return entry;
}

export function makeCloud(name, count) {
  const { model, candidates, area, fade, center, scale } = prepare(name);
  const picked = blueNoise(candidates, area, count);
  const { positions, normals } = projectToSurface(model.sdf, candidates, picked);
  const alpha = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    alpha[i] = fade(positions[i * 3 + 1]);
    for (let a = 0; a < 3; a++) positions[i * 3 + a] = (positions[i * 3 + a] - center[a]) * scale;
  }
  return sortForMorph({ positions, normals, alpha });
}

// Order points by height bands, then by angle around each band's centre.
// Two clouds sorted this way pair index i with a nearby-ish point i,
// so morphing between them reads as a reshaping rather than chaos.
function sortForMorph({ positions, normals, alpha }) {
  const count = alpha.length;
  const order = Array.from({ length: count }, (_, i) => i);
  order.sort((a, b) => positions[a * 3 + 1] - positions[b * 3 + 1]);
  const band = Math.max(64, Math.floor(count / 150));
  for (let start = 0; start < count; start += band) {
    const slice = order.slice(start, start + band);
    let cx = 0, cz = 0;
    for (const i of slice) { cx += positions[i * 3]; cz += positions[i * 3 + 2]; }
    cx /= slice.length; cz /= slice.length;
    const angle = (i) => Math.atan2(positions[i * 3 + 2] - cz, positions[i * 3] - cx);
    slice.sort((a, b) => angle(a) - angle(b));
    for (let k = 0; k < slice.length; k++) order[start + k] = slice[k];
  }
  const out = { positions: new Float32Array(count * 3), normals: new Float32Array(count * 3), alpha: new Float32Array(count) };
  order.forEach((src, dst) => {
    out.positions.set(positions.subarray(src * 3, src * 3 + 3), dst * 3);
    out.normals.set(normals.subarray(src * 3, src * 3 + 3), dst * 3);
    out.alpha[dst] = alpha[src];
  });
  return out;
}
