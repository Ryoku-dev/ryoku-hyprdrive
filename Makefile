CXX ?= g++

# The Lua Hyprland itself links (scripts/lua_pc.sh): its header constants must
# match the liblua the compositor runs, and Arch carries both lua 5.5 and lua54.
LUA_PC := $(shell sh scripts/lua_pc.sh)

OPT ?= -O2

PKGS := pixman-1 libdrm hyprland pangocairo fontconfig libinput libudev wayland-server \
        xkbcommon libsystemd gio-2.0 gio-unix-2.0 $(LUA_PC)

# One folder per subsystem (src/README.md). Every #include is a bare name, so
# each folder is on the include path and objects stay flat in build/.
SRC_DIRS := $(sort $(dir $(wildcard src/*/*.cpp src/*/*.hpp src/*/*/*.cpp src/*/*/*.hpp)))
SRC_INC  := $(addprefix -I,$(SRC_DIRS:/=))
SRCS := $(wildcard src/*/*.cpp src/*/*/*.cpp)
OBJS := $(addprefix build/,$(notdir $(SRCS:.cpp=.o)))
DEPS := $(OBJS:.o=.d)
vpath %.cpp $(SRC_DIRS)
ifneq ($(words $(SRCS)),$(words $(sort $(notdir $(SRCS)))))
$(error two source files share a name: $(filter-out $(sort $(notdir $(SRCS))),$(notdir $(SRCS))))
endif

ifneq ($(filter-out clean,$(or $(MAKECMDGOALS),all)),)
CXXFLAGS := -fPIC $(OPT) -g -std=c++2b -Wno-narrowing -Ibuild $(SRC_INC) -include src/core/HyprCompat.hpp --embed-dir=. \
            $(shell pkg-config --cflags $(PKGS))
LDLIBS   := $(shell pkg-config --libs libsystemd gio-2.0 gio-unix-2.0 fontconfig xcb xcb-res)
endif

ifeq ($(CXX),g++)
    CXXFLAGS += -fno-gnu-unique
endif

VERSION_HEADER = build/PluginVersion.hpp
VERSION_SCRIPT = scripts/generate-plugin-version.sh

.PHONY: all check clean look lithic FORCE

all: hyprdrive.so check

# symcheck is part of the build: an undefined symbol is a lazy-bind compositor
# kill, so a .so that fails it is never laid down.
# The objects keep their debug information; the .so laid down does not (it is
# most of the file). Function names stay, so a crash report still names where it
# died.
hyprdrive.so: $(OBJS)
	$(CXX) -shared $(OBJS) -o $@ $(LDLIBS)
	strip --strip-debug $@
	bash scripts/symcheck.sh

build/BuiltinIcons.o: $(wildcard assets/icons/*.svg) assets/scratchpad-symbolic.svg

build/%.o: %.cpp | $(VERSION_HEADER)
	@mkdir -p build
	$(CXX) $(CXXFLAGS) -MMD -MP -c $< -o $@

$(VERSION_HEADER): FORCE $(VERSION_SCRIPT)
	@sh $(VERSION_SCRIPT) $@ .

FORCE:

check: hyprdrive.so
	bash scripts/keycheck.sh
	bash scripts/gen_keys_table.sh --check
	bash tests/host_tests.sh

# The look bridge (look/): the desktop's Lithic style as text for the plugin,
# which cannot link the Go library. Built from look/vendor, so no network.
look:
	cd look && GOFLAGS=-trimpath go build -o ../ryoku-hyprdrive-look .

# Refresh look/vendor's copy of the Lithic library from a Ryoku checkout, by
# default one beside this repository (../ryoku). go.mod and vendor/modules.txt
# keep naming that place, so a build needs no checkout and no network.
RYOKU ?= ../ryoku
LITHIC_MOD = github.com/ryoku-dev/ryoku/docs/lithic/library/go
LITHIC_REL = ../../ryoku/docs/lithic/library/go
lithic:
	@test -d "$(RYOKU)/docs/lithic/library/go" || { echo "no Lithic library under $(RYOKU); make lithic RYOKU=<a Ryoku checkout>"; exit 1; }
	cd look && go mod edit -replace $(LITHIC_MOD)=$(abspath $(RYOKU))/docs/lithic/library/go && go mod vendor
	cd look && go mod edit -replace $(LITHIC_MOD)=$(LITHIC_REL) \
		&& sed -i 's|=> $(abspath $(RYOKU))/docs/lithic/library/go|=> $(LITHIC_REL)|' vendor/modules.txt

clean:
	rm -rf build hyprdrive.so ryoku-hyprdrive-look

-include $(DEPS)
