GOBO ?= $(HOME)/Projects/gobo
GEC ?= $(GOBO)/bin/gec
GELINT ?= $(GOBO)/bin/gelint
GEDOC ?= $(GOBO)/bin/gedoc
GETEST ?= $(GOBO)/bin/getest
EC ?= ec
CC ?= cc
AR ?= ar
CLANG_FORMAT ?= clang-format
CLANG_TIDY ?= clang-tidy

CFLAGS ?= -O2
CPPFLAGS ?=
NATIVE_CFLAGS = $(CFLAGS) -std=c11 -Wall -Wextra -Werror -I c
NATIVE_DIR = build/native
NATIVE_OBJECT = $(NATIVE_DIR)/subprocess.o
NATIVE_LIBRARY = $(NATIVE_DIR)/libos_process.a
PROJECT_ROOT := $(abspath .)
GOBO_FLAGS = --variable=GOBO_EIFFEL=ge --ise=25.12 --gelint
EIFFEL_SOURCES ?= $(shell find src tests -type f -name '*.e')
EIFFEL_GEDOC_EXCLUDES ?= src/process/os_process_failure_kind.e \
	tests/file_path/os_file_path_tests.e
EIFFEL_GEDOC_SOURCES ?= $(filter-out $(EIFFEL_GEDOC_EXCLUDES),$(EIFFEL_SOURCES))
EIFFEL_TARGETS ?= file_path.ecf@os_file_path process.ecf@os_process os.ecf@application
C_FORMAT_SOURCES ?= $(wildcard c/*.c c/*.h)
C_CHECK_SOURCES ?= c/subprocess_posix.c
C_CHECK_FLAGS ?= -std=c11 -I c
CLANG_TIDY_CHECKS ?= -*,clang-analyzer-*,bugprone-*,cert-*,portability-*,-bugprone-reserved-identifier,-cert-dcl37-c,-cert-dcl51-cpp

.PHONY: all native check check-gobo check-ise format format-gobo format-ise \
	ccheck cformat gobo ise test generate-tests generate-file-path-tests \
	generate-process-tests generate-os-tests test-gobo test-ise \
	test-file-path-gobo test-process-gobo test-os-gobo \
	test-file-path-ise test-process-ise test-os-ise clean

all: gobo

$(NATIVE_DIR):
	mkdir -p $@

$(NATIVE_OBJECT): c/subprocess_posix.c c/subprocess.h | $(NATIVE_DIR)
	$(CC) $(CPPFLAGS) $(NATIVE_CFLAGS) -c $< -o $@

$(NATIVE_LIBRARY): $(NATIVE_OBJECT)
	$(AR) rcs $@ $<

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
			-target "$$target" -ca_default -ca_class -all; \
	done

format: format-gobo

format-gobo:
	@set -e; for file in $(EIFFEL_GEDOC_SOURCES); do \
		case "$$file" in */*) output_dir=$${file%/*} ;; *) output_dir=. ;; esac; \
		$(GEDOC) --force --no-benchmark --output="$$output_dir" "$$file"; \
	done

# Use this optional target for ISE layout and files excluded because of gedoc defects.
format-ise:
	@set -e; for file in $(EIFFEL_SOURCES); do \
		output=$$(mktemp "$$file.pretty.XXXXXX"); \
		if $(EC) -pretty "$$file" "$$output"; then \
			cp "$$output" "$$file"; rm -f "$$output"; \
		else \
			rm -f "$$output"; exit 1; \
		fi; \
	done

ccheck:
	$(CLANG_TIDY) $(C_CHECK_SOURCES) -checks='$(CLANG_TIDY_CHECKS)' \
		-warnings-as-errors='*' -- $(C_CHECK_FLAGS)

cformat:
	$(CLANG_FORMAT) -i $(C_FORMAT_SOURCES)

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
