CC ?= cc

CPPFLAGS += -D_POSIX_C_SOURCE=200809L -Iinclude \
	$(shell pkg-config --cflags json-c)
CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic
LDLIBS += $(shell pkg-config --libs json-c)

TARGET := keyboard-layoutd
BUILD_DIR := build
LIB_SOURCES := src/hypr_ipc.c src/layout_memory.c
SOURCES := src/main.c $(LIB_SOURCES)
OBJECTS := $(SOURCES:src/%.c=$(BUILD_DIR)/%.o)
TESTS := $(BUILD_DIR)/test_hypr_ipc $(BUILD_DIR)/test_layout_memory

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

test: $(TESTS)
	@for test in $(TESTS); do $$test; done

check-live: $(BUILD_DIR)/test_live_ipc
	@$<

compile-commands:
	@command -v bear >/dev/null || { \
		echo "bear is required to generate compile_commands.json" >&2; \
		exit 1; \
	}
	bear --output compile_commands.json -- \
		$(MAKE) clean $(TARGET) $(TESTS) $(BUILD_DIR)/test_live_ipc

$(BUILD_DIR)/test_live_ipc: tests/test_live_ipc.c $(BUILD_DIR)/hypr_ipc.o \
		$(BUILD_DIR)/layout_memory.o
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

clean:
	rm -rf $(BUILD_DIR) $(TARGET)

-include $(OBJECTS:.o=.d)
