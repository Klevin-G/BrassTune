import type { CapacitorConfig } from '@capacitor/cli';

/**
 * Android packages the Vite output that was built locally.  Do not set a
 * `server.url` here: loading a remote site would make the installed app depend
 * on a network connection and would undermine the offline-practice contract.
 */
const config: CapacitorConfig = {
  appId: 'com.aryasalem.brasstune',
  appName: 'BrassTune',
  webDir: 'dist',
  android: {
    allowMixedContent: false,
  },
  server: {
    // A secure local origin is required for WebView media APIs such as
    // getUserMedia and MediaRecorder.
    androidScheme: 'https',
  },
};

export default config;
