#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <sys/uio.h>
#include <linux/errqueue.h>
#include "network.h"

#define MAX_HOPS           30
#define TIMEOUT_MS        600  // 600ms per hop
#define MAX_CONSECUTIVE_MISS 8
#define MAX_DOMAIN_NAME   256
#define UDP_BASE_PORT   33434  // Classic traceroute base port

#ifndef IP_RECVERR
#define IP_RECVERR 11
#endif

typedef struct {
    char ip[16];
    char domain[MAX_DOMAIN_NAME];
    int  ping;
} HopData;

typedef struct {
    HopData *hops;
    int      count;
} TracerouteResult;

// Fast IP-to-domain assignment without blocking synchronous DNS PTR queries.
static void set_hop_domain(const char *ip, char *domain, size_t domain_size) {
    if (ip[0] != '\0') {
        strncpy(domain, ip, domain_size - 1);
    } else {
        strncpy(domain, "Unknown", domain_size - 1);
    }
    domain[domain_size - 1] = '\0';
}

// ── Native Unprivileged Linux Traceroute (UDP + IP_RECVERR) ────────────────
//
// Modern Linux kernels deliver ICMP Time Exceeded (Type 11) and ICMP Port
// Unreachable (Type 3) messages directly to unprivileged UDP sockets via the
// socket error queue (IP_RECVERR + MSG_ERRQUEUE).
//
// No raw sockets, no root/CAP_NET_RAW, no external CLI tools required!

TracerouteResult get_traceroute_data(const char *destination) {
    TracerouteResult result = {NULL, 0};
    result.hops = (HopData *)malloc(MAX_HOPS * sizeof(HopData));
    if (!result.hops) return result;

    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    if (getaddrinfo(destination, NULL, &hints, &res) != 0) return result;

    struct sockaddr_in dest_addr;
    memcpy(&dest_addr, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);

    int consecutive_misses = 0;

    for (int ttl = 1; ttl <= MAX_HOPS; ttl++) {
        HopData hop = {"", "Unknown", -1};

        // Create standard unprivileged UDP socket
        int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock < 0) break;

        // Enable IP_RECVERR so kernel passes ICMP errors to socket error queue
        int val = 1;
        if (setsockopt(sock, SOL_IP, IP_RECVERR, &val, sizeof(val)) < 0) {
            close(sock);
            break;
        }

        // Set IP_TTL
        if (setsockopt(sock, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
            close(sock);
            break;
        }

        dest_addr.sin_port = htons(UDP_BASE_PORT + ttl);

        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);

        char payload[] = "pingroute";
        if (sendto(sock, payload, sizeof(payload), 0,
                   (struct sockaddr *)&dest_addr, sizeof(dest_addr)) < 0) {
            close(sock);
            break;
        }

        char control[1024];
        char data[1024];
        struct iovec iov = { .iov_base = data, .iov_len = sizeof(data) };
        struct msghdr msg = {
            .msg_name = NULL,
            .msg_namelen = 0,
            .msg_iov = &iov,
            .msg_iovlen = 1,
            .msg_control = control,
            .msg_controllen = sizeof(control)
        };

        int is_destination_reached = 0;
        int res_code = -1;

        // Poll socket error queue for ICMP response
        for (int retry = 0; retry < 30; retry++) {
            usleep(20000); // 20ms sleep per check (total timeout ~600ms)
            res_code = recvmsg(sock, &msg, MSG_ERRQUEUE);
            if (res_code >= 0) break;
        }

        clock_gettime(CLOCK_MONOTONIC, &t1);

        if (res_code >= 0) {
            double rtt = (t1.tv_sec - t0.tv_sec) * 1000.0 +
                         (t1.tv_nsec - t0.tv_nsec) / 1000000.0;

            int icmp_type = -1;

            for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL; cmsg = CMSG_NXTHDR(&msg, cmsg)) {
                if (cmsg->cmsg_level == SOL_IP && cmsg->cmsg_type == IP_RECVERR) {
                    struct sock_extended_err *ee = (struct sock_extended_err *)CMSG_DATA(cmsg);
                    struct sockaddr_in *offender = (struct sockaddr_in *)SO_EE_OFFENDER(ee);
                    if (offender && offender->sin_family == AF_INET) {
                        snprintf(hop.ip, sizeof(hop.ip), "%s", inet_ntoa(offender->sin_addr));
                        hop.ping = (int)rtt;
                        set_hop_domain(hop.ip, hop.domain, sizeof(hop.domain));

                        if (offender->sin_addr.s_addr == dest_addr.sin_addr.s_addr) {
                            is_destination_reached = 1;
                        }
                    }
                    icmp_type = ee->ee_type;
                }
            }

            if (icmp_type == ICMP_UNREACH) {
                is_destination_reached = 1;
            }
        }

        close(sock);

        result.hops[result.count++] = hop;

        if (hop.ping >= 0) {
            consecutive_misses = 0;
        } else {
            consecutive_misses++;
        }

        if (is_destination_reached || consecutive_misses >= MAX_CONSECUTIVE_MISS) {
            break;
        }
    }

    return result;
}

char **get_traceroute_array(const char *destination, int *hop_count) {
    TracerouteResult result = get_traceroute_data(destination);
    *hop_count = result.count;

    char **arr = (char **)malloc(result.count * sizeof(char *));
    if (!arr) { free(result.hops); return NULL; }

    for (int i = 0; i < result.count; i++) {
        arr[i] = (char *)malloc(512);
        if (!arr[i]) {
            for (int j = 0; j < i; j++) free(arr[j]);
            free(arr);
            free(result.hops);
            return NULL;
        }
        snprintf(arr[i], 512, "{hop:%d, ip:%s, name:%s, ping:%d}",
                 i + 1,
                 result.hops[i].ip,
                 result.hops[i].domain,
                 result.hops[i].ping);
    }

    free(result.hops);
    return arr;
}

void free_traceroute_array(char **array, int hop_count) {
    if (!array) return;
    for (int i = 0; i < hop_count; i++) free(array[i]);
    free(array);
}