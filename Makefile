CC = clang
OBJCFLAGS = -fobjc-arc -Wall -Wextra -Werror
FRAMEWORKS = -framework Cocoa -framework ApplicationServices
BINARY = build/cardinal-insert

.PHONY: all check install clean

all: $(BINARY)

$(BINARY): src/cardinal_insert.m Makefile
	mkdir -p build
	$(CC) $(CPPFLAGS) $(OBJCFLAGS) $(CFLAGS) src/cardinal_insert.m $(LDFLAGS) $(FRAMEWORKS) -o "$@"

check: $(BINARY)
	python3 tests/check_package.py
	"$(BINARY)" --check

install: $(BINARY)
	./scripts/install.sh

clean:
	rm -f "$(BINARY)"
	@if [ -d build ]; then rmdir build 2>/dev/null || :; fi
