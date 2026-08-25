GOBO ?= $(HOME)/Projects/gobo
GEC ?= $(GOBO)/bin/gec
GELINT ?= $(GOBO)/bin/gelint
EC ?= ec
CC ?= cc
AR ?= ar

CFLAGS ?= -O2
CPPFLAGS ?=
NATIVE_CFLAGS = $(CFLAGS) -std=c11 -Wall -Wextra -Werror -I c
NATIVE_DIR = build/native
NATIVE_OBJECT = $(NATIVE_DIR)/subprocess.o
NATIVE_LIBRARY = $(NATIVE_DIR)/libos_process.a
PROJECT_ROOT := $(abspath .)
GOBO_FLAGS = --variable=GOBO_EIFFEL=ge --ise=25.12 --gelint

.PHONY: all native gobo ise test test-gobo test-ise lint-gobo clean

all: gobo

$(NATIVE_DIR):
	mkdir -p $@

$(NATIVE_OBJECT): c/subprocess_posix.c c/subprocess.h | $(NATIVE_DIR)
	$(CC) $(CPPFLAGS) $(NATIVE_CFLAGS) -c $< -o $@

$(NATIVE_LIBRARY): $(NATIVE_OBJECT)
	$(AR) rcs $@ $<

native: $(NATIVE_LIBRARY)

lint-gobo:
	GOBO_EIFFEL=ge $(GELINT) --variable=GOBO_EIFFEL=ge --ise=25.12 --target=application os.ecf

gobo: native
	GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=application os.ecf
	./os_process_example

ise:
	GOBO_EIFFEL=ise $(EC) -batch -clean -config os.ecf -target application -c_compile
	./EIFGENs/application/W_code/os_process_example

test: test-gobo test-ise

test-gobo: native
	GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_process_tests os.ecf
	./os_process_tests
	GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_file_path_tests os.ecf
	./os_file_path_tests

test-ise:
	GOBO_EIFFEL=ise $(EC) -batch -clean -config os.ecf -target os_process_tests -finalize -keep -c_compile
	./EIFGENs/os_process_tests/F_code/os_process_tests
	GOBO_EIFFEL=ise $(EC) -batch -clean -config os.ecf -target os_file_path_tests -finalize -keep -c_compile
	./EIFGENs/os_file_path_tests/F_code/os_file_path_tests

clean:
	rm -rf build EIFGENs os_process_example os_process_tests os_file_path_tests
