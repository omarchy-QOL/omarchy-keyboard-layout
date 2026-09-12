#include "keyboard_layout/layout_memory.h"

#include <errno.h>
#include <stdlib.h>

static struct window_layout *find_window(struct layout_memory *memory,
                                         uint64_t window) {
  for (size_t i = 0; i < memory->length; i++) {
    if (memory->windows[i].window == window)
      return &memory->windows[i];
  }
  return NULL;
}

static int remember_layout(struct layout_memory *memory, uint64_t window,
                           int layout) {
  struct window_layout *entry = find_window(memory, window);
  if (entry != NULL) {
    entry->layout = layout;
    return 0;
  }

  if (memory->length == memory->capacity) {
    if (memory->capacity > SIZE_MAX / 2)
      return -1;
    size_t next_capacity = memory->capacity == 0 ? 16 : memory->capacity * 2;
    if (next_capacity > SIZE_MAX / sizeof(*memory->windows))
      return -1;
    void *next =
        realloc(memory->windows, next_capacity * sizeof(*memory->windows));
    if (next == NULL)
      return -1;
    memory->windows = next;
    memory->capacity = next_capacity;
  }

  memory->windows[memory->length++] =
      (struct window_layout){.window = window, .layout = layout};
  return 0;
}

void layout_memory_init(struct layout_memory *memory, int default_layout) {
  *memory = (struct layout_memory){
      .active_layout = -1,
      .default_layout = default_layout,
  };
}

void layout_memory_destroy(struct layout_memory *memory) {
  free(memory->windows);
  memory->windows = NULL;
  memory->length = 0;
  memory->capacity = 0;
}

int layout_memory_reset(struct layout_memory *memory, uint64_t focused_window,
                        int active_layout) {
  memory->length = 0;
  memory->focused_window = focused_window;
  memory->active_layout = active_layout;
  if (focused_window == 0 || active_layout < 0)
    return 0;
  return remember_layout(memory, focused_window, active_layout);
}

int layout_memory_observe(struct layout_memory *memory, int layout) {
  if (layout < 0)
    return -1;

  memory->active_layout = layout;
  if (memory->focused_window == 0)
    return 0;
  return remember_layout(memory, memory->focused_window, layout);
}

int layout_memory_focus(struct layout_memory *memory, uint64_t window,
                        int *target_layout) {
  if (window == memory->focused_window)
    return 0;

  if (memory->focused_window != 0 && memory->active_layout >= 0 &&
      remember_layout(memory, memory->focused_window, memory->active_layout) !=
          0)
    return -1;

  memory->focused_window = window;
  if (window == 0)
    return 0;

  struct window_layout *entry = find_window(memory, window);
  int target = entry == NULL ? memory->active_layout : entry->layout;
  if (target < 0)
    target = memory->default_layout;
  if (target == memory->active_layout)
    return 0;

  *target_layout = target;
  return 1;
}

void layout_memory_close(struct layout_memory *memory, uint64_t window) {
  for (size_t i = 0; i < memory->length; i++) {
    if (memory->windows[i].window != window)
      continue;
    memory->windows[i] = memory->windows[--memory->length];
    break;
  }
  if (memory->focused_window == window)
    memory->focused_window = 0;
}

int layout_memory_parse_window(const char *value, uint64_t *window) {
  if (value == NULL || value[0] == '\0') {
    *window = 0;
    return 0;
  }
  if (value[0] == '-' || value[0] == '+')
    return -1;

  errno = 0;
  char *end = NULL;
  unsigned long long parsed = strtoull(value, &end, 16);
  if (errno == ERANGE || end == value || *end != '\0')
    return -1;

  *window = (uint64_t)parsed;
  return 0;
}
