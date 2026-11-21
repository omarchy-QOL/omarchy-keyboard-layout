#ifndef KEYBOARD_LAYOUT_MEMORY_H
#define KEYBOARD_LAYOUT_MEMORY_H

#include <stddef.h>
#include <stdint.h>

struct window_layout {
  uint64_t window;
  int layout;
};

struct layout_memory {
  struct window_layout *windows;
  size_t length;
  size_t capacity;
  uint64_t focused_window;
  int active_layout;
  int default_layout;
  int new_window_layout;
};

void layout_memory_init(struct layout_memory *memory, int default_layout);
void layout_memory_set_new_window_layout(struct layout_memory *memory,
                                         int layout);
void layout_memory_destroy(struct layout_memory *memory);
int layout_memory_reset(struct layout_memory *memory, uint64_t focused_window,
                        int active_layout);
int layout_memory_observe(struct layout_memory *memory, int layout);
int layout_memory_focus(struct layout_memory *memory, uint64_t window,
                        int *target_layout);
void layout_memory_close(struct layout_memory *memory, uint64_t window);
int layout_memory_parse_window(const char *value, uint64_t *window);

#endif
