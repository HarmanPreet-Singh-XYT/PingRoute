#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <windows.h>
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")

#define MAX_HOPS 30
#define MAX_TRIES 1
#define TIMEOUT 100
#define MAX_DOMAIN_NAME 256

typedef struct {
    char ip[16];           // IPv4 address string
    char domain[MAX_DOMAIN_NAME]; // Domain name
    int ping;              // Round-trip time in milliseconds
} HopData;

typedef struct {
    HopData* hops;
    int count;
} TracerouteResult;

unsigned short checksum(void *b, int len) { 
    unsigned short *buf = b;
    unsigned int sum = 0;
    unsigned short result;
    int nleft = len;
    while (nleft > 1) {
        sum += *buf++;
        nleft -= 2;
    }
    if (nleft == 1) {
        *(unsigned char *)(&result) = *(unsigned char *)buf;
        sum += result;
    }
    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);
    result = ~sum;
    return result;
}


void resolve_domain(const char* ip, char* domain, size_t domain_size) {
    struct sockaddr_in sa;
    sa.sin_family = AF_INET;
    inet_pton(AF_INET, ip, &(sa.sin_addr));

    if (getnameinfo((struct sockaddr*)&sa, sizeof(sa), domain, domain_size, NULL, 0, NI_NAMEREQD) != 0) {
        strncpy(domain, "Unknown", domain_size);
        domain[domain_size - 1] = '\0';
    }
}

TracerouteResult get_traceroute_data(const char* destination) {
    HANDLE hIcmpFile;
    unsigned long ipaddr = INADDR_NONE;
    DWORD dwRetVal = 0;
    char SendData[32] = "Data Buffer";
    LPVOID ReplyBuffer = NULL;
    DWORD ReplySize = 0;
    TracerouteResult result = {NULL, 0};
    
    hIcmpFile = IcmpCreateFile();
    if (hIcmpFile == INVALID_HANDLE_VALUE) {
        printf("\tUnable to open handle.\n");
        printf("IcmpCreatefile returned error: %ld\n", GetLastError());
        return result;
    }

    ipaddr = inet_addr(destination);
    if (ipaddr == INADDR_NONE) {
        // If not an IP address, try to resolve domain name
        struct addrinfo hints, *res;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;

        if (getaddrinfo(destination, NULL, &hints, &res) != 0) {
            printf("Unable to resolve %s\n", destination);
            return result;
        }

        ipaddr = ((struct sockaddr_in*)(res->ai_addr))->sin_addr.S_un.S_addr;
        freeaddrinfo(res);
    }

    ReplySize = sizeof(ICMP_ECHO_REPLY) + sizeof(SendData);
    ReplyBuffer = (VOID*)malloc(ReplySize);
    if (ReplyBuffer == NULL) {
        printf("\tUnable to allocate memory\n");
        return result;
    }

    result.hops = (HopData*)malloc(MAX_HOPS * sizeof(HopData));
    if (result.hops == NULL) {
        printf("\tUnable to allocate memory for result\n");
        free(ReplyBuffer);
        return result;
    }

    for (int i = 1; i <= MAX_HOPS; i++) {
        int timeouts = 0;
        HopData hop = {"", "", -1};  // Initialize with empty IP, empty domain, and -1 ping

        for (int j = 0; j < MAX_TRIES; j++) {
            IP_OPTION_INFORMATION IpOption = {0};
            IpOption.Ttl = i;

            dwRetVal = IcmpSendEcho2(hIcmpFile, NULL, NULL, NULL,
                                     ipaddr, SendData, sizeof(SendData), 
                                     &IpOption, ReplyBuffer, ReplySize, TIMEOUT);

            if (dwRetVal != 0) {
                PICMP_ECHO_REPLY pEchoReply = (PICMP_ECHO_REPLY)ReplyBuffer;
                struct in_addr ReplyAddr;
                ReplyAddr.S_un.S_addr = pEchoReply->Address;
                strncpy(hop.ip, inet_ntoa(ReplyAddr), sizeof(hop.ip) - 1);
                hop.ip[sizeof(hop.ip) - 1] = '\0';  // Ensure null-termination
                hop.ping = pEchoReply->RoundTripTime;

                // Resolve domain name
                resolve_domain(hop.ip, hop.domain, sizeof(hop.domain));

                if (pEchoReply->Status == IP_SUCCESS) {
                    break;  // We've reached the destination
                }
            } else {
                timeouts++;
            }
        }

        if (strlen(hop.ip) > 0) {
            result.hops[result.count++] = hop;
        }

        if (timeouts < MAX_TRIES) {
            PICMP_ECHO_REPLY pEchoReply = (PICMP_ECHO_REPLY)ReplyBuffer;
            if (pEchoReply->Status == IP_SUCCESS) {
                break;  // We've reached the destination
            }
        }
    }

    free(ReplyBuffer);
    IcmpCloseHandle(hIcmpFile);
    return result;
}

char** get_traceroute_array(const char* destination, int* hop_count) {
    TracerouteResult result = get_traceroute_data(destination);
    *hop_count = result.count;

    char** traceroute_array = (char**)malloc(result.count * sizeof(char*));
    if (traceroute_array == NULL) {
        printf("Unable to allocate memory for traceroute array\n");
        return NULL;
    }

    for (int i = 0; i < result.count; i++) {
        size_t buffer_size = 512;  // Adjust size if needed
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

    // Free the original result data
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

long ping(const char *target) {
    #define ICMP_ECHO 8
    #define ICMP_ECHO_REPLY 0
    WSADATA wsaData;
    SOCKET sock;
    struct sockaddr_in addr;
    struct icmp_echo {
        unsigned char type;
        unsigned char code;
        unsigned short checksum;
        unsigned short id;
        unsigned short sequence;
        char data[32];
    } icmp_hdr;
    char buffer[1024];
    int addr_len = sizeof(addr);
    int received_bytes;
    LARGE_INTEGER start, end, frequency;
    long elapsed_time;

    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        fprintf(stderr, "WSAStartup failed\n");
        return -1;
    }

    // Create a raw socket
    sock = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
    if (sock == INVALID_SOCKET) {
        fprintf(stderr, "Socket creation failed\n");
        WSACleanup();
        return -1;
    }

    // Prepare sockaddr_in
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr(target);

    // Prepare ICMP header
    memset(&icmp_hdr, 0, sizeof(icmp_hdr));
    icmp_hdr.type = ICMP_ECHO;
    icmp_hdr.code = 0;
    icmp_hdr.id = GetCurrentProcessId();
    icmp_hdr.sequence = 1;
    icmp_hdr.checksum = checksum(&icmp_hdr, sizeof(icmp_hdr));

    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&start);

    // Send ICMP packet
    if (sendto(sock, (char *)&icmp_hdr, sizeof(icmp_hdr), 0, (struct sockaddr *)&addr, sizeof(addr)) == SOCKET_ERROR) {
        fprintf(stderr, "Send failed\n");
        closesocket(sock);
        WSACleanup();
        return -1;
    }

    // Receive ICMP packet
    received_bytes = recvfrom(sock, buffer, sizeof(buffer), 0, (struct sockaddr *)&addr, &addr_len);
    if (received_bytes == SOCKET_ERROR) {
        fprintf(stderr, "Receive failed\n");
        closesocket(sock);
        WSACleanup();
        return -1;
    }

    QueryPerformanceCounter(&end);

    elapsed_time = (end.QuadPart - start.QuadPart) * 1000 / frequency.QuadPart;

    closesocket(sock);
    WSACleanup();

    return elapsed_time;
}


int main(int argc, char **argv) {
    // if (argc != 2) {
    //     printf("Usage: %s <ip address or domain>\n", argv[0]);
    //     return 1;
    // }

    // WSADATA wsaData;
    // if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
    //     printf("WSAStartup failed. Error: %d\n", WSAGetLastError());
    //     return 1;
    // }

    // int hop_count = 0;
    // char** traceroute_array = get_traceroute_array(argv[1], &hop_count);

    // if (traceroute_array != NULL) {
    //     printf("[\n");
    //     for (int i = 0; i < hop_count; i++) {
    //         printf("  %s%s\n", traceroute_array[i], (i < hop_count - 1) ? "," : "");
    //         free(traceroute_array[i]);  // Free each entry
    //     }
    //     printf("]\n");
    //     free(traceroute_array);  // Free the array itself
    // }

    // WSACleanup();
    return 0;
}
