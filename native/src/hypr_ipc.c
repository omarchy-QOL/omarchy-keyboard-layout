#include "keyboard_layout/hypr_ipc.h"
#include "keyboard_layout/layout_memory.h"

#include <errno.h>
#include <json-c/json.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int set_address(struct sockaddr_un *address, const char *runtime_dir,
                       const char *signature, const char *socket_name) {
  int length = snprintf(address->sun_path, sizeof(address->sun_path),
                        "%s/hypr/%s/%s", runtime_dir, signature, socket_name);
  if (length < 0 || (size_t)length >= sizeof(address->sun_path))
    return -1;
  address->sun_family = AF_UNIX;
  return 0;
}

int hypr_ipc_init(struct hypr_ipc *ipc, const char *runtime_dir,
                  const char *instance_signature) {
  *ipc = (struct hypr_ipc){0};
  if (runtime_dir == NULL || runtime_dir[0] == '\0' ||
      instance_signature == NULL || instance_signature[0] == '\0' ||
      set_address(&ipc->control_address, runtime_dir, instance_signature,
                  ".socket.sock") != 0)
    return -1;
  return set_address(&ipc->event_address, runtime_dir, instance_signature,
                     ".socket2.sock");
}

static int connect_to(const struct sockaddr_un *address) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  socklen_t length = (socklen_t)(offsetof(struct sockaddr_un, sun_path) +
                                 strlen(address->sun_path) + 1);
  if (fd < 0)
    return -1;
  if (connect(fd, (const struct sockaddr *)address, length) == 0)
    return fd;
  close(fd);
  return -1;
}

int hypr_ipc_connect_events(const struct hypr_ipc *ipc) {
  return connect_to(&ipc->event_address);
}

static int send_request(const struct hypr_ipc *ipc, const char *request) {
  int fd = connect_to(&ipc->control_address);
  if (fd < 0)
    return -1;

  size_t sent = 0;
  size_t length = strlen(request);
  while (sent < length) {
    ssize_t count = send(fd, request + sent, length - sent, MSG_NOSIGNAL);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0) {
      close(fd);
      return -1;
    }
    sent += (size_t)count;
  }
  if (shutdown(fd, SHUT_WR) == 0)
    return fd;
  close(fd);
  return -1;
}

static json_object *request_json(const struct hypr_ipc *ipc,
                                 const char *request) {
  int fd = send_request(ipc, request);
  if (fd < 0)
    return NULL;
  json_object *response = json_object_from_fd(fd);
  close(fd);
  return response;
}

static json_object *keyboards_from(json_object *root) {
  json_object *keyboards = NULL;
  if (root == NULL || !json_object_is_type(root, json_type_object) ||
      !json_object_object_get_ex(root, "keyboards", &keyboards) ||
      !json_object_is_type(keyboards, json_type_array))
    return NULL;
  return keyboards;
}

static int keyboard_layout(json_object *keyboard, int *layout) {
  json_object *value = NULL;
  if (keyboard == NULL ||
      !json_object_object_get_ex(keyboard, "active_layout_index", &value) ||
      !json_object_is_type(value, json_type_int))
    return -1;
  *layout = json_object_get_int(value);
  return *layout < 0 ? -1 : 0;
}

static const char *keyboard_name(json_object *keyboard) {
  json_object *value = NULL;
  if (keyboard == NULL || !json_object_is_type(keyboard, json_type_object) ||
      !json_object_object_get_ex(keyboard, "name", &value) ||
      !json_object_is_type(value, json_type_string))
    return NULL;
  return json_object_get_string(value);
}

static int ends_with(const char *value, const char *suffix) {
  size_t value_length = strlen(value);
  size_t suffix_length = strlen(suffix);
  return value_length >= suffix_length &&
         strcmp(value + value_length - suffix_length, suffix) == 0;
}

int hypr_keyboard_is_typing(const char *name) {
  return name != NULL && strstr(name, "virtual-keyboard") == NULL &&
         !ends_with(name, "-system-control") &&
         !ends_with(name, "-consumer-control") &&
         strcmp(name, "video-bus") != 0 &&
         strncmp(name, "power-button", 12) != 0;
}

static int device_layout(json_object *root, const char *device, int *layout) {
  json_object *keyboards = keyboards_from(root);
  if (keyboards == NULL || device == NULL)
    return -1;

  size_t count = json_object_array_length(keyboards);
  for (size_t i = 0; i < count; i++) {
    json_object *keyboard = json_object_array_get_idx(keyboards, i);
    const char *name = keyboard_name(keyboard);
    if (name != NULL && strcmp(name, device) == 0)
      return keyboard_layout(keyboard, layout);
  }
  return -1;
}

static int current_layout(json_object *root, int *layout) {
  json_object *keyboards = keyboards_from(root);
  json_object *fallback = NULL;
  json_object *selected = NULL;
  if (keyboards == NULL)
    return -1;

  size_t count = json_object_array_length(keyboards);
  for (size_t i = 0; i < count; i++) {
    json_object *keyboard = json_object_array_get_idx(keyboards, i);
    const char *name = keyboard_name(keyboard);
    if (name == NULL)
      continue;
    if (fallback == NULL)
      fallback = keyboard;
    if (!hypr_keyboard_is_typing(name))
      continue;
    if (selected == NULL)
      selected = keyboard;
    json_object *main = NULL;
    if (json_object_object_get_ex(keyboard, "main", &main) &&
        json_object_is_type(main, json_type_boolean) &&
        json_object_get_boolean(main)) {
      selected = keyboard;
      break;
    }
  }
  return keyboard_layout(selected == NULL ? fallback : selected, layout);
}

int hypr_json_device_layout(const char *json, const char *device, int *layout) {
  json_object *root = json_tokener_parse(json);
  int result = device_layout(root, device, layout);
  json_object_put(root);
  return result;
}

int hypr_json_current_layout(const char *json, int *layout) {
  json_object *root = json_tokener_parse(json);
  int result = current_layout(root, layout);
  json_object_put(root);
  return result;
}

static int active_window(json_object *root, uint64_t *window) {
  json_object *address = NULL;
  if (root == NULL || !json_object_is_type(root, json_type_object) ||
      !json_object_object_get_ex(root, "address", &address) ||
      !json_object_is_type(address, json_type_string))
    return -1;
  return layout_memory_parse_window(json_object_get_string(address), window);
}

int hypr_json_active_window(const char *json, uint64_t *window) {
  json_object *root = json_tokener_parse(json);
  int result = active_window(root, window);
  json_object_put(root);
  return result;
}

int hypr_ipc_active_window(const struct hypr_ipc *ipc, uint64_t *window) {
  json_object *response = request_json(ipc, "j/activewindow");
  int result = active_window(response, window);
  json_object_put(response);
  return result;
}

static int query_layout(const struct hypr_ipc *ipc, const char *device,
                        int *layout) {
  json_object *response = request_json(ipc, "j/devices");
  int result = device == NULL ? current_layout(response, layout)
                              : device_layout(response, device, layout);
  json_object_put(response);
  return result;
}

int hypr_ipc_current_layout(const struct hypr_ipc *ipc, int *layout) {
  return query_layout(ipc, NULL, layout);
}

int hypr_ipc_device_layout(const struct hypr_ipc *ipc, const char *device,
                           int *layout) {
  return query_layout(ipc, device, layout);
}

int hypr_ipc_switch_layout(const struct hypr_ipc *ipc, int layout) {
  char request[64];
  int length =
      snprintf(request, sizeof(request), "/switchxkblayout all %d", layout);
  if (layout < 0 || length < 0 || (size_t)length >= sizeof(request))
    return -1;

  int fd = send_request(ipc, request);
  if (fd < 0)
    return -1;
  char response[3];
  ssize_t count;
  do {
    count = recv(fd, response, sizeof(response), MSG_WAITALL);
  } while (count < 0 && errno == EINTR);
  close(fd);
  return count == 2 && memcmp(response, "ok", 2) == 0 ? 0 : -1;
}
