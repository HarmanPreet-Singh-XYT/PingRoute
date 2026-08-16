/*
 * pingroute-net — standalone traceroute helper
 *
 * Usage: pingroute-net <destination>
 *
 * Runs a traceroute and prints one hop-string per line to stdout:
 *   {hop:1, ip:192.168.1.1, name:router.local, ping:3}
 *   {hop:2, ip:, name:Unknown, ping:-1}
 *   ...
 *
 * Requires CAP_NET_RAW (or root) to open raw ICMP sockets.
 * Set once after installation:
 *   sudo setcap cap_net_raw+ep /path/to/pingroute-net
 *
 * Snap and Flatpak users get this automatically via the network-control
 * interface / finish-arg added to those manifests.
 */

#include <stdio.h>
#include <stdlib.h>
#include "network.h"

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "usage: pingroute-net <destination>\n");
        return 1;
    }

    int hop_count = 0;
    char **hops = get_traceroute_array(argv[1], &hop_count);
    if (hops == NULL) {
        return 1;
    }

    for (int i = 0; i < hop_count; i++) {
        printf("%s\n", hops[i]);
    }
    fflush(stdout);

    free_traceroute_array(hops, hop_count);
    return 0;
}
