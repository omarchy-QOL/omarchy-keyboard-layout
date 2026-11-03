#include "keymap_internal.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <utf8proc.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon-names.h>

static const char *const key_names[] = {
    "ESC",  "FK01", "FK02", "FK03", "FK04", "FK05", "FK06", "FK07", "FK08",
    "FK09", "FK10", "FK11", "FK12", "TLDE", "AE01", "AE02", "AE03", "AE04",
    "AE05", "AE06", "AE07", "AE08", "AE09", "AE10", "AE11", "AE12", "AE13",
    "BKSP", "TAB",  "AD01", "AD02", "AD03", "AD04", "AD05", "AD06", "AD07",
    "AD08", "AD09", "AD10", "AD11", "AD12", "BKSL", "CAPS", "AC01", "AC02",
    "AC03", "AC04", "AC05", "AC06", "AC07", "AC08", "AC09", "AC10", "AC11",
    "RTRN", "LFSH", "LSGT", "AB01", "AB02", "AB03", "AB04", "AB05", "AB06",
    "AB07", "AB08", "AB09", "AB10", "AB11", "RTSH", "LCTL", "LWIN", "LALT",
    "SPCE", "RALT", "RWIN", "MENU", "RCTL", "LEFT", "UP",   "DOWN", "RGHT"};

static const struct {
  const char *name;
  const char *label;
} dead_labels[] = {
    {"dead_acute", "´"},    {"dead_grave", "`"},       {"dead_circumflex", "^"},
    {"dead_tilde", "~"},    {"dead_diaeresis", "¨"},   {"dead_cedilla", "¸"},
    {"dead_caron", "ˇ"},    {"dead_breve", "˘"},       {"dead_abovering", "˚"},
    {"dead_macron", "¯"},   {"dead_doubleacute", "˝"}, {"dead_ogonek", "˛"},
    {"dead_abovedot", "˙"}, {"dead_belowdot", "◌̣"},    {"dead_hook", "◌̉"},
    {"dead_horn", "◌̛"},     {"dead_stroke", "/"},      {"dead_belowcomma", "◌̦"},
    {"dead_greek", "α"},    {"dead_currency", "¤"}};

static xkb_mod_mask_t modifier_mask(struct xkb_keymap *keymap,
                                    const char *name) {
  xkb_mod_index_t index = xkb_keymap_mod_get_index(keymap, name);
  return index < sizeof(xkb_mod_mask_t) * 8 ? (xkb_mod_mask_t)1 << index : 0;
}

static const char *find_level3_key(struct xkb_keymap *keymap,
                                   xkb_layout_index_t group) {
  static const char *const candidates[] = {
      "RALT", "CAPS", "LSGT", "BKSL", "MENU", "RWIN", "LWIN", "RCTL", "LALT"};
  for (size_t index = 0; index < sizeof(candidates) / sizeof(candidates[0]);
       index++) {
    xkb_keycode_t code = xkb_keymap_key_by_name(keymap, candidates[index]);
    const xkb_keysym_t *symbols = NULL;
    int count =
        xkb_keymap_key_get_syms_by_level(keymap, code, group, 0, &symbols);
    if (count == 1 && symbols[0] == XKB_KEY_ISO_Level3_Shift)
      return candidates[index];
  }
  return "";
}

static xkb_mod_mask_t level3_mask(struct xkb_keymap *keymap,
                                  xkb_layout_index_t group, const char *name) {
  if (!name[0])
    return 0;
  struct xkb_state *state = xkb_state_new(keymap);
  if (!state)
    return 0;
  xkb_state_update_mask(state, 0, 0, 0, 0, 0, group);
  xkb_state_update_key(state, xkb_keymap_key_by_name(keymap, name),
                       XKB_KEY_DOWN);
  xkb_mod_mask_t mask =
      xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED);
  xkb_state_unref(state);
  return mask;
}

static int append_symbol(char *text, size_t *length, xkb_keysym_t symbol) {
  uint32_t point = xkb_keysym_to_utf32(symbol);
  if (!point)
    return 0;
  utf8proc_category_t category = utf8proc_category((utf8proc_int32_t)point);
  if (category == UTF8PROC_CATEGORY_CC || category == UTF8PROC_CATEGORY_CF ||
      category == UTF8PROC_CATEGORY_CS)
    return 0;
  utf8proc_uint8_t encoded[4];
  utf8proc_ssize_t count =
      utf8proc_encode_char((utf8proc_int32_t)point, encoded);
  if (count <= 0 || *length + (size_t)count > KEYMAP_TEXT_LIMIT)
    return -1;
  memcpy(text + *length, encoded, (size_t)count);
  *length += (size_t)count;
  text[*length] = '\0';
  return 0;
}

static const char *dead_label(const char *name) {
  for (size_t index = 0; index < sizeof(dead_labels) / sizeof(dead_labels[0]);
       index++)
    if (strcmp(name, dead_labels[index].name) == 0)
      return dead_labels[index].label;
  return "";
}

static int describe_key_state(struct xkb_state *state, xkb_keycode_t code,
                              struct json_object **result) {
  *result = NULL;
  const xkb_keysym_t *symbols = NULL;
  xkb_keysym_t single = xkb_state_key_get_one_sym(state, code);
  int count = single ? 1 : xkb_state_key_get_syms(state, code, &symbols);
  if (single)
    symbols = &single;
  if (count <= 0)
    return 0;
  if (count > 32)
    return -1;

  char symbol_name[128];
  if (xkb_keysym_get_name(symbols[0], symbol_name, sizeof(symbol_name)) <= 0)
    return -1;
  bool is_dead = count == 1 && strncmp(symbol_name, "dead_", 5) == 0;
  char text[KEYMAP_TEXT_LIMIT + 1] = "";
  size_t length = 0;
  if (!is_dead)
    for (int index = 0; index < count; index++)
      if (append_symbol(text, &length, symbols[index]) != 0)
        return -1;

  char label[KEYMAP_TEXT_LIMIT + 5];
  utf8proc_int32_t point = 0;
  utf8proc_ssize_t first_size = utf8proc_iterate(
      (const utf8proc_uint8_t *)text, (utf8proc_ssize_t)length, &point);
  if (is_dead) {
    snprintf(label, sizeof(label), "%s", dead_label(symbol_name));
  } else if (first_size > 0 && (size_t)first_size == length &&
             utf8proc_get_property(point)->combining_class != 0) {
    snprintf(label, sizeof(label), "◌%s", text);
  } else {
    snprintf(label, sizeof(label), "%s", text[0] ? text : symbol_name);
  }

  struct json_object *entry = json_object_new_object();
  if (!entry)
    return -1;
  json_object_object_add(entry, "keysym", json_object_new_string(symbol_name));
  json_object_object_add(entry, "label", json_object_new_string(label));
  json_object_object_add(entry, "text", json_object_new_string(text));
  json_object_object_add(entry, "dead",
                         json_object_new_string(is_dead ? symbol_name : ""));
  *result = entry;
  return 0;
}

struct json_object *keymap_collect_keys(struct xkb_keymap *keymap,
                                        xkb_layout_index_t group,
                                        const char **level3_key) {
  struct json_object *keys = json_object_new_object();
  struct xkb_state *state = xkb_state_new(keymap);
  if (!keys || !state) {
    json_object_put(keys);
    xkb_state_unref(state);
    return NULL;
  }
  xkb_mod_mask_t shift = modifier_mask(keymap, XKB_MOD_NAME_SHIFT);
  xkb_mod_mask_t caps = modifier_mask(keymap, XKB_MOD_NAME_CAPS);
  *level3_key = find_level3_key(keymap, group);
  xkb_mod_mask_t level3 = level3_mask(keymap, group, *level3_key);

  for (size_t index = 0; index < sizeof(key_names) / sizeof(key_names[0]);
       index++) {
    xkb_keycode_t code = xkb_keymap_key_by_name(keymap, key_names[index]);
    if (code == XKB_KEYCODE_INVALID)
      continue;
    struct json_object *states = json_object_new_array_ext(8);
    struct json_object *key = json_object_new_object();
    if (!states || !key) {
      json_object_put(states);
      json_object_put(key);
      goto failure;
    }
    bool has_symbols = false;
    for (unsigned int flags = 0; flags < 8; flags++) {
      xkb_mod_mask_t depressed =
          ((flags & 1u) ? shift : 0) | ((flags & 4u) ? level3 : 0);
      xkb_state_update_mask(state, depressed, 0, (flags & 2u) ? caps : 0, 0, 0,
                            group);
      struct json_object *entry = NULL;
      if (describe_key_state(state, code, &entry) != 0) {
        json_object_put(states);
        json_object_put(key);
        goto failure;
      }
      has_symbols = has_symbols || entry != NULL;
      json_object_array_add(states, entry);
    }
    if (has_symbols) {
      json_object_object_add(key, "states", states);
      json_object_object_add(keys, key_names[index], key);
    } else {
      json_object_put(states);
      json_object_put(key);
    }
  }
  xkb_state_unref(state);
  return keys;

failure:
  xkb_state_unref(state);
  json_object_put(keys);
  return NULL;
}
