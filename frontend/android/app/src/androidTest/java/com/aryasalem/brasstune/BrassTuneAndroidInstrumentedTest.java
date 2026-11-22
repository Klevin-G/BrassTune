package com.aryasalem.brasstune;

import static org.junit.Assert.assertEquals;

import android.content.Context;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;

/**
 * Minimal device-side package identity check. Audio, OAuth, and WebView flows
 * require explicit physical-device journeys before release.
 */
@RunWith(AndroidJUnit4.class)
public class BrassTuneAndroidInstrumentedTest {

    @Test
    public void appContext_usesTheBrassTunePackage() {
        Context appContext = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertEquals("com.aryasalem.brasstune", appContext.getPackageName());
    }
}
