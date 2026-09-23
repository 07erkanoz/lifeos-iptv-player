// LifeOsTV Linux integration. Preserve both GTK/Flutter GLX and EGL contexts
// while rendering into mpv's isolated EGL context. MIT; see ../LICENSE.
#pragma once
#include <epoxy/egl.h>
#include <epoxy/glx.h>

class GraphicsContextGuard {
public:
  GraphicsContextGuard()
      : egl_display_(eglGetCurrentDisplay()),
        egl_context_(eglGetCurrentContext()),
        egl_draw_(eglGetCurrentSurface(EGL_DRAW)),
        egl_read_(eglGetCurrentSurface(EGL_READ)), api_(eglQueryAPI()),
        glx_display_(glXGetCurrentDisplay()),
        glx_context_(glXGetCurrentContext()),
        glx_draw_(glXGetCurrentDrawable()),
        glx_read_(glXGetCurrentReadDrawable()) {}
  ~GraphicsContextGuard() { restore(); }
  bool makeCurrent(EGLDisplay display, EGLContext context) {
    changed_ = true;
    if (glXGetCurrentContext() != nullptr) {
      glXMakeContextCurrent(glXGetCurrentDisplay(), None, None, nullptr);
    }
    eglBindAPI(EGL_OPENGL_ES_API);
    return eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context);
  }
  void restore() {
    if (!changed_)
      return;
    const auto current = eglGetCurrentDisplay();
    if (current != EGL_NO_DISPLAY) {
      eglMakeCurrent(current, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    eglBindAPI(api_);
    if (glx_context_ != nullptr) {
      glXMakeContextCurrent(glx_display_, glx_draw_, glx_read_, glx_context_);
    } else if (egl_context_ != EGL_NO_CONTEXT) {
      eglMakeCurrent(egl_display_, egl_draw_, egl_read_, egl_context_);
    }
    changed_ = false;
  }

private:
  EGLDisplay egl_display_;
  EGLContext egl_context_;
  EGLSurface egl_draw_, egl_read_;
  EGLenum api_;
  Display *glx_display_;
  GLXContext glx_context_;
  GLXDrawable glx_draw_, glx_read_;
  bool changed_ = false;
};
