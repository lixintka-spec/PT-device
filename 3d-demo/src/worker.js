// Point clouds are generated off the main thread so the page stays responsive.
import { makeCloud } from './cloud.js';

self.onmessage = ({ data: { id, count } }) => {
  const clouds = {};
  const transfer = [];
  for (const name of ['arm', 'leg']) {
    const cloud = makeCloud(name, count);
    clouds[name] = cloud;
    transfer.push(cloud.positions.buffer, cloud.normals.buffer, cloud.alpha.buffer);
  }
  self.postMessage({ id, count, clouds }, transfer);
};
