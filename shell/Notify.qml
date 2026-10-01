pragma Singleton

import Quickshell

// Notices from the shell itself go through the normal notification path,
// so they look like every other notification.
Singleton {
    function send(title, body, critical) {
        const cmd = ["notify-send", "-a", "System", "-i", critical ? "dialog-warning" : "dialog-information"];
        if (critical)
            cmd.push("-u", "critical");
        cmd.push(title, body ?? "");
        Quickshell.execDetached(cmd);
    }

    function error(title, body) {
        send(title, body, true);
    }
}
