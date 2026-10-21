package com.github.catvod.spider;

import android.content.Context;

/** Delayed initialization makes shared-bundle ordering observable on a real Android runtime. */
public final class Init {
    public static volatile boolean ready;

    public static void init(Context context) throws InterruptedException {
        Thread.sleep(250);
        ready = true;
    }
}
