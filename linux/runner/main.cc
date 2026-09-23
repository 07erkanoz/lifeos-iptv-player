#include "my_application.h"

int main(int argc, char** argv) {
  // GTK3 cannot request keep-above or absolute window positioning on Wayland.
  // Prefer X11/XWayland for desktop PiP when available. Honour an explicit
  // GDK_BACKEND, and retain native Wayland on systems without XWayland.
  if (g_getenv("GDK_BACKEND") == nullptr && g_getenv("DISPLAY") != nullptr) {
    gdk_set_allowed_backends("x11,wayland");
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
