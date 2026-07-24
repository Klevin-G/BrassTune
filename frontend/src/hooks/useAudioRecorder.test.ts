import { describe, expect, it } from 'vitest';
import type { SessionAudioUploadResponse } from '../api/client';
import { audioRecorderErrorMessageIds, classifyAudioUploadResponse } from './useAudioRecorder';

function response(flags: Partial<SessionAudioUploadResponse> = {}): SessionAudioUploadResponse {
  return {
    uploaded: true,
    audio: { id: 7 } as SessionAudioUploadResponse['audio'],
    ...flags,
  };
}

describe('audio upload 202 consumer state', () => {
  it('keeps stable error codes mapped to localized message IDs', () => {
    expect(audioRecorderErrorMessageIds).toEqual({
      capture_unavailable: 'audioRecorder.captureUnavailable',
      microphone_denied: 'audioRecorder.microphoneDenied',
      upload_failed: 'audioRecorder.uploadFailed',
      local_save_failed: 'practice.errorLocalSave',
    });
  });

  it('keeps activation and reconciliation ambiguity pending instead of reporting upload success', () => {
    expect(classifyAudioUploadResponse(response({ activation_pending: true, reconciliation_pending: true }))).toEqual({
      status: 'pending',
      pendingReason: 'activation',
    });
    expect(classifyAudioUploadResponse(response({ reconciliation_pending: true }))).toEqual({
      status: 'pending',
      pendingReason: 'reconciliation',
    });
  });

  it('reports cleanup-only and combined follow-up work truthfully', () => {
    expect(classifyAudioUploadResponse(response({ cleanup_pending: true }))).toEqual({
      status: 'pending',
      pendingReason: 'cleanup',
    });
    expect(classifyAudioUploadResponse(response({ cleanup_pending: true, reconciliation_pending: true }))).toEqual({
      status: 'pending',
      pendingReason: 'cleanup_reconciliation',
    });
    expect(classifyAudioUploadResponse(response())).toEqual({ status: 'uploaded', pendingReason: null });
  });
});
