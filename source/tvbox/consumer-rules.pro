# Downloaded JARs and Python call these contracts by their published names.
-keep class com.github.catvod.crawler.** { *; }
# CatVod JARs resolve Gson dynamically, so R8 cannot infer their calls.
-keep class com.google.gson.** { *; }
-keep class com.flytech.juying.source.tvbox.spider.ScriptHttp { public *; }
