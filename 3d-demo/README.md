# 3d-demo — point-cloud anatomy

A limb (arm or leg) rendered purely as a **surface point cloud**: no polygons are drawn,
the dots alone describe the silhouette and volume.

```bash
npm install
npm run dev
```

## Controls

- **Arm / Leg** switch (or `Space`, `A`, `L`) — points morph from one limb to the other
- **Density** slider — 5k to 60k points
- Drag to orbit, scroll to zoom

## Pipeline

```
SDF limb ──surface nets──▶ mesh ──area-weighted sampling──▶ candidates
candidates ──Poisson-disk selection──▶ evenly spaced points ──project──▶ surface positions + normals
```

- `src/anatomy.js` — arm and leg sculpted procedurally from blended round cones and ellipsoids
- `src/sampler.js` — mesh extraction, uniform surface sampling, blue-noise selection
- `src/cloud.js` — normalizes each limb and orders points so the morph reads as a reshape
- `src/worker.js` — generation runs off the main thread
- `src/pointMaterial.js` — point-sprite shader: dots shrink with depth, brightness follows the
  surface normal (facing camera = bright, grazing = dim, facing away = nearly invisible)

To use a real scanned or modelled limb instead, load the mesh (e.g. GLTF) and feed its
triangles to `sampleCandidates` in place of `polygonize`.
