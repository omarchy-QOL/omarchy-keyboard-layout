#include "keymap_internal.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <utf8proc.h>
#include <xkbcommon/xkbcommon-compose.h>

struct symbol_list {
  const char *names[KEYMAP_SYMBOL_LIMIT];
  size_t count;
};

static int add_symbol(struct symbol_list *list, const char *name) {
  for (size_t index = 0; index < list->count; index++)
    if (strcmp(list->names[index], name) == 0)
      return 0;
  if (list->count == KEYMAP_SYMBOL_LIMIT)
    return -1;
  list->names[list->count++] = name;
  return 0;
}

static const char *entry_string(const struct json_object *entry,
                                const char *name) {
  struct json_object *field = NULL;
  return json_object_object_get_ex(entry, name, &field)
             ? json_object_get_string(field)
             : "";
}

static int collect_symbols(struct json_object *keys, struct symbol_list *dead,
                           struct symbol_list *followers) {
  json_object_object_foreach(keys, key_name, key) {
    (void)key_name;
    struct json_object *states = NULL;
    if (!json_object_object_get_ex(key, "states", &states))
      continue;
    for (size_t index = 0; index < json_object_array_length(states); index++) {
      struct json_object *entry = json_object_array_get_idx(states, index);
      if (!entry)
        continue;
      const char *name = entry_string(entry, "keysym");
      const char *dead_name = entry_string(entry, "dead");
      if (add_symbol(followers, name) != 0 ||
          (dead_name[0] && add_symbol(dead, dead_name) != 0))
        return -1;
    }
  }
  return add_symbol(followers, "space");
}

static struct xkb_compose_table *
load_compose_table(struct xkb_context *context) {
  const char *locales[] = {getenv("LC_ALL"), getenv("LC_CTYPE"), getenv("LANG"),
                           "C.UTF-8", "en_US.UTF-8"};
  for (size_t index = 0; index < sizeof(locales) / sizeof(locales[0]);
       index++) {
    if (!locales[index] || !locales[index][0])
      continue;
    struct xkb_compose_table *table = xkb_compose_table_new_from_locale(
        context, locales[index], XKB_COMPOSE_COMPILE_NO_FLAGS);
    if (table)
      return table;
  }
  return NULL;
}

static int compose_text(struct xkb_compose_state *state, const char *first,
                        const char *second, char *text, size_t capacity) {
  xkb_keysym_t prefix = xkb_keysym_from_name(first, XKB_KEYSYM_NO_FLAGS);
  xkb_keysym_t suffix = xkb_keysym_from_name(second, XKB_KEYSYM_NO_FLAGS);
  text[0] = '\0';
  if (!prefix || !suffix)
    return 0;
  xkb_compose_state_reset(state);
  xkb_compose_state_feed(state, prefix);
  xkb_compose_state_feed(state, suffix);
  if (xkb_compose_state_get_status(state) != XKB_COMPOSE_COMPOSED)
    return 0;
  int length = xkb_compose_state_get_utf8(state, text, capacity);
  if (length < 0 || (size_t)length >= capacity)
    return -1;
  return 0;
}

static bool is_letter(const char *text) {
  utf8proc_int32_t point = 0;
  size_t length = strlen(text);
  utf8proc_ssize_t count = utf8proc_iterate((const utf8proc_uint8_t *)text,
                                            (utf8proc_ssize_t)length, &point);
  if (count <= 0 || (size_t)count != length)
    return false;
  utf8proc_category_t category = utf8proc_category(point);
  return category >= UTF8PROC_CATEGORY_LU && category <= UTF8PROC_CATEGORY_LO;
}

static void append_choice(struct json_object *choices, const char *text) {
  if (!is_letter(text) || json_object_array_length(choices) >= 12)
    return;
  for (size_t index = 0; index < json_object_array_length(choices); index++)
    if (strcmp(
            json_object_get_string(json_object_array_get_idx(choices, index)),
            text) == 0)
      return;
  json_object_array_add(choices, json_object_new_string(text));
}

static int add_letter_accents(struct xkb_compose_state *state,
                              const struct json_object *entry,
                              struct json_object *accents) {
  const char *letter = entry_string(entry, "text");
  if (!is_letter(letter) || json_object_object_get_ex(accents, letter, NULL))
    return 0;
  static const char *const accent_keys[] = {
      "dead_grave",       "dead_acute",     "dead_circumflex", "dead_diaeresis",
      "dead_tilde",       "dead_abovering", "dead_macron",     "dead_abovedot",
      "dead_ogonek",      "dead_cedilla",   "dead_caron",      "dead_breve",
      "dead_doubleacute", "dead_stroke"};
  struct json_object *choices = json_object_new_array();
  if (!choices)
    return -1;
  for (size_t index = 0; index < sizeof(accent_keys) / sizeof(accent_keys[0]);
       index++) {
    char composed[KEYMAP_TEXT_LIMIT + 1];
    if (compose_text(state, accent_keys[index], entry_string(entry, "keysym"),
                     composed, sizeof(composed)) != 0) {
      json_object_put(choices);
      return -1;
    }
    append_choice(choices, composed);
  }
  static const struct {
    const char *letter;
    const char *choices[2];
  } extra[] = {{"a", {"æ", NULL}},
               {"A", {"Æ", NULL}},
               {"o", {"œ", "ø"}},
               {"O", {"Œ", "Ø"}},
               {"s", {"ß", NULL}}};
  for (size_t index = 0; index < sizeof(extra) / sizeof(extra[0]); index++)
    if (strcmp(letter, extra[index].letter) == 0)
      for (size_t choice = 0; choice < 2; choice++)
        if (extra[index].choices[choice])
          append_choice(choices, extra[index].choices[choice]);
  if (json_object_array_length(choices))
    json_object_object_add(accents, letter, choices);
  else
    json_object_put(choices);
  return 0;
}

int keymap_add_compositions(struct xkb_context *context,
                            struct json_object *description) {
  struct json_object *pairs = json_object_new_object();
  struct json_object *accents = json_object_new_object();
  struct json_object *keys = NULL;
  if (!pairs || !accents) {
    json_object_put(pairs);
    json_object_put(accents);
    return -1;
  }
  json_object_object_add(description, "compose", pairs);
  json_object_object_add(description, "accents", accents);
  struct xkb_compose_table *table = load_compose_table(context);
  if (!table)
    return 0;
  struct xkb_compose_state *state =
      xkb_compose_state_new(table, XKB_COMPOSE_STATE_NO_FLAGS);
  xkb_compose_table_unref(table);
  if (!state)
    return -1;
  json_object_object_get_ex(description, "keys", &keys);
  struct symbol_list dead = {0}, followers = {0};
  int result = collect_symbols(keys, &dead, &followers);
  size_t pair_count = 0;
  for (size_t prefix = 0; result == 0 && prefix < dead.count; prefix++) {
    struct json_object *results = json_object_new_object();
    if (!results) {
      result = -1;
      break;
    }
    for (size_t suffix = 0; suffix < followers.count; suffix++) {
      char text[KEYMAP_TEXT_LIMIT + 1];
      if (compose_text(state, dead.names[prefix], followers.names[suffix], text,
                       sizeof(text)) != 0) {
        result = -1;
        break;
      }
      if (text[0]) {
        if (++pair_count > 4096) {
          result = -1;
          break;
        }
        json_object_object_add(results, followers.names[suffix],
                               json_object_new_string(text));
      }
    }
    json_object_object_add(pairs, dead.names[prefix], results);
  }
  if (result == 0) {
    json_object_object_foreach(keys, key_name, key) {
      (void)key_name;
      struct json_object *states = NULL;
      json_object_object_get_ex(key, "states", &states);
      for (size_t index = 0; index < json_object_array_length(states);
           index++) {
        struct json_object *entry = json_object_array_get_idx(states, index);
        if (entry && add_letter_accents(state, entry, accents) != 0)
          result = -1;
      }
    }
  }
  xkb_compose_state_unref(state);
  return result;
}
