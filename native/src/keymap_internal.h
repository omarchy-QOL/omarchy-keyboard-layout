#ifndef KEYBOARD_LAYOUT_KEYMAP_INTERNAL_H
#define KEYBOARD_LAYOUT_KEYMAP_INTERNAL_H

#include <json-c/json.h>
#include <xkbcommon/xkbcommon.h>

enum {
  KEYMAP_REQUEST_LIMIT = 65536,
  KEYMAP_FILE_LIMIT = 1048576,
  KEYMAP_OUTPUT_LIMIT = 1048576,
  KEYMAP_TEXT_LIMIT = 256,
  KEYMAP_SYMBOL_LIMIT = 512
};

struct json_object *keymap_collect_keys(struct xkb_keymap *keymap,
                                        xkb_layout_index_t group,
                                        const char **level3_key);
int keymap_add_compositions(struct xkb_context *context,
                            struct json_object *description);

#endif
