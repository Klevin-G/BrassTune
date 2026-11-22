import { App } from '@capacitor/app';
import { Browser } from '@capacitor/browser';
import { Capacitor } from '@capacitor/core';
import { PRACTICE_AUDIO_PAUSE_EVENT, PRACTICE_AUDIO_RESUME_EVENT } from '../domain/practiceLibrary';

const ANDROID_OAUTH_CALLBACK = 'com.brasstune.android://auth/callback';
const ACCOUNT_WEB_ORIGIN = 'https://brasstune.vercel.app';

export function isNativeAndroidPlatform(): boolean {
  return Capacitor.isNativePlatform() && Capacitor.getPlatform() === 'android';
}

/**
 * Native OAuth stays opt-in until the exact callback is added to Supabase's
 * redirect allow-list. This prevents an Android package from showing a button
 * whose browser return can never complete.
 */
export function nativeAndroidOAuthEnabled(): boolean {
  return nativeAndroidAccountFeaturesEnabled() && import.meta.env.VITE_ANDROID_OAUTH_ENABLED === 'true';
}

export function hasValidNativeAccountEndpoints(apiBase: string | undefined, wsBase: string | undefined): boolean {
  const validOrigin = (value: string | undefined, protocol: 'https:' | 'wss:') => {
    if (!value) return false;
    try {
      const url = new URL(value);
      return url.protocol === protocol
        && Boolean(url.hostname)
        && !isLoopbackHost(url.hostname)
        && !url.username
        && !url.password
        && !url.port
        && (url.pathname === '/' || url.pathname === '')
        && !url.search
        && !url.hash;
    } catch {
      return false;
    }
  };
  return validOrigin(apiBase, 'https:') && validOrigin(wsBase, 'wss:');
}

function isLoopbackHost(hostname: string): boolean {
  const normalized = hostname.replace(/^\[|\]$/g, '').toLowerCase();
  return normalized === 'localhost'
    || normalized === '::1'
    || /^127(?:\.\d{1,3}){3}$/.test(normalized);
}

/**
 * The packaged WebView has the `https://localhost` origin. Backend CORS and
 * WebSocket policy must explicitly approve it, and API/WS production bases
 * must be supplied at bundle build time before account surfaces can appear.
 */
export function nativeAndroidAccountFeaturesEnabled(): boolean {
  return isNativeAndroidPlatform()
    && import.meta.env.VITE_ANDROID_ACCOUNT_API_ENABLED === 'true'
    && hasValidNativeAccountEndpoints(
      import.meta.env.VITE_API_BASE_URL,
      import.meta.env.VITE_WS_BASE_URL,
    );
}

export function nativeAndroidOAuthCallbackURL(): string {
  return ANDROID_OAUTH_CALLBACK;
}

/**
 * Password-reset and email-confirmation links need an HTTPS origin that the
 * email client can open. Until Android App Links are separately verified, use
 * the existing production web reset route rather than emitting `https://localhost`.
 */
export function nativeAccountWebOrigin(): string | null {
  return isNativeAndroidPlatform() ? ACCOUNT_WEB_ORIGIN : null;
}

/** Convert only the expected Android callback into an in-app auth route. */
export function nativeOAuthCallbackRoute(value: string): string | null {
  try {
    const url = new URL(value);
    if (
      url.protocol !== 'com.brasstune.android:'
      || url.hostname !== 'auth'
      || url.pathname !== '/callback'
      || url.username
      || url.password
      || url.port
    ) {
      return null;
    }
    return `/auth/callback${url.search}${url.hash}`;
  } catch {
    return null;
  }
}

export async function openNativeOAuthBrowser(url: string): Promise<void> {
  if (!nativeAndroidOAuthEnabled()) {
    throw new Error('Android OAuth is not configured for this build.');
  }
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:' || !parsed.hostname || parsed.username || parsed.password) {
    throw new Error('Android OAuth received an unsafe authorization URL.');
  }
  await Browser.open({ url: parsed.toString() });
}

function deliverNativeOAuthCallback(url: string): void {
  const route = nativeOAuthCallbackRoute(url);
  if (!route) return;
  void Browser.close().catch(() => undefined);
  window.location.assign(route);
}

/**
 * Capacitor does not reliably issue browser `visibilitychange` while Android
 * backgrounds the activity. Reuse the web app's explicit audio-stop event so
 * the tuner, recorder, metronome, and drone release hardware promptly. The
 * resume event never starts a saved take; its listener may only restore a
 * passive tuner microphone after finalization completed.
 */
export async function initializeNativePlatform(): Promise<void> {
  if (!isNativeAndroidPlatform()) return;

  await App.addListener('appStateChange', ({ isActive }) => {
    window.dispatchEvent(new Event(isActive ? PRACTICE_AUDIO_RESUME_EVENT : PRACTICE_AUDIO_PAUSE_EVENT));
  });
  await App.addListener('appUrlOpen', ({ url }) => deliverNativeOAuthCallback(url));

  const launch = await App.getLaunchUrl().catch(() => null);
  if (launch?.url) deliverNativeOAuthCallback(launch.url);
}
