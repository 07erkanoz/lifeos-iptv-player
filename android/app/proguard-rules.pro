# R8 / ProGuard keep rules for LifeOs TV release builds.
# Wired up in app/build.gradle.kts (release { proguardFiles(...) }).

# ─── Generic attributes that R8 strips by default but reflection needs ──────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Exceptions
# Keep line numbers so Crashlytics / stack traces stay readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ─── JNI: every native method's owning class must keep its name ────────────
-keepclasseswithmembernames class * {
    native <methods>;
}
-keepclassmembers class * {
    native <methods>;
}

# ─── Kotlin metadata (coroutines + reflection in plugins) ──────────────────
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ─── Flutter embedding / plugin shims ──────────────────────────────────────
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.util.** { *; }

# ─── media_kit + libmpv (JNI bindings + reflection) ────────────────────────
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-keep class com.alexmercerind.** { *; }
-keep class io.github.** { *; }
-dontwarn com.alexmercerind.**
-dontwarn io.github.**

# ─── drift (SQLite ORM, generated code uses reflection on annotations) ─────
-keep class drift.** { *; }
-keep class moor.** { *; }
-dontwarn drift.**
-dontwarn moor.**

# ─── dio / okhttp / okio (HTTP client) ─────────────────────────────────────
-dontwarn okio.**
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ─── bonsoir (mDNS Chromecast discovery) ───────────────────────────────────
-keep class fr.skyost.bonsoir.** { *; }
-dontwarn fr.skyost.bonsoir.**

# ─── Google Cast SDK (Chromecast) ──────────────────────────────────────────
-keep class com.google.android.gms.cast.** { *; }
-dontwarn com.google.android.gms.cast.**

# ─── window_manager / screen_brightness / wakelock_plus ────────────────────
-keep class com.example.window_manager.** { *; }
-keep class jp.kawamuray.wasabeef.screen_brightness.** { *; }
-keep class dev.fluttercommunity.plus.wakelock.** { *; }
-dontwarn jp.kawamuray.wasabeef.screen_brightness.**
-dontwarn dev.fluttercommunity.plus.wakelock.**

# ─── url_launcher (intent dispatch only) ───────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }

# ─── Project's own native bridge ───────────────────────────────────────────
-keep class com.lifeostv.lifeostv.MainActivity { *; }

# ─── Parcelable Creators (Android requires this for Bundle marshalling) ────
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# ─── Enums used via Enum.valueOf / values() reflection ─────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
