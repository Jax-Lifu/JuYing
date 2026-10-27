package com.github.catvod.spider;

import android.content.Context;

/** The fixture requires the same once-per-JAR initializer as public CatVod plugins. */
public final class Init {
    public static int calls;
    public static void init(Context context) {
        if (!(context instanceof android.app.Application)) throw new IllegalArgumentException("CatVod needs Application");
        calls++;
    }
}
