#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <netdb.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include "network.h"

#define MAX_HOPS 30
#define TIMEOUT 1 // 1 second timeout
#define MAX_DOMAIN_NAME 256

typedef struct {
    char ip[16];                  // IPv4 address string
    char domain[MAX_DOMAIN_NAME]; // Domain name
    int ping;                     // Round-trip time in milliseconds
} HopData;

typedef struct {
    HopData* hops;
    int count;
} TracerouteResult;

// Calculate checksum for ICMP header
static unsigned short checksum(void *b, int len) {
    unsigned short *buf = b;
    unsigned int sum = 0;
    unsigned short result;

    for (sum = 0; len > 1; len -= 2) {
        sum += *buf++;
    }
    if (len == 1) {
        sum += *(unsigned char*)buf;
    }
    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);
    result = ~sum;
    return result;
}

// Resolve domain from IP address
static void resolve_domain(const char* ip, char* domain, size_t domain_size) {
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    inet_pton(AF_INET, ip, &(sa.sin_addr));

    if (getnameinfo((struct sockaddr*)&sa, sizeof(sa), domain, (socklen_t)domain_size, NULL, 0, NI_NAMEREQD) != 0) {
        strncpy(domain, "Unknown", domain_size);
        domain[domain_size - 1] = '\0';
    }
}

// Locate the ICMP header within a received datagram on Darwin / iOS
static struct icmp* locate_icmp_header(unsigned char* buf, int recv_len) {
    if (recv_len < (int)sizeof(struct icmp)) {
        return NULL;
    }

    struct icmp* candidate_a = (struct icmp*)buf;
    if (candidate_a->icmp_type == ICMP_ECHOREPLY ||
        candidate_a->icmp_type == ICMP_TIMXCEED ||
        candidate_a->icmp_type == ICMP_UNREACH) {
        return candidate_a;
    }

    if (recv_len >= (int)sizeof(struct ip) + (int)sizeof(struct icmp)) {
        struct ip* ip_hdr = (struct ip*)buf;
        int ip_header_len = ip_hdr->ip_hl * 4;
        if (recv_len >= ip_header_len + (int)sizeof(struct icmp)) {
            struct icmp* candidate_b = (struct icmp*)(buf + ip_header_len);
            if (candidate_b->icmp_type == ICMP_ECHOREPLY ||
                candidate_b->icmp_type == ICMP_TIMXCEED ||
                candidate_b->icmp_type == ICMP_UNREACH) {
                return candidate_b;
            }
        }
    }

    return NULL;
}

static TracerouteResult get_traceroute_data(const char* destination) {
    int sockfd;
    struct sockaddr_in dest_addr;
    struct addrinfo hints, *res;
    int ttl = 1, max_ttl = MAX_HOPS;
    TracerouteResult result = {NULL, 0};
    result.hops = (HopData*)malloc(MAX_HOPS * sizeof(HopData));
    if (!result.hops) return result;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;

    if (getaddrinfo(destination, NULL, &hints, &res) != 0) {
        return result;
    }

    memcpy(&dest_addr, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);

    if ((sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)) < 0) {
        if ((sockfd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)) < 0) {
            return result;
        }
    }

    unsigned short seq = (unsigned short)(getpid() & 0xFFFF);

    for (int i = 1; i <= max_ttl; i++) {
        struct icmp icmp_hdr;
        unsigned char recv_buffer[1024];
        struct sockaddr_in reply_addr;
        socklen_t reply_len = sizeof(reply_addr);
        HopData hop = {"", "", -1};

        if (setsockopt(sockfd, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
            break;
        }

        memset(&icmp_hdr, 0, sizeof(icmp_hdr));
        icmp_hdr.icmp_type = ICMP_ECHO;
        icmp_hdr.icmp_code = 0;
        icmp_hdr.icmp_id = 0;
        icmp_hdr.icmp_seq = seq++;
        icmp_hdr.icmp_cksum = checksum(&icmp_hdr, sizeof(icmp_hdr));

        struct timespec start_time, end_time;
        clock_gettime(CLOCK_MONOTONIC, &start_time);
        if (sendto(sockfd, &icmp_hdr, sizeof(icmp_hdr), 0,
                   (struct sockaddr*)&dest_addr, sizeof(dest_addr)) <= 0) {
            break;
        }

        struct timeval timeout = {TIMEOUT, 0};
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

        int recv_len = (int)recvfrom(sockfd, recv_buffer, sizeof(recv_buffer), 0,
                                      (struct sockaddr*)&reply_addr, &reply_len);
        clock_gettime(CLOCK_MONOTONIC, &end_time);

        if (recv_len > 0) {
            struct icmp* icmp_reply = locate_icmp_header(recv_buffer, recv_len);
            int is_destination_reached = 0;

            if (icmp_reply != NULL &&
                (icmp_reply->icmp_type == ICMP_ECHOREPLY ||
                 icmp_reply->icmp_type == ICMP_TIMXCEED)) {
                double time_spent = (end_time.tv_sec - start_time.tv_sec) * 1000.0 +
                                    (end_time.tv_nsec - start_time.tv_nsec) / 1000000.0;

                strncpy(hop.ip, inet_ntoa(reply_addr.sin_addr), sizeof(hop.ip) - 1);
                hop.ip[sizeof(hop.ip) - 1] = '\0';
                hop.ping = (int)time_spent;

                resolve_domain(hop.ip, hop.domain, sizeof(hop.domain));
                is_destination_reached = (icmp_reply->icmp_type == ICMP_ECHOREPLY);
                result.hops[result.count++] = hop;
            }

            if (is_destination_reached) {
                break;
            }
        } else {
            result.hops[result.count++] = hop;
        }

        ttl++;
    }

    close(sockfd);
    return result;
}

char** get_traceroute_array(const char* destination, int* hop_count) {
    TracerouteResult result = get_traceroute_data(destination);
    *hop_count = result.count;

    if (result.count == 0 || result.hops == NULL) {
        if (result.hops != NULL) free(result.hops);
        return NULL;
    }

    char** traceroute_array = (char**)malloc(result.count * sizeof(char*));
    if (traceroute_array == NULL) {
        free(result.hops);
        return NULL;
    }

    for (int i = 0; i < result.count; i++) {
        size_t buffer_size = 512;
        traceroute_array[i] = (char*)malloc(buffer_size);
        if (traceroute_array[i] == NULL) {
            for (int j = 0; j < i; j++) free(traceroute_array[j]);
            free(traceroute_array);
            free(result.hops);
            return NULL;
        }

        snprintf(traceroute_array[i], buffer_size,
                 "{hop:%d, ip:%s, name:%s, ping:%d}",
                 i + 1, result.hops[i].ip, result.hops[i].domain, result.hops[i].ping);
    }

    if (result.hops != NULL) {
        free(result.hops);
    }

    return traceroute_array;
}

void free_traceroute_array(char** array, int hop_count) {
    if (array == NULL) return;

    for (int i = 0; i < hop_count; i++) {
        if (array[i] != NULL) {
            free(array[i]);
        }
    }
    free(array);
}
