#!/usr/bin/env bash
# End the session: through uwsm when it manages Hyprland (normal login on tty1),
# otherwise by telling Hyprland itself to exit (e.g. started by hand).
if uwsm check is-active >/dev/null 2>&1; then
    exec uwsm stop
fi
exec hyprctl dispatch 'hl.dsp.exit()'
