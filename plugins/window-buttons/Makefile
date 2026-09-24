# window-buttons – built against the installed Hyprland headers (pacman: hyprland).
# Rebuild after every Hyprland update:  make  (plugins/build.sh does all plugins)
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b
INCLUDES = $(shell pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon)

window-buttons.so: main.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) main.cpp -o $@

clean:
	rm -f window-buttons.so
