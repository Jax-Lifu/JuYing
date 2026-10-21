# Downloaded CatVod Dex links these host classes by their published binary names.
# R8 cannot infer those calls from the APK because the spiders arrive at runtime.
-keep class com.github.catvod.** { *; }

# Spider's public ABI exposes OkHttp types. Their methods and Okio dependencies
# are also invoked directly by independently compiled third-party spiders.
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
