# Keep rules for when release shrinking (R8) is enabled.
# This file is currently NOT wired in – release builds do not enable minify.
# To activate: set `isMinifyEnabled = true` + `isShrinkResources = true` on the
# release buildType and add `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")`.

# media_kit + libmpv native bindings
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-keep class com.alexmercerind.** { *; }

# media_kit uses reflection + JNI to reach libmpv
-keep class io.github.** { *; }
-keepclassmembers class * {
    native <methods>;
}

# Kotlin metadata (coroutines / reflection in plugins)
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Chromecast / Google Cast SDK
-keep class com.google.android.gms.cast.** { *; }
-dontwarn com.google.android.gms.cast.**

# Keep Flutter embedding
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }

# Drift (moor) uses reflection on generated classes
-keep class drift.** { *; }
-dontwarn drift.**

# Window Manager plugin
-keep class com.example.window_manager.** { *; }

# Keep line numbers for crash reports
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
