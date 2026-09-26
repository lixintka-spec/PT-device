import * as THREE from 'three';

// Point-sprite shader for the limb clouds.
// - `position`/`normal` hold the arm, `aLegPosition`/`aLegNormal` the leg;
//   uMorph blends between them (0 = arm, 1 = leg) with a per-point delay.
// - Dot size shrinks with camera depth, brightness follows the surface
//   normal: facing the camera = bright, grazing = dim, facing away = faint.

const vertexShader = /* glsl */ `
  uniform float uMorph;
  uniform float uSpread;
  uniform float uScatter;
  uniform float uSize;
  uniform float uScale;
  uniform float uTime;
  uniform float uCamDist;
  uniform float uReveal;

  attribute vec3 aLegPosition;
  attribute vec3 aLegNormal;
  attribute vec2 aAlpha;
  attribute vec4 aRand; // x: size, y: brightness, z: morph delay, w: seed

  varying float vAlpha;
  varying float vSize;

  float easeInOut(float t) {
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5;
  }

  void main() {
    float t = clamp((uMorph - aRand.z * uSpread) / (1.0 - uSpread), 0.0, 1.0);
    float e = easeInOut(t);
    vec3 p = mix(position, aLegPosition, e);
    vec3 n = normalize(mix(normal, aLegNormal, e) + vec3(1e-4));
    float alpha = mix(aAlpha.x, aAlpha.y, e);

    // Mid-transition the points lift off the surface and drift, then resettle.
    float flight = sin(3.14159265 * t) * uScatter;
    vec3 drift = vec3(aRand.w, fract(aRand.w * 7.13), fract(aRand.w * 13.7)) - 0.5;
    p += (n * 0.1 + drift * 0.16) * flight;

    vec4 mv = modelViewMatrix * vec4(p, 1.0);
    float depth = -mv.z;

    vec3 viewNormal = normalize(normalMatrix * n);
    float facing = dot(viewNormal, normalize(-mv.xyz));
    // Facing term carries the silhouette; a soft key light from the upper
    // left brings out the muscle forms.
    float key = max(dot(viewNormal, normalize(vec3(-0.55, 0.6, 0.6))), 0.0);
    float light = smoothstep(-0.2, 0.8, facing) * (0.55 + 0.75 * key);
    light = mix(light, 0.6, flight);

    float depthCue = 1.0 - 0.6 * smoothstep(uCamDist - 0.7, uCamDist + 0.9, depth);
    float twinkle = 0.9 + 0.1 * sin(uTime * (0.7 + aRand.y * 1.6) + aRand.w * 60.0);

    vAlpha = alpha * mix(0.03, 1.0, min(light, 1.0)) * depthCue * (0.65 + 0.35 * aRand.y) * twinkle * uReveal;

    float size = uSize * (0.75 + 0.5 * aRand.x) * mix(0.55, 1.0, min(light, 1.0)) * uScale / depth;
    // Sub-pixel dots are drawn at a minimum size with reduced opacity instead,
    // which keeps distant points from shimmering.
    float px = max(size, 1.5);
    vAlpha *= min(1.0, size / px);
    vSize = px;

    gl_PointSize = px;
    gl_Position = projectionMatrix * mv;
  }
`;

const fragmentShader = /* glsl */ `
  uniform vec3 uColor;
  varying float vAlpha;
  varying float vSize;

  void main() {
    float d = length(gl_PointCoord - 0.5) * 2.0;
    float aa = 2.0 / vSize;
    float disc = 1.0 - smoothstep(1.0 - aa, 1.0, d);
    if (disc <= 0.0) discard;
    gl_FragColor = vec4(uColor, disc * vAlpha);
  }
`;

export function createPointMaterial() {
  return new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    uniforms: {
      uMorph: { value: 1 },
      uSpread: { value: 0.6 },
      uScatter: { value: 1 },
      uSize: { value: 0.006 },
      uScale: { value: 500 },
      uTime: { value: 0 },
      uCamDist: { value: 5 },
      uReveal: { value: 0 },
      // Raw display RGB (ShaderMaterial skips colour-space conversion).
      uColor: { value: new THREE.Vector3(0.94, 0.95, 0.96) },
    },
    transparent: true,
    depthWrite: false,
    depthTest: false,
    blending: THREE.AdditiveBlending,
  });
}
