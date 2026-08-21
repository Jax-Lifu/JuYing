package com.github.catvod.crawler;

public final class SpiderDebug {
    private SpiderDebug() {}
    public static void log(Throwable error) { if (error != null) error.printStackTrace(System.err); }
    public static void log(String message) { if (message != null) System.err.println(message); }
    public static void log(String tag, String message, Object... args) {
        if (message != null) System.err.println(tag + ": " + String.format(message, args));
    }
}
