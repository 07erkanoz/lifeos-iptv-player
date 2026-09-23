# LifeOsTV Linux renderer fix

Base: media_kit_video 2.0.1 from pub.dev, MIT (LICENSE retained).
The Dart API and Android/iOS/macOS/Windows sources are unchanged.

The upstream Linux renderer assumes an EGL context is current when its method
channel runs. GTK3 may have a GLX context current on that thread, while Flutter
renders on another thread. This made every hardware-enabled player fall back to
the CPU pixel buffer on the tested GNOME/XWayland/AMD system. Decoding became
VAAPI-copy while each displayed frame still required CPU conversion/upload.

Changes in linux/video_output.cc, linux/texture_gl.cc and graphics_context.h:

- Initialize the isolated EGL renderer from the explicit X11/Wayland display
  when no EGL context is current. Do not terminate the shared EGL display.
- Select a GLES-compatible RGBA config without assuming Flutter's EGL config is
  available on the platform thread.
- Save, release and restore GLX as well as EGL contexts around mpv operations.
  Merely calling eglMakeCurrent with a GLX context bound failed with EGL_BAD_ACCESS.
- Use the dimensions already pushed by the Dart videoParams subscription. Avoid
  synchronous mpv_get_property calls from the raster thread; mpv documents this
  as a deadlock hazard during core/render synchronization. Dimensions use atomic
  reads/writes across the platform and raster threads.
- Release the mpv renderer and texture resources before destroying their EGL
  context. Clean up partial hardware initialization before software fallback.

Keep software rendering available when hardware acceleration is disabled or
initialization fails. Do not replace this with a forced vendor-specific decoder.
On upstream upgrades, compare these three files and run the Linux release smoke
harness with native window captures, both decoder settings, fullscreen/PiP,
and repeated player disposal. Linux GLX and Wayland paths need separate checks.

Raw mpv screenshot readback returned null with the tested direct VAAPI frames;
native window screenshots are used to verify visible output in that mode.
