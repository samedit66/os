GOBO ?= $(HOME)/Projects/gobo
GEC ?= $(GOBO)/bin/gec
GELINT ?= $(GOBO)/bin/gelint
GETEST ?= $(GOBO)/bin/getest
GEDOC ?= $(GOBO)/bin/gedoc
EC ?= ec
CC ?= cc
AR ?= ar
CLANG_FORMAT ?= clang-format
CLANG_TIDY ?= clang-tidy

CFLAGS ?= -O2
CPPFLAGS ?=
NATIVE_CFLAGS = $(CFLAGS) -std=c11 -Wall -Wextra -Werror -I c
NATIVE_DIR = build/native
NATIVE_OBJECTS = $(NATIVE_DIR)/subprocess.o $(NATIVE_DIR)/file_path.o
NATIVE_LIBRARY = $(NATIVE_DIR)/libos_native.a
PROJECT_ROOT := $(abspath .)
GOBO_FLAGS = --variable=GOBO_EIFFEL=ge --ise=25.12 --gelint
ISE_TEST_FLAGS ?= -clean
ISE_TEST_CODE_DIR ?= W_code
EIFFEL_TARGETS ?= os.ecf@os examples/quick_start/quick_start.ecf@quick_start
EIFFEL_FORMAT_SOURCES ?= $(shell git ls-files '*.e')
EIFFEL_FORMAT_EXCLUDES ?= tests/file_path/os_file_path_tests.e
C_FORMAT_SOURCES ?= $(wildcard c/*.c c/*.h)
C_CHECK_SOURCES ?= c/subprocess_posix.c c/file_path_posix.c
C_CHECK_FLAGS ?= -std=c11 -I c
CLANG_TIDY_CHECKS ?= -*,clang-analyzer-*,bugprone-*,cert-*,portability-*,-bugprone-reserved-identifier,-cert-dcl37-c,-cert-dcl51-cpp

.PHONY: all native check check-gobo check-ise format ccheck cformat gobo ise \
	test generate-tests test-gobo test-ise test-ise-finalized clean

all: gobo

$(NATIVE_DIR):
	mkdir -p $@

$(NATIVE_DIR)/subprocess.o: c/subprocess_posix.c c/subprocess.h | $(NATIVE_DIR)
	$(CC) $(CPPFLAGS) $(NATIVE_CFLAGS) -c $< -o $@

$(NATIVE_DIR)/file_path.o: c/file_path_posix.c c/file_path.h | $(NATIVE_DIR)
	$(CC) $(CPPFLAGS) $(NATIVE_CFLAGS) -c $< -o $@

$(NATIVE_LIBRARY): $(NATIVE_OBJECTS)
	$(AR) rcs $@ $^

native: $(NATIVE_LIBRARY)

check: check-gobo check-ise

check-gobo:
	@set -e; for system in $(EIFFEL_TARGETS); do \
		ecf=$${system%@*}; target=$${system#*@}; \
		GOBO_EIFFEL=ge $(GELINT) --variable=GOBO_EIFFEL=ge --ise=25.12 \
			--target="$$target" "$$ecf"; \
	done

check-ise:
	@set -e; for system in $(EIFFEL_TARGETS); do \
		ecf=$${system%@*}; target=$${system#*@}; \
		GOBO="$(GOBO)" GOBO_EIFFEL=ise $(EC) -batch -config "$$ecf" \
			-target "$$target" -clean -ca_default -ca_class -all; \
	done

format:
	@set -e; formatter="$(abspath $(GEDOC))"; \
	for source in $(filter-out $(EIFFEL_FORMAT_EXCLUDES),$(EIFFEL_FORMAT_SOURCES)); do \
		directory=$${source%/*}; filename=$${source##*/}; \
		(cd "$$directory" && GOBO="$(GOBO)" GOBO_EIFFEL=ge \
			"$$formatter" --silent --force "$$filename"); \
	done

ccheck:
	$(CLANG_TIDY) $(C_CHECK_SOURCES) -checks='$(CLANG_TIDY_CHECKS)' \
		-warnings-as-errors='*' -- $(C_CHECK_FLAGS)

cformat:
	$(CLANG_FORMAT) -i $(C_FORMAT_SOURCES)

gobo: native
	GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=quick_start examples/quick_start/quick_start.ecf
	./os_quick_start

ise: native
	GOBO_EIFFEL=ise $(EC) -batch -clean -config examples/quick_start/quick_start.ecf -target quick_start -c_compile
	./EIFGENs/quick_start/W_code/os_quick_start

test: test-gobo test-ise

generate-tests:
	$(GETEST) -g tests/getest.cfg

test-gobo: native generate-tests
	GOBO="$(GOBO)" GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_process_test_child os.ecf
	GOBO="$(GOBO)" GOBO_EIFFEL=ge ZIG_GLOBAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-global-cache ZIG_LOCAL_CACHE_DIR=$(PROJECT_ROOT)/build/zig-local-cache $(GEC) $(GOBO_FLAGS) --target=os_tests os.ecf
	./os_tests -D "process_child=$(PROJECT_ROOT)/os_process_test_child"

test-ise: native generate-tests
	GOBO="$(GOBO)" GOBO_EIFFEL=ise $(EC) -batch -config os.ecf -target os_process_test_child $(ISE_TEST_FLAGS) -c_compile
	GOBO="$(GOBO)" GOBO_EIFFEL=ise $(EC) -batch -config os.ecf -target os_tests $(ISE_TEST_FLAGS) -c_compile
	./EIFGENs/os_tests/$(ISE_TEST_CODE_DIR)/os_tests -D "process_child=$(PROJECT_ROOT)/EIFGENs/os_process_test_child/$(ISE_TEST_CODE_DIR)/os_process_test_child"

test-ise-finalized:
	$(MAKE) test-ise ISE_TEST_FLAGS="-clean -finalize -keep" ISE_TEST_CODE_DIR=F_code

clean:
	rm -rf build EIFGENs os_process_example os_quick_start os_process_tests os_file_path_tests os_process_test_child os_tests
