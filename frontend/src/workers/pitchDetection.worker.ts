/// <reference lib="webworker" />

import { pitchFrameFromPcm } from '../domain/localPitchDetection';

interface PitchWorkerRequest {
  type: 'detect';
  pcm: ArrayBuffer;
  sampleRate: number;
  instrumentId: string;
  referencePitch: number;
  timestampMs: number;
}

self.onmessage = (event: MessageEvent<PitchWorkerRequest>) => {
  const request = event.data;
  if (request.type !== 'detect') return;
  const frame = pitchFrameFromPcm(
    new Float32Array(request.pcm),
    request.sampleRate,
    request.instrumentId,
    request.referencePitch,
    request.timestampMs,
  );
  self.postMessage({ type: 'frame', timestampMs: request.timestampMs, frame });
};

export {};
