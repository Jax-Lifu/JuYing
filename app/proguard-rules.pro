# Hilt / Room / kotlinx.serialization 的规则由各库的 consumer rules 提供。
# 保留崩溃堆栈行号与运行时注解（供 smbj 的 MBassador 事件总线反射读取 @Handler）
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
-renamesourcefileattribute SourceFile

# Release 包彻底剥离 Timber.v / Timber.d 调试日志调用及其参数拼接开销
-assumenosideeffects class timber.log.Timber {
    public static *** v(...);
    public static *** d(...);
}
-assumenosideeffects class timber.log.Timber$Forest {
    public *** v(...);
    public *** d(...);
}

# TVBox jar 爬虫通过反射加载并继承 Spider，必须保留其公共 API 与签名。
-keep class com.github.catvod.** { *; }
-keepclassmembers class * extends com.github.catvod.crawler.Spider { *; }

# SMBJ 与 MBassador 事件总线（SMBEventBus 通过反射调用 HandlerInvocation(SubscriptionContext) 构造器与 @Handler 方法）
-keep class net.engio.mbassy.** { *; }
-keep class com.hierynomus.smbj.** { *; }
-keep class com.hierynomus.protocol.** { *; }
-keepclassmembers class * {
    @net.engio.mbassy.listener.Handler <methods>;
}

# 忽略第三方桌面/服务端可选依赖告警
-dontwarn javax.el.**
-dontwarn org.slf4j.**
-dontwarn org.ietf.jgss.**
-dontwarn org.bouncycastle.**
-dontwarn kotlin.reflect.jvm.internal.**
-dontwarn java.rmi.**
