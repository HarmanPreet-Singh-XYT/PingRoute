#include <stdio.h>
#include <stdlib.h>
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

#define MAX_HOPS 30
#define MAX_TRIES 1
#define TIMEOUT 1 // 1 second timeout
#define MAX_DOMAIN_NAME 256
#define ICMP_DATA_SIZE 32

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
    sa.sin_family = AF_INET;
    inet_pton(AF_INET, ip, &(sa.sin_addr));

    if (getnameinfo((struct sockaddr*)&sa, sizeof(sa), domain, domain_size, NULL, 0, NI_NAMEREQD) != 0) {
        strncpy(domain, "Unknown", domain_size);
        domain[domain_size - 1] = '\0';
    }
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

    for (int i = 1; i <= max_ttl; i++) {
        struct icmp icmp_hdr;
        char recv_buffer[1024];
        struct sockaddr_in reply_addr;
        socklen_t reply_len = sizeof(reply_addr);
        HopData hop = {"", "", -1};  // Initialize with empty IP, empty domain, and -1 ping

        // Set the TTL
        if (setsockopt(sockfd, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
            perror("setsockopt");
            break;
        }

        // Prepare ICMP header
        memset(&icmp_hdr, 0, sizeof(icmp_hdr));
        icmp_hdr.icmp_type = ICMP_ECHO;
        icmp_hdr.icmp_code = 0;
        icmp_hdr.icmp_id = getpid();
        icmp_hdr.icmp_seq = i;
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

        // Receive ICMP Echo Reply
        int recv_len = recvfrom(sockfd, recv_buffer, sizeof(recv_buffer), 0, 
                                (struct sockaddr*)&reply_addr, &reply_len);
        clock_gettime(CLOCK_MONOTONIC, &end_time);

        if (recv_len > 0) {
            double time_spent = (end_time.tv_sec - start_time.tv_sec) * 1000.0 +
                                (end_time.tv_nsec - start_time.tv_nsec) / 1000000.0;

            // Store IP address and RTT
            strncpy(hop.ip, inet_ntoa(reply_addr.sin_addr), sizeof(hop.ip) - 1);
            hop.ping = (int)time_spent;
            
            // Resolve domain
            resolve_domain(hop.ip, hop.domain, sizeof(hop.domain));

            result.hops[result.count++] = hop;
        } else {
            printf("Hop %d: Timeout\n", i);
        }

        ttl++;
        if (strcmp(hop.ip, inet_ntoa(dest_addr.sin_addr)) == 0) {
            // Reached destination
            break;
        }
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