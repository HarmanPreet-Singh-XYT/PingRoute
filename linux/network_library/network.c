#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <netdb.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include "network.h"

#define MAX_HOPS 30
#define MAX_TRIES 1
#define TIMEOUT 1 // 1 second timeout
#define MAX_DOMAIN_NAME 256
#define ICMP_DATA_SIZE 32

// glibc's <netinet/ip_icmp.h> defines ICMP_TIME_EXCEEDED; some libc variants
// spell it ICMP_TIMXCEED instead. Fall back to the raw IANA ICMP type value
// (11) if neither macro is available so this still compiles portably.
#if !defined(ICMP_TIME_EXCEEDED) && defined(ICMP_TIMXCEED)
#define ICMP_TIME_EXCEEDED ICMP_TIMXCEED
#elif !defined(ICMP_TIME_EXCEEDED)
#define ICMP_TIME_EXCEEDED 11
#endif

typedef struct {
    char ip[16];           // IPv4 address string
    char domain[MAX_DOMAIN_NAME]; // Domain name
    int ping;              // Round-trip time in milliseconds
} HopData;

typedef struct {
    HopData* hops;
    int count;
} TracerouteResult;

// Calculate checksum for ICMP header
unsigned short checksum(void *b, int len) {    
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
void resolve_domain(const char* ip, char* domain, size_t domain_size) {
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    inet_pton(AF_INET, ip, &(sa.sin_addr));

    if (getnameinfo((struct sockaddr*)&sa, sizeof(sa), domain, domain_size, NULL, 0, NI_NAMEREQD) != 0) {
        strncpy(domain, "Unknown", domain_size);
        domain[domain_size - 1] = '\0';
    }
}

// Locate the ICMP header within a packet received on a SOCK_RAW/IPPROTO_ICMP
// socket. Unlike SOCK_DGRAM ICMP, raw sockets on Linux always deliver the
// full IPv4 header ahead of the ICMP payload, so it must be skipped using
// its own header-length field before the ICMP type can be inspected.
static struct icmp* locate_icmp_header(unsigned char* buf, int recv_len) {
    if (recv_len < (int)sizeof(struct ip)) {
        return NULL;
    }
    struct ip* ip_hdr = (struct ip*)buf;
    int ip_header_len = ip_hdr->ip_hl * 4;
    if (recv_len < ip_header_len + (int)sizeof(struct icmp)) {
        return NULL;
    }
    return (struct icmp*)(buf + ip_header_len);
}

// A Time Exceeded message's payload embeds the original IPv4 header + first
// 8 bytes of our ICMP echo request, which is how we confirm a received
// packet actually answers *our* probe (and not unrelated ICMP traffic any
// other process/hop happens to be generating, which a raw ICMP socket also
// receives). For an Echo Reply the kernel instead echoes our id/seq back
// directly in the outer ICMP header.
static int response_matches_probe(struct icmp* icmp_reply, int recv_len,
                                   unsigned char* icmp_start, uint16_t expected_id,
                                   uint16_t expected_seq) {
    if (icmp_reply->icmp_type == ICMP_ECHOREPLY) {
        return icmp_reply->icmp_id == expected_id && icmp_reply->icmp_seq == expected_seq;
    }
    if (icmp_reply->icmp_type == ICMP_TIME_EXCEEDED || icmp_reply->icmp_type == ICMP_UNREACH) {
        unsigned char* payload = (unsigned char*)icmp_reply + 8; // past outer ICMP header
        int remaining = recv_len - (int)(payload - icmp_start);
        if (remaining < (int)sizeof(struct ip)) return 0;

        struct ip* orig_ip = (struct ip*)payload;
        int orig_ip_len = orig_ip->ip_hl * 4;
        if (remaining < orig_ip_len + (int)sizeof(struct icmp)) return 0;

        struct icmp* orig_icmp = (struct icmp*)(payload + orig_ip_len);
        return orig_icmp->icmp_type == ICMP_ECHO &&
               orig_icmp->icmp_id == expected_id &&
               orig_icmp->icmp_seq == expected_seq;
    }
    return 0;
}

// Perform traceroute using raw sockets for ICMP Echo
TracerouteResult get_traceroute_data(const char* destination) {
    int sockfd;
    struct sockaddr_in dest_addr;
    struct addrinfo hints, *res;
    int ttl = 1, max_ttl = MAX_HOPS;
    TracerouteResult result = {NULL, 0};
    result.hops = (HopData*)malloc(MAX_HOPS * sizeof(HopData));

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_RAW;
    hints.ai_protocol = IPPROTO_ICMP;

    if (getaddrinfo(destination, NULL, &hints, &res) != 0) {
        printf("Unable to resolve %s\n", destination);
        return result;
    }

    memcpy(&dest_addr, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);

    if ((sockfd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP)) < 0) {
        perror("socket creation failed");
        return result;
    }

    uint16_t probe_id = (uint16_t)(getpid() & 0xFFFF);

    for (int i = 1; i <= max_ttl; i++) {
        struct icmp icmp_hdr;
        unsigned char recv_buffer[1024];
        struct sockaddr_in reply_addr;
        socklen_t reply_len = sizeof(reply_addr);
        HopData hop = {"", "", -1};  // Initialize with empty IP, empty domain, and -1 ping
        uint16_t probe_seq = (uint16_t)i;

        // Set the TTL
        if (setsockopt(sockfd, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
            perror("setsockopt");
            break;
        }

        // Prepare ICMP header
        memset(&icmp_hdr, 0, sizeof(icmp_hdr));
        icmp_hdr.icmp_type = ICMP_ECHO;
        icmp_hdr.icmp_code = 0;
        icmp_hdr.icmp_id = probe_id;
        icmp_hdr.icmp_seq = probe_seq;
        icmp_hdr.icmp_cksum = 0;
        icmp_hdr.icmp_cksum = checksum(&icmp_hdr, sizeof(icmp_hdr));

        // Send ICMP Echo Request
        struct timespec start_time, end_time;
        clock_gettime(CLOCK_MONOTONIC, &start_time);
        if (sendto(sockfd, &icmp_hdr, sizeof(icmp_hdr), 0,
                   (struct sockaddr*)&dest_addr, sizeof(dest_addr)) <= 0) {
            perror("sendto");
            break;
        }

        // Set timeout for receiving
        struct timeval timeout = {TIMEOUT, 0};
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

        int is_destination_reached = 0;

        // A raw ICMP socket receives every ICMP packet delivered to this
        // host, including replies to other hops' probes or unrelated
        // traffic — keep reading until we find one that actually matches
        // this probe's id/seq, or the receive timeout elapses.
        while (1) {
            int recv_len = recvfrom(sockfd, recv_buffer, sizeof(recv_buffer), 0,
                                    (struct sockaddr*)&reply_addr, &reply_len);
            if (recv_len <= 0) {
                break; // timed out waiting for this hop
            }

            struct icmp* icmp_reply = locate_icmp_header(recv_buffer, recv_len);
            if (icmp_reply == NULL ||
                !response_matches_probe(icmp_reply, recv_len, recv_buffer, probe_id, probe_seq)) {
                continue; // not our probe's response, keep listening
            }

            clock_gettime(CLOCK_MONOTONIC, &end_time);
            double time_spent = (end_time.tv_sec - start_time.tv_sec) * 1000.0 +
                                (end_time.tv_nsec - start_time.tv_nsec) / 1000000.0;

            strncpy(hop.ip, inet_ntoa(reply_addr.sin_addr), sizeof(hop.ip) - 1);
            hop.ip[sizeof(hop.ip) - 1] = '\0';
            hop.ping = (int)time_spent;

            resolve_domain(hop.ip, hop.domain, sizeof(hop.domain));

            is_destination_reached = (icmp_reply->icmp_type == ICMP_ECHOREPLY);
            break;
        }

        // Record this hop whether it replied or timed out, so silent/
        // filtered routers still show up as a row instead of being skipped
        // (which previously made only the final responding hop appear).
        result.hops[result.count++] = hop;

        if (is_destination_reached) {
            break;
        }

        ttl++;
    }

    close(sockfd);
    return result;
}

// Get traceroute array as JSON-like string for each hop
char** get_traceroute_array(const char* destination, int* hop_count) {
    TracerouteResult result = get_traceroute_data(destination);
    *hop_count = result.count;

    char** traceroute_array = (char**)malloc(result.count * sizeof(char*));
    if (traceroute_array == NULL) {
        printf("Unable to allocate memory for traceroute array\n");
        return NULL;
    }

    for (int i = 0; i < result.count; i++) {
        size_t buffer_size = 512;
        traceroute_array[i] = (char*)malloc(buffer_size);
        if (traceroute_array[i] == NULL) {
            printf("Unable to allocate memory for traceroute entry\n");
            for (int j = 0; j < i; j++) {
                free(traceroute_array[j]);
            }
            free(traceroute_array);
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
int main(int argc, char *argv[]) {
    return 0;
}