#include "keyboard_layout/hypr_ipc.h"

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

static const char *devices =
    "{\"keyboards\":["
    "{\"name\":\"video-bus\",\"active_layout_index\":2,\"main\":false},"
    "{\"name\":\"physical-keyboard\",\"active_layout_index\":1,"
    "\"main\":false},"
    "{\"name\":\"typing-main\",\"active_layout_index\":3,\"main\":true},"
    "{\"name\":\"hl-virtual-keyboard-ime\","
    "\"active_layout_index\":4,\"main\":true}]}";

static void test_active_window(void) {
  uint64_t window = 0;
  assert(hypr_json_active_window("{\"address\":\"0x1a2b\"}", &window) == 0);
  assert(window == 0x1a2b);
  assert(hypr_json_active_window("{}", &window) == -1);
  assert(hypr_json_active_window("{\"address\":17}", &window) == -1);
}

static void test_device_layout(void) {
  int layout = -1;
  assert(hypr_json_device_layout(devices, "physical-keyboard", &layout) == 0);
  assert(layout == 1);
  assert(hypr_json_device_layout(devices, "missing", &layout) == -1);
  assert(hypr_json_device_layout(devices, NULL, &layout) == -1);
  assert(hypr_json_device_layout("{\"keyboards\":[]}", "missing", &layout) ==
         -1);
}

static void test_current_layout_prefers_main_typing_keyboard(void) {
  int layout = -1;
  assert(hypr_json_current_layout(devices, &layout) == 0);
  assert(layout == 3);

  const char *fallback = "{\"keyboards\":[{\"name\":\"video-bus\","
                         "\"active_layout_index\":2,\"main\":false}]}";
  assert(hypr_json_current_layout(fallback, &layout) == 0);
  assert(layout == 2);
  assert(hypr_json_current_layout("{\"keyboards\":[]}", &layout) == -1);
}

static void test_typing_keyboard_filter(void) {
  assert(hypr_keyboard_is_typing("physical-keyboard"));
  assert(!hypr_keyboard_is_typing("hl-virtual-keyboard-ime"));
  assert(!hypr_keyboard_is_typing("keyboard-system-control"));
  assert(!hypr_keyboard_is_typing("keyboard-consumer-control"));
  assert(!hypr_keyboard_is_typing("video-bus"));
  assert(!hypr_keyboard_is_typing("power-button-1"));
  assert(!hypr_keyboard_is_typing(NULL));
}

static void test_invalid_json(void) {
  int layout = -1;
  assert(hypr_json_current_layout("not json", &layout) == -1);
  assert(hypr_json_current_layout("{\"keyboards\":{}}", &layout) == -1);
  assert(hypr_json_device_layout("{\"keyboards\":[{\"name\":\"keyboard\","
                                 "\"active_layout_index\":\"1\"}]}",
                                 "keyboard", &layout) == -1);

  const char *wrong_main_type =
      "{\"keyboards\":["
      "{\"name\":\"first\",\"active_layout_index\":1,"
      "\"main\":false},"
      "{\"name\":\"second\",\"active_layout_index\":2,"
      "\"main\":\"false\"}]}";
  assert(hypr_json_current_layout(wrong_main_type, &layout) == 0);
  assert(layout == 1);
}

static void test_ipc_environment(void) {
  struct hypr_ipc ipc;
  char long_path[sizeof(ipc.control_address.sun_path) + 1];
  memset(long_path, 'x', sizeof(long_path) - 1);
  long_path[sizeof(long_path) - 1] = '\0';

  assert(hypr_ipc_init(&ipc, NULL, "signature") == -1);
  assert(hypr_ipc_init(&ipc, "", "signature") == -1);
  assert(hypr_ipc_init(&ipc, "/run/user/1000", "") == -1);
  assert(hypr_ipc_init(&ipc, long_path, "signature") == -1);
}

int main(void) {
  test_active_window();
  test_device_layout();
  test_current_layout_prefers_main_typing_keyboard();
  test_typing_keyboard_filter();
  test_invalid_json();
  test_ipc_environment();
}
