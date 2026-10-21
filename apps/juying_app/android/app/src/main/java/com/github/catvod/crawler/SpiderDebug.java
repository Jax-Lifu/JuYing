package com.github.catvod.crawler;

import android.util.Log;

import java.util.Locale;

/** Lightweight logging ABI expected by common CatVod JAR packages. */
public final class SpiderDebug {
    private static final String TAG = "CatVodSpider";

    private SpiderDebug() {}

    public static boolean isEnabled() { return true; }

    public static void log(Throwable throwable) { log(TAG, throwable); }

    public static void log(String tag, Throwable throwable) {
        if (throwable != null) Log.e(tag, throwable.getMessage(), throwable);
    }

    public static void log(String message) {
        if (message != null && !message.isEmpty()) Log.d(TAG, message);
    }

    public static void log(String tag, String message, Object... args) {
        if (message == null || message.isEmpty()) return;
        try {
            Log.d(tag, args == null || args.length == 0
                    ? message
                    : String.format(Locale.US, message, args));
        } catch (Throwable ignored) {
            Log.d(tag, message);
        }
    }
}
