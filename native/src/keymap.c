#include "keyboard_layout/keymap.h"
#include "keymap_internal.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon-names.h>

struct keymap_request {
  struct xkb_rule_names names;
  const char *file_path;
  xkb_layout_index_t group;
};

static int keymap_error(const char *message) {
  fprintf(stderr, "keyboard-layoutd: keymap: %s\n", message);
  return EXIT_FAILURE;
}

static int read_request_string(struct json_object *object, const char *name,
                               const char **value) {
  struct json_object *field = NULL;
  *value = "";
  if (!json_object_object_get_ex(object, name, &field))
    return 0;
  if (!json_object_is_type(field, json_type_string))
    return -1;
  *value = json_object_get_string(field);
  size_t length = (size_t)json_object_get_string_len(field);
  if (length > 4096 || strlen(*value) != length)
    return -1;
  return 0;
}

static struct json_object *read_request(FILE *input,
                                        struct keymap_request *request) {
  char *buffer = malloc(KEYMAP_REQUEST_LIMIT + 1);
  if (!buffer)
    return NULL;
  size_t length = fread(buffer, 1, KEYMAP_REQUEST_LIMIT + 1, input);
  if (ferror(input) || length == 0 || length > KEYMAP_REQUEST_LIMIT) {
    free(buffer);
    return NULL;
  }
  struct json_tokener *parser = json_tokener_new();
  if (!parser) {
    free(buffer);
    return NULL;
  }
  json_tokener_set_flags(parser,
                         JSON_TOKENER_STRICT | JSON_TOKENER_VALIDATE_UTF8);
  struct json_object *object =
      json_tokener_parse_ex(parser, buffer, (int)length);
  enum json_tokener_error error = json_tokener_get_error(parser);
  size_t consumed = json_tokener_get_parse_end(parser);
  while (consumed < length &&
         (buffer[consumed] == ' ' || buffer[consumed] == '\n' ||
          buffer[consumed] == '\r' || buffer[consumed] == '\t'))
    consumed++;
  json_tokener_free(parser);
  free(buffer);
  if (error != json_tokener_success || consumed != length ||
      !json_object_is_type(object, json_type_object)) {
    json_object_put(object);
    return NULL;
  }

  if (read_request_string(object, "rules", &request->names.rules) != 0 ||
      read_request_string(object, "model", &request->names.model) != 0 ||
      read_request_string(object, "layouts", &request->names.layout) != 0 ||
      read_request_string(object, "variants", &request->names.variant) != 0 ||
      read_request_string(object, "options", &request->names.options) != 0 ||
      read_request_string(object, "keymapFile", &request->file_path) != 0) {
    json_object_put(object);
    return NULL;
  }
  struct json_object *group = NULL;
  if (!json_object_object_get_ex(object, "group", &group) ||
      !json_object_is_type(group, json_type_int) ||
      json_object_get_int64(group) < 0 ||
      json_object_get_int64(group) > UINT32_MAX) {
    json_object_put(object);
    return NULL;
  }
  request->group = (xkb_layout_index_t)json_object_get_int64(group);
  return object;
}

static struct xkb_keymap *load_keymap_file(struct xkb_context *context,
                                           const char *path) {
  int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
  if (descriptor < 0)
    return NULL;
  struct stat status;
  if (fstat(descriptor, &status) != 0 || !S_ISREG(status.st_mode) ||
      status.st_size <= 0 || status.st_size > KEYMAP_FILE_LIMIT) {
    close(descriptor);
    return NULL;
  }
  char *buffer = malloc(KEYMAP_FILE_LIMIT + 1);
  if (!buffer) {
    close(descriptor);
    return NULL;
  }
  size_t length = 0;
  while (length <= KEYMAP_FILE_LIMIT) {
    ssize_t count =
        read(descriptor, buffer + length, KEYMAP_FILE_LIMIT + 1 - length);
    if (count < 0 && errno == EINTR)
      continue;
    if (count < 0) {
      length = KEYMAP_FILE_LIMIT + 1;
      break;
    }
    if (count == 0)
      break;
    length += (size_t)count;
  }
  close(descriptor);
  struct xkb_keymap *keymap = NULL;
  if (length > 0 && length <= KEYMAP_FILE_LIMIT &&
      memchr(buffer, '\0', length) == NULL)
    keymap = xkb_keymap_new_from_buffer(context, buffer, length,
                                        XKB_KEYMAP_FORMAT_TEXT_V1,
                                        XKB_KEYMAP_COMPILE_NO_FLAGS);
  free(buffer);
  return keymap;
}

static struct xkb_keymap *load_keymap(struct xkb_context *context,
                                      const struct keymap_request *request) {
  if (request->file_path[0] != '\0')
    return load_keymap_file(context, request->file_path);
  struct xkb_rule_names names = request->names;
  if (!names.rules[0])
    names.rules = "evdev";
  if (!names.model[0])
    names.model = "pc105";
  if (!names.layout[0])
    return NULL;
  return xkb_keymap_new_from_names(context, &names,
                                   XKB_KEYMAP_COMPILE_NO_FLAGS);
}

// stream arguments follow the conventional input/output order
// NOLINTNEXTLINE(bugprone-easily-swappable-parameters)
int keymap_describe(FILE *input, FILE *output) {
  struct keymap_request request = {0};
  struct json_object *document = read_request(input, &request);
  if (!document)
    return keymap_error("invalid request");
  struct xkb_context *context =
      xkb_context_new(XKB_CONTEXT_NO_ENVIRONMENT_NAMES);
  if (!context) {
    json_object_put(document);
    return keymap_error("could not create context");
  }
  xkb_context_set_log_level(context, XKB_LOG_LEVEL_CRITICAL);
  struct xkb_keymap *keymap = load_keymap(context, &request);
  if (!keymap || request.group >= xkb_keymap_num_layouts(keymap)) {
    xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    json_object_put(document);
    return keymap_error("could not load the requested group");
  }

  const char *level3_key = "";
  struct json_object *keys =
      keymap_collect_keys(keymap, request.group, &level3_key);
  struct json_object *description = json_object_new_object();
  int result = EXIT_FAILURE;
  if (keys && json_object_object_length(keys) > 0 && description) {
    json_object_object_add(description, "schemaVersion",
                           json_object_new_int(1));
    json_object_object_add(description, "keys", keys);
    json_object_object_add(description, "altGrKey",
                           json_object_new_string(level3_key));
    json_object_object_add(description, "group",
                           json_object_new_int64(request.group));
    struct json_object *modifiers = json_object_new_object();
    json_object_object_add(
        modifiers, "shift",
        json_object_new_boolean(
            xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_SHIFT) < 32));
    json_object_object_add(
        modifiers, "capsLock",
        json_object_new_boolean(
            xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_CAPS) < 32));
    json_object_object_add(modifiers, "altGr",
                           json_object_new_boolean(level3_key[0] != '\0'));
    json_object_object_add(description, "modifiers", modifiers);
    const char *layout_name = xkb_keymap_layout_get_name(keymap, request.group);
    json_object_object_add(
        description, "layoutName",
        json_object_new_string(layout_name ? layout_name : ""));
    if (keymap_add_compositions(context, description) == 0) {
      size_t length = 0;
      const char *json = json_object_to_json_string_length(
          description, JSON_C_TO_STRING_PLAIN, &length);
      if (json && length <= KEYMAP_OUTPUT_LIMIT &&
          fwrite(json, 1, length, output) == length &&
          fputc('\n', output) != EOF)
        result = EXIT_SUCCESS;
    }
  } else {
    json_object_put(keys);
  }
  json_object_put(description);
  xkb_keymap_unref(keymap);
  xkb_context_unref(context);
  json_object_put(document);
  if (result != EXIT_SUCCESS)
    return keymap_error("could not describe keymap");
  return result;
}
