#include "keyboard_layout/layout_memory.h"

#include <assert.h>
#include <stdint.h>

static void test_window_restore(void) {
  struct layout_memory memory;
  layout_memory_init(&memory, 0);
  assert(layout_memory_reset(&memory, 0xa, 1) == 0);

  int target = -1;
  assert(layout_memory_focus(&memory, 0xb, &target) == 0);
  assert(layout_memory_observe(&memory, 2) == 0);

  assert(layout_memory_focus(&memory, 0xa, &target) == 1);
  assert(target == 1);
  assert(layout_memory_observe(&memory, target) == 0);
  assert(layout_memory_focus(&memory, 0xb, &target) == 1);
  assert(target == 2);

  layout_memory_destroy(&memory);
}

static void test_unfocused_layout_is_not_attributed(void) {
  struct layout_memory memory;
  layout_memory_init(&memory, 0);
  assert(layout_memory_reset(&memory, 0xa, 1) == 0);

  int target = -1;
  assert(layout_memory_focus(&memory, 0, &target) == 0);
  assert(layout_memory_observe(&memory, 2) == 0);
  assert(layout_memory_focus(&memory, 0xa, &target) == 1);
  assert(target == 1);

  layout_memory_destroy(&memory);
}

static void test_close_and_reset_forget_saved_layouts(void) {
  struct layout_memory memory;
  layout_memory_init(&memory, 0);
  assert(layout_memory_reset(&memory, 0xa, 1) == 0);
  layout_memory_close(&memory, 0xa);

  int target = -1;
  assert(layout_memory_focus(&memory, 0xa, &target) == 0);
  assert(layout_memory_observe(&memory, 2) == 0);
  assert(layout_memory_reset(&memory, 0xb, 1) == 0);
  assert(layout_memory_focus(&memory, 0xa, &target) == 0);

  layout_memory_destroy(&memory);
}

static void test_more_than_64_windows(void) {
  struct layout_memory memory;
  layout_memory_init(&memory, 0);
  assert(layout_memory_reset(&memory, 1, 0) == 0);

  int target = -1;
  for (uint64_t window = 2; window <= 130; window++) {
    int result = layout_memory_focus(&memory, window, &target);
    assert(result >= 0);
    if (result > 0)
      assert(layout_memory_observe(&memory, target) == 0);
    assert(layout_memory_observe(&memory, (int)(window % 3)) == 0);
  }
  assert(memory.length == 130);

  assert(layout_memory_focus(&memory, 65, &target) == 1);
  assert(target == 2);
  layout_memory_destroy(&memory);
}

static void test_new_window_layout_follows_option(void) {
  struct layout_memory memory;
  layout_memory_init(&memory, 0);

  int target = -1;
  // By default an unseen window inherits the active layout.
  assert(layout_memory_reset(&memory, 0xa, 1) == 0);
  assert(layout_memory_focus(&memory, 0xb, &target) == 0);
  assert(layout_memory_observe(&memory, 2) == 0);

  // With a layout for new windows an unseen window starts on it.
  layout_memory_set_new_window_layout(&memory, 2);
  assert(layout_memory_reset(&memory, 0xc, 1) == 0);
  assert(layout_memory_focus(&memory, 0xd, &target) == 1);
  assert(target == 2);
  assert(layout_memory_observe(&memory, target) == 0);

  // A saved layout still wins.
  assert(layout_memory_focus(&memory, 0xc, &target) == 1);
  assert(target == 1);
  assert(layout_memory_observe(&memory, target) == 0);

  layout_memory_destroy(&memory);
}

static void test_window_address_parser(void) {
  uint64_t window = 99;
  assert(layout_memory_parse_window("", &window) == 0 && window == 0);
  assert(layout_memory_parse_window("0xabcdef", &window) == 0 &&
         window == 0xabcdef);
  assert(layout_memory_parse_window("abcdef", &window) == 0 &&
         window == 0xabcdef);
  assert(layout_memory_parse_window("0x1g", &window) == -1);
  assert(layout_memory_parse_window("-1", &window) == -1);
  assert(layout_memory_parse_window("+1", &window) == -1);
  assert(layout_memory_parse_window("xyz", &window) == -1);
}

int main(void) {
  test_window_restore();
  test_unfocused_layout_is_not_attributed();
  test_close_and_reset_forget_saved_layouts();
  test_more_than_64_windows();
  test_new_window_layout_follows_option();
  test_window_address_parser();
}
