// Procedural anatomy, sculpted as signed distance fields (units: metres).
// Both limbs are right-side, standing in anatomical position:
//   +y up, +z anterior (front), -x lateral (outside), +x medial.
// Each model exposes a `cutY` where the limb is severed; points dissolve
// over `fadeLength` below that cut.

import { ShapeBuilder } from './sdf.js';

export function buildLeg() {
  const s = new ShapeBuilder();

  // Thigh: femur core angled inwards (Q-angle) with muscle masses.
  s.cone([-0.03, 0.9, -0.005], [0.0, 0.5, 0.0], 0.082, 0.047, 0.03);
  s.ellipsoid([-0.012, 0.69, 0.03], [0.058, 0.17, 0.05], [0, 0, 3], 0.035); // rectus femoris / quads
  s.ellipsoid([0.034, 0.565, 0.028], [0.034, 0.065, 0.034], [0, 0, -12], 0.03); // vastus medialis
  s.ellipsoid([-0.05, 0.67, 0.0], [0.038, 0.16, 0.055], [0, 0, 4], 0.03); // vastus lateralis
  s.ellipsoid([0.0, 0.69, -0.035], [0.058, 0.16, 0.05], [0, 0, 2], 0.035); // hamstrings
  s.ellipsoid([0.04, 0.79, -0.005], [0.05, 0.11, 0.058], [0, 0, -10], 0.035); // adductors
  s.ellipsoid([-0.03, 0.87, -0.055], [0.085, 0.075, 0.065], [0, 0, 0], 0.04); // gluteal fold

  // Knee.
  s.ellipsoid([0.0, 0.48, -0.002], [0.052, 0.045, 0.046], [0, 0, 0], 0.025);
  s.ellipsoid([0.002, 0.505, 0.043], [0.024, 0.028, 0.013], [0, 0, 0], 0.012); // patella
  s.cone([0.002, 0.47, 0.038], [0.004, 0.42, 0.032], 0.012, 0.011, 0.012); // patellar tendon
  s.ellipsoid([-0.012, 0.47, -0.035], [0.02, 0.03, 0.02], [0, 0, 0], 0.02); // biceps femoris tendon
  s.ellipsoid([0.02, 0.47, -0.035], [0.02, 0.035, 0.02], [0, 0, 0], 0.02); // semitendinosus tendon

  // Lower leg: tibia with its sharp anterior crest, calf muscles behind.
  s.cone([0.0, 0.46, 0.0], [0.006, 0.09, 0.0], 0.043, 0.026, 0.02);
  s.cone([0.006, 0.43, 0.022], [0.01, 0.13, 0.018], 0.019, 0.015, 0.015); // tibial crest
  s.ellipsoid([0.018, 0.355, -0.036], [0.034, 0.085, 0.038], [8, 0, -4], 0.025); // gastrocnemius medial
  s.ellipsoid([-0.02, 0.37, -0.032], [0.031, 0.072, 0.035], [8, 0, 4], 0.025); // gastrocnemius lateral
  s.ellipsoid([0.0, 0.27, -0.024], [0.041, 0.1, 0.034], [4, 0, 0], 0.03); // soleus
  s.ellipsoid([-0.02, 0.33, 0.014], [0.024, 0.1, 0.024], [0, 0, 3], 0.02); // tibialis anterior
  s.cone([0.002, 0.2, -0.034], [0.002, 0.055, -0.046], 0.014, 0.012, 0.02); // achilles tendon

  // Ankle.
  s.ellipsoid([0.028, 0.075, 0.002], [0.014, 0.016, 0.014], [0, 0, 0], 0.012); // medial malleolus
  s.ellipsoid([-0.027, 0.06, -0.006], [0.013, 0.017, 0.013], [0, 0, 0], 0.012); // lateral malleolus

  // Foot: heel, dorsum and a fan of metatarsals.
  s.ellipsoid([0.0, 0.034, -0.036], [0.03, 0.034, 0.034], [0, 0, 0], 0.02); // heel
  s.ellipsoid([0.004, 0.05, 0.035], [0.037, 0.037, 0.075], [-14, 0, 0], 0.025); // dorsum
  const metatarsals = [
    { base: [0.022, 0.058, 0.02], head: [0.03, 0.02, 0.13], r: [0.019, 0.018] },
    { base: [0.01, 0.06, 0.025], head: [0.012, 0.019, 0.135], r: [0.014, 0.013] },
    { base: [-0.004, 0.058, 0.022], head: [-0.006, 0.018, 0.128], r: [0.014, 0.013] },
    { base: [-0.016, 0.052, 0.018], head: [-0.022, 0.017, 0.118], r: [0.014, 0.012] },
    { base: [-0.028, 0.042, 0.01], head: [-0.036, 0.015, 0.103], r: [0.013, 0.011] },
  ];
  for (const m of metatarsals) s.cone(m.base, m.head, m.r[0], m.r[1], 0.02);

  // Toes (big toe first, then 2..5).
  s.chain([[0.03, 0.02, 0.13], [0.032, 0.019, 0.165], [0.033, 0.017, 0.193]], [0.017, 0.0155, 0.013], 0.008);
  s.chain([[0.012, 0.019, 0.135], [0.013, 0.018, 0.16], [0.013, 0.013, 0.18]], [0.01, 0.0092, 0.008], 0.006);
  s.chain([[-0.006, 0.018, 0.128], [-0.007, 0.016, 0.152], [-0.008, 0.012, 0.17]], [0.0095, 0.0088, 0.0078], 0.006);
  s.chain([[-0.022, 0.017, 0.118], [-0.024, 0.015, 0.14], [-0.025, 0.011, 0.157]], [0.0092, 0.0084, 0.0075], 0.006);
  s.chain([[-0.036, 0.015, 0.103], [-0.039, 0.013, 0.122], [-0.04, 0.01, 0.137]], [0.0087, 0.008, 0.0071], 0.006);

  // Flat sole, severed at the hip.
  const cutY = 0.9;
  s.clip([0, -1, 0], 0, 0.012);
  s.clip([0, 1, 0], cutY);
  return { ...s.build(), cutY, fadeLength: 0.14, cell: 0.004 };
}

export function buildArm() {
  const s = new ShapeBuilder();

  // Shoulder and upper arm.
  s.ellipsoid([-0.012, 0.69, 0.0], [0.058, 0.05, 0.055], [0, 0, 0], 0.03); // shoulder cap
  s.ellipsoid([-0.022, 0.625, 0.002], [0.05, 0.1, 0.052], [0, 0, 8], 0.03); // deltoid
  s.cone([0.0, 0.68, 0.0], [0.002, 0.41, -0.006], 0.045, 0.033, 0.025);
  s.ellipsoid([0.002, 0.52, 0.022], [0.033, 0.1, 0.032], [0, 0, 0], 0.025); // biceps
  s.ellipsoid([0.004, 0.545, -0.022], [0.037, 0.12, 0.034], [0, 0, 0], 0.025); // triceps
  s.ellipsoid([0.03, 0.6, -0.004], [0.03, 0.1, 0.032], [0, 0, -6], 0.03); // medial arm mass

  // Elbow.
  s.ellipsoid([0.026, 0.405, -0.01], [0.014, 0.014, 0.013], [0, 0, 0], 0.018); // medial epicondyle
  s.ellipsoid([-0.024, 0.41, -0.006], [0.012, 0.013, 0.012], [0, 0, 0], 0.018); // lateral epicondyle
  s.ellipsoid([0.004, 0.4, -0.03], [0.017, 0.022, 0.015], [0, 0, 0], 0.014); // olecranon

  // Forearm in supination: radius (lateral) and ulna (medial) side by side
  // give the flattened, oval cross-section toward the wrist.
  s.cone([-0.012, 0.39, 0.0], [-0.019, 0.14, 0.0], 0.022, 0.016, 0.02); // radius side
  s.cone([0.014, 0.4, -0.01], [0.019, 0.14, -0.002], 0.02, 0.012, 0.02); // ulna side
  s.ellipsoid([-0.024, 0.325, 0.002], [0.029, 0.085, 0.029], [0, 0, -4], 0.025); // brachioradialis
  s.ellipsoid([0.014, 0.33, 0.012], [0.029, 0.085, 0.027], [0, 0, 5], 0.025); // flexors
  s.ellipsoid([0.0, 0.132, 0.0], [0.03, 0.02, 0.016], [0, 0, 0], 0.015); // wrist
  s.ellipsoid([0.024, 0.142, -0.008], [0.008, 0.009, 0.008], [0, 0, 0], 0.008); // ulnar styloid

  // Hand, palm facing forward (+z), fingers pointing down.
  s.box([0.0, 0.07, 0.0], [0.038, 0.046, 0.011], 0.009, [0, 0, 0], 0.012); // palm
  s.ellipsoid([-0.022, 0.085, 0.01], [0.018, 0.032, 0.013], [0, 0, -18], 0.012); // thenar
  s.ellipsoid([0.027, 0.075, 0.008], [0.013, 0.036, 0.011], [0, 0, 4], 0.012); // hypothenar

  // Fingers: [x at knuckle, splay (x drift per unit length), phalanx lengths, radii]
  const fingers = [
    { x: -0.026, splay: -0.12, lengths: [0.042, 0.025, 0.02], radii: [0.0098, 0.0092, 0.0083, 0.0072] },
    { x: -0.007, splay: -0.03, lengths: [0.047, 0.029, 0.021], radii: [0.0102, 0.0095, 0.0086, 0.0075] },
    { x: 0.012, splay: 0.05, lengths: [0.044, 0.027, 0.02], radii: [0.0095, 0.009, 0.0081, 0.007] },
    { x: 0.029, splay: 0.14, lengths: [0.034, 0.021, 0.018], radii: [0.0084, 0.0078, 0.007, 0.0062] },
  ];
  for (const f of fingers) {
    // Relaxed hand: each joint curls a little further toward the palm (+z).
    const pts = [[f.x, 0.03, 0.0]];
    let angle = 0.08;
    let [x, y, z] = pts[0];
    for (const len of f.lengths) {
      angle += 0.14;
      x += f.splay * len;
      y -= Math.cos(angle) * len;
      z += Math.sin(angle) * len;
      pts.push([x, y, z]);
    }
    s.chain(pts, f.radii, 0.006);
  }
  // Thumb: metacarpal + two phalanges, rotated forward and out.
  s.cone([-0.028, 0.108, 0.004], [-0.047, 0.066, 0.02], 0.0145, 0.0115, 0.012);
  s.chain([[-0.047, 0.066, 0.02], [-0.056, 0.036, 0.03], [-0.06, 0.01, 0.036]], [0.0115, 0.0102, 0.0085], 0.005);

  const cutY = 0.72;
  s.clip([0, 1, 0], cutY);
  return { ...s.build(), cutY, fadeLength: 0.12, cell: 0.003 };
}
