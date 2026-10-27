package com.github.catvod.crawler;

import timber.log.Timber;

/** FongMi/CatVod 日志 ABI；第三方正文可能包含凭据，只记录类型或长度。 */
public final class SpiderDebug {
    public static void log(Throwable error) {
        if (error != null) Timber.d("Spider error: %s", error.getClass().getSimpleName());
    }

    public static void log(String message) {
        if (message != null) Timber.v("Spider message: %d chars", message.length());
    }

    public static void log(String tag, String message, Object... args) {
        log(message);
    }
}
