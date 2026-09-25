# riptide-wm – built against the installed Hyprland headers (pacman: hyprland).
# plugins/build.sh runs this after every Hyprland update.
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wno-c++11-narrowing
ifeq ($(CXX),g++)
    CXXFLAGS += --no-gnu-unique
endif
INCLUDES = $(shell pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon)
SRC = main.cpp window_buttons.cpp titlebars/titlebars.cpp titlebars/barDeco.cpp titlebars/BarPassElement.cpp

riptide-wm.so: $(SRC) plugin.hpp titlebars/*.hpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(SRC) -o $@

clean:
	rm -f riptide-wm.so
