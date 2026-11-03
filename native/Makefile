CC ?= cc

CPPFLAGS += -D_POSIX_C_SOURCE=200809L -Iinclude \
	$(shell pkg-config --cflags json-c xkbcommon libutf8proc)
CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic
LDLIBS += $(shell pkg-config --libs json-c xkbcommon libutf8proc)

TARGET := keyboard-layoutd
BUILD_DIR := build
LIB_SOURCES := src/hypr_ipc.c src/layout_memory.c
KEYMAP_SOURCES := src/keymap.c src/keymap_symbols.c src/keymap_compose.c
SOURCES := src/main.c $(LIB_SOURCES) $(KEYMAP_SOURCES)
OBJECTS := $(SOURCES:src/%.c=$(BUILD_DIR)/%.o)
TESTS := $(BUILD_DIR)/test_hypr_ipc $(BUILD_DIR)/test_layout_memory $(BUILD_DIR)/test_keymap

.PHONY: all check-live clean compile-commands test

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

$(BUILD_DIR)/%.o: src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/test_hypr_ipc: tests/test_hypr_ipc.c $(BUILD_DIR)/hypr_ipc.o \
		$(BUILD_DIR)/layout_memory.o
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

$(BUILD_DIR)/test_layout_memory: tests/test_layout_memory.c \
		$(BUILD_DIR)/layout_memory.o
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

$(BUILD_DIR)/test_keymap: tests/test_keymap.c $(KEYMAP_SOURCES:src/%.c=$(BUILD_DIR)/%.o)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) \
		-DKEYMAP_FIXTURE_PATH='"$(CURDIR)/tests/fixtures/keymap-reference.json"' \
		-o $@ $^ $(LDLIBS)

test: $(TESTS)
	@set -e; for test in $(TESTS); do $$test; done

check-live: $(BUILD_DIR)/test_live_ipc
	@$<

compile-commands:
	@command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
	@for source in $(SOURCES) $(wildcard tests/test_*.c); do \
		jq -n --arg directory "$(CURDIR)" --arg file "$$source" \
			--arg command "$(CC) $(CPPFLAGS) $(CFLAGS) -c $$source" \
			'{directory:$$directory,file:$$file,command:$$command}'; \
	done | jq -s . > compile_commands.json

$(BUILD_DIR)/test_live_ipc: tests/test_live_ipc.c $(BUILD_DIR)/hypr_ipc.o \
		$(BUILD_DIR)/layout_memory.o
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

clean:
	rm -rf $(BUILD_DIR) $(TARGET)

-include $(OBJECTS:.o=.d)
