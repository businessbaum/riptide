// A Wayland socket for one sandboxed app, in a security context (wp_security_context_v1):
// the compositor (Hyprland) hides the privileged protocols from every client that
// connects through it – capturing the screen, reading the clipboard in the background,
// faking keyboard and mouse input, managing other apps' windows.
//
//   wl-security-context <socket path> <app id> <instance id>
//
// Prints "ready" once the socket accepts connections and keeps it until stdin hangs up:
// stdin is the write end of a pipe whose only reader is the sandbox (bwrap --sync-fd),
// so the socket lives exactly as long as the app. (A pipe we read from works as well:
// then its end of file stops us.) Then the socket file is removed and the compositor
// stops listening on it.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-client.h>

#include "security-context-v1-client-protocol.h"

static struct wp_security_context_manager_v1 *manager;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
                   uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, wp_security_context_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name, &wp_security_context_manager_v1_interface, 1);
}

static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {global, global_remove};

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <socket path> <app id> <instance id>\n", argv[0]);
        return 2;
    }
    const char *path = argv[1];

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        perror("wl-security-context: no Wayland display");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) {
        fprintf(stderr, "wl-security-context: compositor has no wp_security_context_manager_v1\n");
        return 1;
    }

    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof addr.sun_path) {
        fprintf(stderr, "wl-security-context: socket path too long\n");
        return 1;
    }
    strcpy(addr.sun_path, path);
    int listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    unlink(path);
    if (listen_fd < 0 || bind(listen_fd, (struct sockaddr *)&addr, sizeof addr) < 0 || listen(listen_fd, 16) < 0) {
        perror("wl-security-context: socket");
        return 1;
    }

    // The compositor listens until the read end of this pipe hangs up (we exit)
    int close_fds[2];
    if (pipe2(close_fds, O_CLOEXEC) < 0) {
        perror("wl-security-context: pipe");
        unlink(path);
        return 1;
    }

    struct wp_security_context_v1 *context =
        wp_security_context_manager_v1_create_listener(manager, listen_fd, close_fds[0]);
    wp_security_context_v1_set_sandbox_engine(context, "org.riptide.sandbox");
    wp_security_context_v1_set_app_id(context, argv[2]);
    wp_security_context_v1_set_instance_id(context, argv[3]);
    wp_security_context_v1_commit(context);
    wp_security_context_v1_destroy(context);
    if (wl_display_roundtrip(display) < 0) {
        fprintf(stderr, "wl-security-context: the compositor refused the security context\n");
        unlink(path);
        return 1;
    }
    close(listen_fd);
    close(close_fds[0]);

    printf("ready\n");
    fflush(stdout);
    struct pollfd watch = {.fd = STDIN_FILENO, .events = POLLIN};
    for (;;) {
        if (poll(&watch, 1, -1) < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        if (watch.revents & (POLLHUP | POLLERR | POLLNVAL))
            break;
        char buffer[64];
        if ((watch.revents & POLLIN) && read(STDIN_FILENO, buffer, sizeof buffer) <= 0)
            break;
    }
    unlink(path);
    return 0;
}
