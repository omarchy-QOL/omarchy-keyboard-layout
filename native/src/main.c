#include "keyboard_layout/hypr_ipc.h"
#include "keyboard_layout/keymap.h"
#include "keyboard_layout/layout_memory.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

enum { DEFAULT_LAYOUT = 0, EVENT_SIZE = 4096 };

struct app {
  struct hypr_ipc ipc;
  struct layout_memory memory;
};

static volatile sig_atomic_t stop_requested;

static void request_stop(int signal_number) {
  (void)signal_number;
  stop_requested = 1;
}

static void sync_state(struct app *app) {
  uint64_t window = 0;
  int layout = -1;
  hypr_ipc_active_window(&app->ipc, &window);
  hypr_ipc_current_layout(&app->ipc, &layout);
  if (layout_memory_reset(&app->memory, window, layout) != 0)
    fprintf(stderr, "keyboard-layoutd: could not initialize memory\n");
}

static void focus_window(struct app *app, const char *data) {
  uint64_t window = 0;
  int target = -1;
  if (layout_memory_parse_window(data, &window) != 0)
    return;

  int result = layout_memory_focus(&app->memory, window, &target);
  if (result < 0) {
    fprintf(stderr, "keyboard-layoutd: could not remember layout\n");
  } else if (result > 0) {
    printf("restore:%d\n", target);
    fflush(stdout);
    if (hypr_ipc_switch_layout(&app->ipc, target) == 0) {
      layout_memory_observe(&app->memory, target);
    } else {
      fprintf(stderr, "keyboard-layoutd: could not restore layout %d\n",
              target);
    }
  }
}

static void observe_layout(struct app *app, char *data) {
  char *separator = strchr(data, ',');
  if (separator == NULL || separator == data)
    return;
  *separator = '\0';
  if (!hypr_keyboard_is_typing(data))
    return;

  int layout = -1;
  if (hypr_ipc_device_layout(&app->ipc, data, &layout) == 0 &&
      layout_memory_observe(&app->memory, layout) != 0)
    fprintf(stderr, "keyboard-layoutd: could not remember layout\n");
}

static void handle_event(struct app *app, char *line) {
  char *separator = strstr(line, ">>");
  if (separator == NULL)
    return;
  *separator = '\0';
  char *data = separator + 2;

  if (strcmp(line, "activewindowv2") == 0) {
    focus_window(app, data);
  } else if (strcmp(line, "activelayout") == 0) {
    observe_layout(app, data);
  } else if (strcmp(line, "closewindow") == 0) {
    uint64_t window = 0;
    if (layout_memory_parse_window(data, &window) == 0)
      layout_memory_close(&app->memory, window);
  } else if (strcmp(line, "configreloaded") == 0) {
    sync_state(app);
  }
}

static void read_events(int socket_fd, struct app *app) {
  char chunk[EVENT_SIZE];
  char line[EVENT_SIZE];
  size_t length = 0;
  int discarding = 0;

  while (!stop_requested) {
    ssize_t count = read(socket_fd, chunk, sizeof(chunk));
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return;

    for (ssize_t i = 0; i < count; i++) {
      if (chunk[i] == '\n') {
        if (!discarding) {
          line[length] = '\0';
          handle_event(app, line);
        }
        length = 0;
        discarding = 0;
      } else if (!discarding && length < sizeof(line) - 1) {
        line[length++] = chunk[i];
      } else {
        discarding = 1;
      }
    }
  }
}

static void reconnect_delay(void) {
  struct timespec delay = {.tv_sec = 1};
  while (!stop_requested && nanosleep(&delay, &delay) != 0 && errno == EINTR) {
  }
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "--probe") == 0) {
    puts("{\"schemaVersion\":1,\"keymap\":true,\"tracking\":true}");
    return EXIT_SUCCESS;
  }
  if (argc == 2 && strcmp(argv[1], "--describe-keymap") == 0)
    return keymap_describe(stdin, stdout);
  if (argc != 1) {
    fprintf(stderr, "usage: keyboard-layoutd [--probe | --describe-keymap]\n");
    return EXIT_FAILURE;
  }
  struct sigaction action = {.sa_handler = request_stop};
  sigemptyset(&action.sa_mask);
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);

  struct app app;
  if (hypr_ipc_init(&app.ipc, getenv("XDG_RUNTIME_DIR"),
                    getenv("HYPRLAND_INSTANCE_SIGNATURE")) != 0) {
    fprintf(stderr, "keyboard-layoutd: invalid Hyprland environment\n");
    return EXIT_FAILURE;
  }

  layout_memory_init(&app.memory, DEFAULT_LAYOUT);
  while (!stop_requested) {
    int socket_fd = hypr_ipc_connect_events(&app.ipc);
    if (socket_fd >= 0) {
      sync_state(&app);
      read_events(socket_fd, &app);
      close(socket_fd);
    }
    if (!stop_requested)
      reconnect_delay();
  }
  layout_memory_destroy(&app.memory);
  return EXIT_SUCCESS;
}
