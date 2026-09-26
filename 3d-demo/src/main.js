import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { createPointMaterial } from './pointMaterial.js';
import './style.css';

const MORPH_SECONDS = 2.2;
const FOV = 30;

const canvas = document.querySelector('#scene');
const statusEl = document.querySelector('#status');
const modelReadout = document.querySelector('#readout-model');
const pointsReadout = document.querySelector('#readout-points');
const switchEl = document.querySelector('.switch');
const buttons = [...document.querySelectorAll('[data-model]')];
const density = document.querySelector('#density');
const densityValue = document.querySelector('#density-value');

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

let renderer;
try {
  renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true });
} catch {
  statusEl.textContent = 'WebGL is not available in this browser.';
  throw new Error('WebGL unavailable');
}
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setClearColor(0x000000, 0);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(FOV, 1, 0.1, 50);
camera.position.set(3.3, 0.5, 4.5);

const controls = new OrbitControls(camera, canvas);
// Aim slightly below centre so the limb sits above the bottom controls.
controls.target.set(0, -0.13, 0);
controls.enableDamping = true;
controls.dampingFactor = 0.06;
controls.enablePan = false;
controls.minDistance = 2.2;
controls.maxDistance = 10;
controls.autoRotate = !reducedMotion;
controls.autoRotateSpeed = 1;

const material = createPointMaterial();
if (reducedMotion) material.uniforms.uScatter.value = 0;
let points = null;

// --- state -----------------------------------------------------------------

const state = {
  model: 'leg', // target model
  morph: 1, // 0 = arm, 1 = leg
  reveal: 0,
  count: Number(density.value),
};

function setModel(model) {
  state.model = model;
  modelReadout.textContent = model === 'arm' ? 'Arm' : 'Leg';
  switchEl.dataset.active = model;
  for (const b of buttons) b.setAttribute('aria-pressed', String(b.dataset.model === model));
}

buttons.forEach((b) => b.addEventListener('click', () => setModel(b.dataset.model)));
window.addEventListener('keydown', (e) => {
  // Focused controls keep their native keyboard behaviour.
  if (e.target.closest?.('button, input')) return;
  if (e.code === 'Space') {
    e.preventDefault();
    setModel(state.model === 'arm' ? 'leg' : 'arm');
  } else if (e.key === 'a' || e.key === 'A') setModel('arm');
  else if (e.key === 'l' || e.key === 'L') setModel('leg');
});

// --- point cloud generation (web worker) -----------------------------------

const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
let requestId = 0;

function requestClouds(count) {
  requestId++;
  statusEl.textContent = points ? 'Resampling…' : 'Sampling surface…';
  statusEl.hidden = false;
  worker.postMessage({ id: requestId, count });
}

worker.onmessage = ({ data }) => {
  if (data.id !== requestId) return;
  const { arm, leg } = data.clouds;
  const count = data.count;

  const rand = new Float32Array(count * 4);
  let seed = 1;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
  for (let i = 0; i < count; i++) {
    // Morph delay sweeps from the bottom up, loosened with some randomness.
    const height = (leg.positions[i * 3 + 1] + arm.positions[i * 3 + 1]) / 4 + 0.5;
    rand.set([rnd(), rnd(), 0.8 * height + 0.2 * rnd(), rnd()], i * 4);
  }
  const alpha = new Float32Array(count * 2);
  for (let i = 0; i < count; i++) {
    alpha[i * 2] = arm.alpha[i];
    alpha[i * 2 + 1] = leg.alpha[i];
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(arm.positions, 3));
  geometry.setAttribute('normal', new THREE.BufferAttribute(arm.normals, 3));
  geometry.setAttribute('aLegPosition', new THREE.BufferAttribute(leg.positions, 3));
  geometry.setAttribute('aLegNormal', new THREE.BufferAttribute(leg.normals, 3));
  geometry.setAttribute('aAlpha', new THREE.BufferAttribute(alpha, 2));
  geometry.setAttribute('aRand', new THREE.BufferAttribute(rand, 4));

  if (points) {
    points.geometry.dispose();
    points.geometry = geometry;
  } else {
    points = new THREE.Points(geometry, material);
    points.frustumCulled = false;
    scene.add(points);
  }

  // Keep the on-screen dot size proportional to the spacing between points.
  material.uniforms.uSize.value = 0.7 * Math.sqrt(1.7 / count);
  pointsReadout.textContent = count.toLocaleString('en-US');
  statusEl.hidden = true;
};

let densityTimer;
density.addEventListener('input', () => {
  state.count = Number(density.value);
  densityValue.textContent = `${Math.round(state.count / 1000)}k`;
  clearTimeout(densityTimer);
  densityTimer = setTimeout(() => requestClouds(state.count), 180);
});

// --- render loop ------------------------------------------------------------

function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  // Narrow screens: pull back so the full limb stays in frame.
  camera.fov = w / h < 0.75 ? FOV * 1.25 : FOV;
  camera.updateProjectionMatrix();
  const bufferHeight = renderer.getDrawingBufferSize(new THREE.Vector2()).y;
  material.uniforms.uScale.value = bufferHeight / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2));
}
window.addEventListener('resize', resize);
resize();

const timer = new THREE.Timer();
timer.connect(document);
renderer.setAnimationLoop((timestamp) => {
  timer.update(timestamp);
  const dt = Math.min(timer.getDelta(), 0.05);
  const target = state.model === 'leg' ? 1 : 0;
  const step = dt / (reducedMotion ? 0.6 : MORPH_SECONDS);
  state.morph += THREE.MathUtils.clamp(target - state.morph, -step, step);
  if (points) state.reveal = Math.min(1, state.reveal + dt / 1.4);

  const u = material.uniforms;
  u.uMorph.value = state.morph;
  u.uReveal.value = state.reveal * state.reveal * (3 - 2 * state.reveal);
  u.uTime.value = timer.getElapsed();
  u.uCamDist.value = camera.position.length();

  controls.update(dt);
  renderer.render(scene, camera);
});

setModel(state.model);
densityValue.textContent = `${Math.round(state.count / 1000)}k`;
requestClouds(state.count);
