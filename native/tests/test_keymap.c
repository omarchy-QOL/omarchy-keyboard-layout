#include "keyboard_layout/keymap.h"

#include <assert.h>
#include <json-c/json.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>

#ifndef KEYMAP_FIXTURE_PATH
#define KEYMAP_FIXTURE_PATH "tests/fixtures/keymap-reference.json"
#endif

static struct json_object *describe_text(const char *request,
                                         int expected_status) {
  FILE *input = tmpfile();
  FILE *output = tmpfile();
  assert(input && output);
  assert(fputs(request, input) >= 0);
  rewind(input);
  int status = keymap_describe(input, output);
  assert((status == 0) == (expected_status == 0));
  assert(fflush(output) == 0);
  long length = ftell(output);
  assert(length >= 0 && length <= 1048576);
  struct json_object *description = NULL;
  if (status == 0) {
    char *text = calloc((size_t)length + 1, 1);
    assert(text);
    rewind(output);
    assert(fread(text, 1, (size_t)length, output) == (size_t)length);
    description = json_tokener_parse(text);
    free(text);
    assert(description);
  } else {
    assert(length == 0);
  }
  fclose(input);
  fclose(output);
  return description;
}

static struct json_object *describe(struct json_object *request) {
  return describe_text(json_object_to_json_string(request), 0);
}

static struct json_object *field(struct json_object *object, const char *name) {
  struct json_object *value = NULL;
  assert(json_object_object_get_ex(object, name, &value));
  return value;
}

static const char *text_field(struct json_object *object, const char *name) {
  struct json_object *value = field(object, name);
  assert(json_object_is_type(value, json_type_string));
  return json_object_get_string(value);
}

static struct json_object *key_state(struct json_object *description,
                                     const char *name, size_t state) {
  struct json_object *key = field(field(description, "keys"), name);
  return json_object_array_get_idx(field(key, "states"), state);
}

static void test_reference_cases(void) {
  struct json_object *cases = json_object_from_file(KEYMAP_FIXTURE_PATH);
  assert(cases);
  for (size_t index = 0; index < json_object_array_length(cases); index++) {
    struct json_object *test = json_object_array_get_idx(cases, index);
    struct json_object *actual = describe(field(test, "request"));
    struct json_object *expected = field(test, "expected");
    struct json_object *expected_keys = field(expected, "keys");
    json_object_object_foreach(expected_keys, name, key) {
      assert(json_object_equal(field(field(actual, "keys"), name), key));
    }
    assert(strcmp(text_field(actual, "altGrKey"),
                  text_field(expected, "altGrKey")) == 0);
    struct json_object *expected_compose = field(expected, "compose");
    json_object_object_foreach(expected_compose, prefix, pairs) {
      struct json_object *actual_pairs =
          field(field(actual, "compose"), prefix);
      json_object_object_foreach(pairs, suffix, text) {
        assert(json_object_equal(field(actual_pairs, suffix), text));
      }
    }
    assert(json_object_equal(field(actual, "accents"),
                             field(expected, "accents")));
    json_object_put(actual);
  }
  json_object_put(cases);
}

static void test_active_groups(void) {
  struct json_object *request = json_tokener_parse(
      "{\"layouts\":\"us,de\",\"variants\":\",\",\"group\":1}");
  struct json_object *description = describe(request);
  assert(strcmp(text_field(key_state(description, "AD06", 0), "text"), "z") ==
         0);
  assert(strcmp(text_field(key_state(description, "AD11", 0), "text"), "ü") ==
         0);
  assert(strcmp(text_field(key_state(description, "AD01", 4), "text"), "@") ==
         0);
  assert(strcmp(text_field(description, "altGrKey"), "RALT") == 0);
  json_object_put(description);
  json_object_object_add(request, "layouts", json_object_new_string("us,us"));
  json_object_object_add(request, "variants",
                         json_object_new_string(",dvorak"));
  description = describe(request);
  assert(strcmp(text_field(key_state(description, "AD01", 0), "text"), "'") ==
         0);
  json_object_put(description);
  json_object_put(request);
}

static void test_remapped_keys(void) {
  struct json_object *request =
      json_tokener_parse("{\"layouts\":\"us\",\"options\":\"caps:escape,lv3:"
                         "ralt_switch\",\"group\":0}");
  struct json_object *description = describe(request);
  assert(strcmp(text_field(key_state(description, "CAPS", 0), "keysym"),
                "Escape") == 0);
  assert(strcmp(text_field(description, "altGrKey"), "RALT") == 0);
  json_object_put(description);
  json_object_put(request);
}

static void test_custom_file(void) {
  struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  struct xkb_rule_names names = {.layout = "us,de", .options = "caps:escape"};
  struct xkb_keymap *keymap =
      xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
  assert(keymap);
  char *keymap_text =
      xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
  char directory[] = "/tmp/keyboard-keymap-test-XXXXXX";
  assert(mkdtemp(directory));
  char path[256];
  assert(snprintf(path, sizeof(path), "%s/keyboard ü.xkb", directory) > 0);
  FILE *file = fopen(path, "w");
  assert(file && fputs(keymap_text, file) >= 0 && fclose(file) == 0);
  struct json_object *request = json_object_new_object();
  json_object_object_add(request, "keymapFile", json_object_new_string(path));
  json_object_object_add(request, "group", json_object_new_int(1));
  struct json_object *description = describe(request);
  assert(strcmp(text_field(key_state(description, "AD06", 0), "text"), "z") ==
         0);
  assert(strcmp(text_field(key_state(description, "CAPS", 0), "keysym"),
                "Escape") == 0);
  json_object_put(description);

  file = fopen(path, "w");
  const char *minimal =
      "xkb_keymap {"
      "xkb_keycodes { minimum=8; maximum=255; <AD01>=24; };"
      "xkb_types { type \"ONE_LEVEL\" { modifiers=None; map[None]=Level1; }; };"
      "xkb_compatibility {};"
      "xkb_symbols { key <AD01> { type=\"ONE_LEVEL\", [q] }; };"
      "};";
  assert(file && fputs(minimal, file) >= 0 && fclose(file) == 0);
  json_object_object_add(request, "group", json_object_new_int(0));
  description = describe(request);
  assert(!json_object_object_get_ex(field(description, "keys"), "LFSH", NULL));
  assert(strcmp(text_field(key_state(description, "AD01", 0), "text"), "q") ==
         0);
  json_object_put(description);

  assert(remove(path) == 0 && mkfifo(path, 0600) == 0);
  assert(describe_text(json_object_to_json_string(request), 1) == NULL);
  assert(remove(path) == 0);
  file = fopen(path, "w");
  assert(file && fseek(file, 1048576, SEEK_SET) == 0 &&
         fputc('x', file) != EOF && fclose(file) == 0);
  assert(describe_text(json_object_to_json_string(request), 1) == NULL);
  assert(remove(path) == 0 && rmdir(directory) == 0);
  json_object_put(request);
  free(keymap_text);
  xkb_keymap_unref(keymap);
  xkb_context_unref(context);
}

static void test_invalid_requests(void) {
  const char *invalid[] = {
      "",
      "not JSON",
      "[]",
      "null",
      "{}",
      "{\"layouts\":12,\"group\":0}",
      "{\"layouts\":\"us\",\"group\":-1}",
      "{\"layouts\":\"us\",\"group\":1}",
      "{\"layouts\":\"us\",\"group\":4294967296}",
      "{\"layouts\":\"us\",\"group\":false}",
      "{\"layouts\":\"us\\u0000de\",\"group\":0}",
      "{\"layouts\":\"nonexistent-layout-test\",\"group\":0}",
      "{\"layouts\":\"us\",\"group\":0} {\"extra\":true}"};
  for (size_t index = 0; index < sizeof(invalid) / sizeof(invalid[0]); index++)
    assert(describe_text(invalid[index], 1) == NULL);
  char *oversized = malloc(65538);
  assert(oversized);
  memset(oversized, ' ', 65537);
  oversized[65537] = '\0';
  assert(describe_text(oversized, 1) == NULL);
  free(oversized);
}

int main(void) {
  assert(setenv("LC_ALL", "en_US.UTF-8", 1) == 0);
  test_reference_cases();
  test_active_groups();
  test_remapped_keys();
  test_custom_file();
  test_invalid_requests();
  puts("keymap tests passed");
  return 0;
}
