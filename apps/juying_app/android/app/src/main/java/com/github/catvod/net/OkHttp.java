package com.github.catvod.net;

import java.util.concurrent.TimeUnit;

import okhttp3.Dns;
import okhttp3.OkHttpClient;

/** Minimal CatVod networking ABI shared by dynamically loaded spiders. */
public final class OkHttp {
    private static final OkHttpClient CLIENT = new OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build();

    private OkHttp() {}

    public static Dns dns() { return Dns.SYSTEM; }

    public static OkHttpClient client() { return CLIENT; }
}
