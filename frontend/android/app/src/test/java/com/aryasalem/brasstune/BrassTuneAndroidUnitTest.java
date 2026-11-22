package com.aryasalem.brasstune;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/**
 * Static native-project guardrail. Web behavior is validated by the Vite test
 * suite; this test protects the release package identifier from accidental
 * drift before a signing configuration exists.
 */
public class BrassTuneAndroidUnitTest {

    @Test
    public void packageName_isAndroidSafeAndStable() {
        assertEquals("com.aryasalem.brasstune", BuildConfig.APPLICATION_ID);
    }
}
