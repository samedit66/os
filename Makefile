GOBO ?= $(HOME)/Projects/gobo
GEC ?= $(GOBO)/bin/gec
GELINT ?= $(GOBO)/bin/gelint
GETEST ?= $(GOBO)/bin/getest
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

.PHONY: all native gobo ise test generate-tests generate-file-path-tests \
	generate-process-tests generate-os-tests test-gobo test-ise \
	test-file-path-gobo test-process-gobo test-os-gobo \
	test-file-path-ise test-process-ise test-os-ise lint-gobo clean

all: gobo

$(NATIVE_DIR):
	mkdir -p $@

$(NATIVE_OBJECT): c/subprocess_posix.c c/subprocess.h | $(NATIVE_DIR)
	$(CC) $(CPPFLAGS) $(NATIVE_CFLAGS) -c $< -o $@

$(NATIVE_LIBRARY): $(NATIVE_OBJECT)
	$(AR) rcs $@ $<

native: $(NATIVE_LIBRARY)

lint-gobo:
	GOBO_EIFFEL=ge $(GELINT) --variable=GOBO_EIFFEL=ge --ise=25.12 --target=os_file_path file_path.ecf
	GOBO_EIFFEL=ge $(GELINT) --variable=GOBO_EIFFEL=ge --ise=25.12 --target=os_process process.ecf
	GOBO_EIFFEL=ge $(GELINT) --variable=GOBO_EIFFEL=ge --ise=25.12 --target=application os.ecf

gobo: native
	GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=application os.ecf
	./os_process_example

ise: native
	GOBO_EIFFEL=ise $(EC) -batch -clean -config os.ecf -target application -c_compile
	./EIFGENs/application/W_code/os_process_example

test: test-gobo test-ise

generate-tests: generate-file-path-tests generate-process-tests generate-os-tests

generate-file-path-tests:
	$(GETEST) -g tests/file_path/getest.cfg

generate-process-tests:
	$(GETEST) -g tests/process/getest.cfg

generate-os-tests:
	$(GETEST) -g tests/getest.cfg

test-gobo: test-file-path-gobo test-process-gobo test-os-gobo

test-file-path-gobo: generate-file-path-tests
	GOBO="$(GOBO)" GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_file_path_tests file_path.ecf
	./os_file_path_tests

test-process-gobo: native generate-process-tests
	GOBO="$(GOBO)" GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_process_test_child process.ecf
	GOBO="$(GOBO)" GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_process_tests process.ecf
	./os_process_tests -D "process_child=$(PROJECT_ROOT)/os_process_test_child"

test-os-gobo: native generate-os-tests
	GOBO="$(GOBO)" GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_process_test_child os.ecf
	GOBO="$(GOBO)" GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_tests os.ecf
	./os_tests -D "process_child=$(PROJECT_ROOT)/os_process_test_child"

test-ise: test-file-path-ise test-process-ise test-os-ise

test-file-path-ise: generate-file-path-tests
	GOBO="$(GOBO)" GOBO_EIFFEL=ise $(EC) -batch -clean -config file_path.ecf -target os_file_path_tests -finalize -keep -c_compile
	./EIFGENs/os_file_path_tests/F_code/os_file_path_tests

test-process-ise: native generate-process-tests
	GOBO="$(GOBO)" GOBO_EIFFEL=ise $(EC) -batch -clean -config process.ecf -target os_process_test_child -finalize -keep -c_compile
	GOBO="$(GOBO)" GOBO_EIFFEL=ise $(EC) -batch -clean -config process.ecf -target os_process_tests -finalize -keep -c_compile
	./EIFGENs/os_process_tests/F_code/os_process_tests -D "process_child=$(PROJECT_ROOT)/EIFGENs/os_process_test_child/F_code/os_process_test_child"

test-os-ise: native generate-os-tests
	GOBO="$(GOBO)" GOBO_EIFFEL=ise $(EC) -batch -clean -config os.ecf -target os_process_test_child -finalize -keep -c_compile
	GOBO="$(GOBO)" GOBO_EIFFEL=ise $(EC) -batch -clean -config os.ecf -target os_tests -finalize -keep -c_compile
	./EIFGENs/os_tests/F_code/os_tests -D "process_child=$(PROJECT_ROOT)/EIFGENs/os_process_test_child/F_code/os_process_test_child"

clean:
	rm -rf build EIFGENs os_process_example os_process_tests os_file_path_tests os_process_test_child os_tests
