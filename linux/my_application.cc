#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  
  // Use X11 rendering directly when possible
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
      gtk_window_set_default_visual(window, gdk_screen_get_system_visual(screen));
  }

  // Set up window
  gtk_window_set_title(window, "Wine Prefix Manager");
  gtk_window_set_default_size(window, 1000, 700);
  
  // Force software rendering mode for GTK visuals
  const char* software_gl = g_getenv("LIBGL_ALWAYS_SOFTWARE");
  if (software_gl == nullptr) {
    g_setenv("LIBGL_ALWAYS_SOFTWARE", "1", TRUE);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  FlView* view = fl_view_new(project);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_show_all(GTK_WIDGET(window));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::open.
static void my_application_open(GApplication* application,
                                GFile** files,
                                gint n_files,
                                const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  // Handle file opening logic here
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

// Implements GObject::class_init.
static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

// Implements GObject::init.
static void my_application_init(MyApplication* self) {}

// Creates a new instance of MyApplication.
MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", "com.example.wine_prefix_manager",
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}