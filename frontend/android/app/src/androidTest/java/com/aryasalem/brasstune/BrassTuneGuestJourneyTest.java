package com.aryasalem.brasstune;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;
import java.io.File;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Pattern;
import org.json.JSONArray;
import org.junit.Test;
import org.junit.runner.RunWith;

/**
 * Device smoke for the packaged guest WebView. Run on a disposable emulator after
 * clearing app data and revoking RECORD_AUDIO; the test deliberately exercises
 * the first Android permission prompt and temporarily turns airplane mode on.
 * It uses DOM assertions because this WebView's accessibility tree exposes only
 * its container on the tested emulator, while UI Automator handles Android UI.
 */
@RunWith(AndroidJUnit4.class)
public class BrassTuneGuestJourneyTest {
    private static final String TAG = "BrassTuneGuestSmoke";
    private static final String PACKAGE = "com.aryasalem.brasstune";
    private static final long UI_TIMEOUT_MS = 15_000;
    private static final long JS_TIMEOUT_MS = 10_000;

    @Test
    public void deniedMicRetriesThenBackgroundSavesGuestTakeOffline() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        assertEquals("Start with RECORD_AUDIO revoked on a disposable emulator.",
            PackageManager.PERMISSION_DENIED, context.checkSelfPermission(Manifest.permission.RECORD_AUDIO));

        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(MainActivity.class)) {
            waitForJs(scenario, "document.querySelector('.ag-guest') !== null");
            assertEquals("Guest-only package must not offer account creation.", "false",
                js(scenario, "document.querySelector('.ag-create-account, .ag-email-toggle, .google-button') !== null"));
            screenshot(device, context, "01-gateway.png");
            tap(scenario, device, ".ag-guest");
            waitForJs(scenario, "location.pathname === '/practice' && document.querySelector('[aria-label=\"Live tuner\"]') !== null");

            UiObject2 deny = device.wait(Until.findObject(By.text(Pattern.compile("(?i).*don.t allow.*"))), UI_TIMEOUT_MS);
            assertNotNull("Android must offer the first microphone permission decision.", deny);
            deny.click();
            if ("true".equals(js(scenario, "document.querySelector('.ob-close') !== null"))) {
                tap(scenario, device, ".ob-close");
                waitForJs(scenario, "document.querySelector('.ob-backdrop') === null");
            }
            waitForJs(scenario, "document.querySelector('[aria-label=\"Turn on microphone\"]') !== null");
            assertEquals("true", js(scenario,
                "(() => { const m = navigator.mediaDevices; const original = m.getUserMedia.bind(m); "
                    + "window.__btSmokeTracks = []; m.getUserMedia = async (...args) => { "
                    + "const stream = await original(...args); window.__btSmokeTracks.push(...stream.getTracks()); "
                    + "return stream; }; return true; })()"));

            String grantResult = device.executeShellCommand("pm grant " + PACKAGE + " android.permission.RECORD_AUDIO");
            Log.i(TAG, "pm grant result: " + grantResult.trim());
            assertEquals(PackageManager.PERMISSION_GRANTED, context.checkSelfPermission(Manifest.permission.RECORD_AUDIO));
            tap(scenario, device, "[aria-label='Turn on microphone']");
            waitForJs(scenario,
                "window.__btSmokeTracks.length > 0 && window.__btSmokeTracks[0].readyState === 'live' "
                    + "&& document.querySelector('[aria-label=\"Turn on microphone\"]') === null");
            screenshot(device, context, "02-microphone-live.png");

            tap(scenario, device, "[aria-label='Save this take']");
            waitForJs(scenario, "document.querySelector('[aria-label=\"Stop and save\"]') !== null");
            screenshot(device, context, "03-recording.png");
            device.pressHome();
            SystemClock.sleep(2_000);
            device.executeShellCommand("am start -n " + PACKAGE + "/.MainActivity");
            waitForJs(scenario, "window.__btSmokeTracks.length > 0 && window.__btSmokeTracks[0].readyState === 'ended'");
            waitForJs(scenario,
                "(() => { const rows = JSON.parse(localStorage.getItem('brasstune.guestSessions.v1') || '[]'); "
                    + "return rows.length > 0 && rows[0].guest_session === true && rows[0].ended_at !== null; })()");
            Log.i(TAG, "Guest take finalized and the captured microphone track ended after Home.");
            screenshot(device, context, "04-returned-saved.png");

            try {
                device.executeShellCommand("cmd connectivity airplane-mode enable");
                device.executeShellCommand("svc wifi disable");
                device.executeShellCommand("svc data disable");
                assertEquals("The relaunch must run with airplane mode enabled.", "enabled",
                    device.executeShellCommand("cmd connectivity airplane-mode").trim());
                scenario.recreate();
                waitForJs(scenario, "document.querySelector('.ag-guest, a[href=\"/sessions\"]') !== null");
                if ("true".equals(js(scenario, "document.querySelector('.ag-guest') !== null"))) {
                    tap(scenario, device, ".ag-guest");
                    waitForJs(scenario, "location.pathname === '/practice'");
                }
                if ("true".equals(js(scenario, "document.querySelector('.ob-close') !== null"))) {
                    tap(scenario, device, ".ob-close");
                    waitForJs(scenario, "document.querySelector('.ob-backdrop') === null");
                }
                waitForJs(scenario, "document.querySelector('a[href=\"/sessions\"]') !== null");
                tap(scenario, device, "a[href='/sessions']");
                waitForJs(scenario, "location.pathname === '/sessions' && document.querySelectorAll('.ps-item').length > 0");
                assertFalse("Saved guest take must not disappear offline.",
                    "true".equals(js(scenario, "document.body.textContent.includes('No recordings yet')")));
                screenshot(device, context, "05-offline-recordings.png");
                Log.i(TAG, "Guest recording is visible after offline Activity recreation.");
            } finally {
                device.executeShellCommand("cmd connectivity airplane-mode disable");
                device.executeShellCommand("svc wifi enable");
                device.executeShellCommand("svc data enable");
            }
        }
    }

    @Test
    public void metronomeAndDroneStopOnExplicitTapAndAndroidHomeWhileOffline() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        device.executeShellCommand("cmd connectivity airplane-mode enable");
        device.executeShellCommand("svc wifi disable");
        device.executeShellCommand("svc data disable");
        try {
            assertEquals("enabled", device.executeShellCommand("cmd connectivity airplane-mode").trim());
            try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(MainActivity.class)) {
                waitForJs(scenario,
                    "document.querySelector('.ag-guest, a[href=\"/metronome\"]') !== null");
                if ("true".equals(js(scenario, "document.querySelector('.ag-guest') !== null"))) {
                    assertEquals("Guest-only package must not offer account creation.", "false",
                        js(scenario, "document.querySelector('.ag-create-account, .ag-email-toggle, .google-button') !== null"));
                    tap(scenario, device, ".ag-guest");
                    waitForJs(scenario, "location.pathname === '/practice'");
                }
                dismissMicPromptIfPresent(device);
                if ("true".equals(js(scenario, "document.querySelector('.ob-close') !== null"))) {
                    tap(scenario, device, ".ob-close");
                    waitForJs(scenario, "document.querySelector('.ob-backdrop') === null");
                }

                // Observe actual oscillator creation/stops; a button label alone
                // would not show that WebAudio ever drove a native output node.
                assertEquals("true", js(scenario,
                    "(() => { const Audio = window.AudioContext || window.webkitAudioContext; if (!Audio) return false; "
                        + "const probe = window.__btAudioProbe = {created: 0, stopCalls: 0}; "
                        + "const original = Audio.prototype.createOscillator; "
                        + "Audio.prototype.createOscillator = function(...args) { "
                        + "const oscillator = original.apply(this, args); probe.created++; "
                        + "const stop = oscillator.stop.bind(oscillator); "
                        + "oscillator.stop = (...values) => { probe.stopCalls++; return stop(...values); }; "
                        + "return oscillator; }; return true; })()"));

                waitForJs(scenario, "document.querySelector('a[href=\"/metronome\"]') !== null");
                tap(scenario, device, "a[href='/metronome']");
                waitForJs(scenario, "location.pathname === '/metronome' && document.querySelector('.mt-transport') !== null");
                tap(scenario, device, ".mt-transport");
                waitForJs(scenario, "document.querySelector('.mt-transport.is-running') !== null && window.__btAudioProbe.created > 0");
                screenshot(device, context, "06-metronome-running.png");
                tap(scenario, device, ".mt-transport");
                waitForJs(scenario,
                    "document.querySelector('.mt-transport.is-running') === null "
                        + "&& document.querySelector('.mt-status')?.textContent.trim() === 'Stopped'");
                int stoppedMetronomeCreated = Integer.parseInt(js(scenario, "window.__btAudioProbe.created"));
                // At 96 BPM a beat is about 625 ms. Observe beyond two beats
                // so a still-running scheduler cannot pass by chance.
                SystemClock.sleep(1_500);
                assertEquals("Explicit metronome stop must halt tick scheduling.", stoppedMetronomeCreated,
                    Integer.parseInt(js(scenario, "window.__btAudioProbe.created")));

                tap(scenario, device, ".mt-transport");
                waitForJs(scenario,
                    "document.querySelector('.mt-transport.is-running') !== null "
                        + "&& window.__btAudioProbe.created > " + stoppedMetronomeCreated);
                device.pressHome();
                SystemClock.sleep(800);
                device.executeShellCommand("am start -n " + PACKAGE + "/.MainActivity");
                waitForJs(scenario,
                    "location.pathname === '/metronome' && document.querySelector('.mt-transport.is-running') === null "
                        + "&& document.querySelector('.mt-status')?.textContent.trim() === 'Stopped'");
                int backgroundMetronomeCreated = Integer.parseInt(js(scenario, "window.__btAudioProbe.created"));
                SystemClock.sleep(1_500);
                assertEquals("Android Home must halt metronome tick scheduling.", backgroundMetronomeCreated,
                    Integer.parseInt(js(scenario, "window.__btAudioProbe.created")));
                screenshot(device, context, "07-metronome-stopped-after-home.png");
                Log.i(TAG, "Metronome started WebAudio oscillators; explicit stop and Home stopped tick scheduling.");

                tap(scenario, device, ".floating-tabbar a[href='/practice']");
                waitForJs(scenario, "location.pathname === '/practice'");
                // Returning through the tuner may request the microphone again
                // after an earlier denial. Dismiss it before touching the drone.
                dismissMicPromptIfPresent(device);
                tap(scenario, device, "[role='radiogroup'][aria-label='Practice tool'] button:last-child");
                waitForJs(scenario,
                    "document.querySelector('.practice-actions button')?.textContent.trim() === 'Start tone'");
                int beforeDrone = Integer.parseInt(js(scenario, "window.__btAudioProbe.created"));
                tap(scenario, device, ".practice-actions button");
                waitForJs(scenario,
                    "document.querySelector('.practice-actions button')?.textContent.trim() === 'Stop tone' "
                        + "&& window.__btAudioProbe.created > " + beforeDrone);
                screenshot(device, context, "08-drone-running.png");
                int beforeExplicitDroneStop = Integer.parseInt(js(scenario, "window.__btAudioProbe.stopCalls"));
                tap(scenario, device, ".practice-actions button");
                waitForJs(scenario,
                    "document.querySelector('.practice-actions button')?.textContent.trim() === 'Start tone' "
                        + "&& window.__btAudioProbe.stopCalls > " + beforeExplicitDroneStop);

                tap(scenario, device, ".practice-actions button");
                waitForJs(scenario, "document.querySelector('.practice-actions button')?.textContent.trim() === 'Stop tone'");
                int beforeBackgroundDroneStop = Integer.parseInt(js(scenario, "window.__btAudioProbe.stopCalls"));
                device.pressHome();
                SystemClock.sleep(800);
                device.executeShellCommand("am start -n " + PACKAGE + "/.MainActivity");
                waitForJs(scenario,
                    "location.pathname === '/practice' "
                        + "&& document.querySelector('.practice-actions button')?.textContent.trim() === 'Start tone' "
                        + "&& window.__btAudioProbe.stopCalls > " + beforeBackgroundDroneStop);
                // The WebView DOM can settle before Android's next compositor
                // frame after resuming the Activity.
                SystemClock.sleep(900);
                assertEquals("true", js(scenario,
                    "document.querySelector('.practice-actions button')?.textContent.trim() === 'Start tone'"));
                screenshot(device, context, "09-drone-stopped-after-home.png");
                Log.i(TAG, "Drone created WebAudio oscillators; explicit stop and Home called oscillator.stop().");
            }
        } finally {
            device.executeShellCommand("cmd connectivity airplane-mode disable");
            device.executeShellCommand("svc wifi enable");
            device.executeShellCommand("svc data enable");
        }
    }

    private static WebView findWebView(View view) {
        if (view instanceof WebView) return (WebView) view;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int index = 0; index < group.getChildCount(); index++) {
                WebView found = findWebView(group.getChildAt(index));
                if (found != null) return found;
            }
        }
        return null;
    }

    private static void dismissMicPromptIfPresent(UiDevice device) {
        UiObject2 deny = device.wait(Until.findObject(By.text(Pattern.compile("(?i).*don.t allow.*"))), 3_000);
        if (deny != null) deny.click();
    }

    private static String js(ActivityScenario<MainActivity> scenario, String expression) throws Exception {
        AtomicReference<String> result = new AtomicReference<>();
        CountDownLatch completed = new CountDownLatch(1);
        scenario.onActivity(activity -> {
            WebView webView = findWebView(activity.getWindow().getDecorView());
            assertNotNull("Packaged activity must contain a WebView.", webView);
            webView.evaluateJavascript(expression, value -> {
                result.set(value);
                completed.countDown();
            });
        });
        assertTrue("WebView JavaScript timed out: " + expression, completed.await(JS_TIMEOUT_MS, TimeUnit.MILLISECONDS));
        return result.get();
    }

    private static void waitForJs(ActivityScenario<MainActivity> scenario, String expression) throws Exception {
        long deadline = SystemClock.uptimeMillis() + UI_TIMEOUT_MS;
        String last = null;
        while (SystemClock.uptimeMillis() < deadline) {
            last = js(scenario, expression);
            if ("true".equals(last)) return;
            SystemClock.sleep(150);
        }
        assertEquals("Timed out waiting for WebView condition: " + expression, "true", last);
    }

    /** Touch the visible DOM element through Android input, rather than calling
     * HTMLElement.click(). The hit test fails if a modal obscures the control. */
    private static void tap(ActivityScenario<MainActivity> scenario, UiDevice device, String selector) throws Exception {
        String quotedSelector = org.json.JSONObject.quote(selector);
        String coordinates = js(scenario,
            "(() => { const e = document.querySelector(" + quotedSelector + "); if (!e) return null; "
                + "e.scrollIntoView({block: 'center'}); const r = e.getBoundingClientRect(); "
                + "const x = r.left + r.width / 2, y = r.top + r.height / 2; "
                + "const hit = document.elementFromPoint(x, y); "
                + "return [x, y, window.innerWidth, r.width > 0 && r.height > 0 && (hit === e || e.contains(hit))]; })()");
        assertFalse("DOM target missing: " + selector, "null".equals(coordinates));
        JSONArray values = new JSONArray(coordinates);
        assertTrue("DOM target is hidden or covered: " + selector, values.getBoolean(3));
        AtomicReference<int[]> geometry = new AtomicReference<>();
        scenario.onActivity(activity -> {
            WebView webView = findWebView(activity.getWindow().getDecorView());
            assertNotNull(webView);
            int[] position = new int[2];
            webView.getLocationOnScreen(position);
            geometry.set(new int[] { position[0], position[1], webView.getWidth() });
        });
        int[] webView = geometry.get();
        double scale = (double) webView[2] / values.getDouble(2);
        assertTrue("Android touch failed: " + selector,
            device.click(webView[0] + (int) Math.round(values.getDouble(0) * scale),
                webView[1] + (int) Math.round(values.getDouble(1) * scale)));
    }

    private static void screenshot(UiDevice device, Context context, String name) {
        File directory = new File(context.getExternalFilesDir(null), "instrumentation");
        if (directory.mkdirs() || directory.isDirectory()) {
            // WebView DOM updates can precede the next compositor frame.
            SystemClock.sleep(350);
            assertTrue("Could not save instrumentation screenshot: " + name,
                device.takeScreenshot(new File(directory, name)));
        }
    }
}
