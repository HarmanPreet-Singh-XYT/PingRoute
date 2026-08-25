#include "network.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define MAX_HOPS 30
#define TIMEOUT_SEC 1
#define TIMEOUT_USEC 200000 // 1.2s timeout per probe
#define MAX_DOMAIN_NAME 256
#define BASE_PORT 33434

typedef struct {
  char ip[46];                  // IPv4/IPv6 address string
  char domain[MAX_DOMAIN_NAME]; // Domain name or Unknown
  int ping;                     // Round-trip time in milliseconds (-1 if loss)
} HopData;

typedef struct {
  HopData *hops;
  int count;
} TracerouteResult;

// Resolve domain name from IP address
static void resolve_domain(const char *ip, char *domain, size_t domain_size) {
  if (ip == NULL || ip[0] == '\0' || strcmp(ip, "*") == 0) {
    strncpy(domain, "Unknown", domain_size);
    domain[domain_size - 1] = '\0';
    return;
  }
  struct sockaddr_in sa;
  memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET;
  if (inet_pton(AF_INET, ip, &(sa.sin_addr)) <= 0) {
    strncpy(domain, "Unknown", domain_size);
    domain[domain_size - 1] = '\0';
    return;
  }

  if (getnameinfo((struct sockaddr *)&sa, sizeof(sa), domain,
                  (socklen_t)domain_size, NULL, 0, NI_NAMEREQD) != 0) {
    strncpy(domain, "Unknown", domain_size);
    domain[domain_size - 1] = '\0';
  }
}

// Locate ICMP header inside received datagram (offset by IP header if present)
static struct icmp *locate_icmp_header(unsigned char *buf, int recv_len) {
  if (recv_len < (int)sizeof(struct icmp)) {
    return NULL;
  }

  struct icmp *candidate_a = (struct icmp *)buf;
  if (candidate_a->icmp_type == ICMP_ECHOREPLY ||
      candidate_a->icmp_type == ICMP_TIMXCEED ||
      candidate_a->icmp_type == ICMP_UNREACH) {
    return candidate_a;
  }

  if (recv_len >= (int)sizeof(struct ip) + (int)sizeof(struct icmp)) {
    struct ip *ip_hdr = (struct ip *)buf;
    int ip_header_len = ip_hdr->ip_hl * 4;
    if (recv_len >= ip_header_len + (int)sizeof(struct icmp)) {
      struct icmp *candidate_b = (struct icmp *)(buf + ip_header_len);
      if (candidate_b->icmp_type == ICMP_ECHOREPLY ||
          candidate_b->icmp_type == ICMP_TIMXCEED ||
          candidate_b->icmp_type == ICMP_UNREACH) {
        return candidate_b;
      }
    }
  }

  return NULL;
}

// Drain any unread packets before sending next probe
static void drain_socket(int sockfd) {
  if (sockfd < 0)
    return;
  unsigned char dummy[1024];
  while (recvfrom(sockfd, dummy, sizeof(dummy), MSG_DONTWAIT, NULL, NULL) > 0) {
  }
}

static TracerouteResult get_traceroute_data(const char *destination) {
  struct sockaddr_in dest_addr;
  struct addrinfo hints, *res = NULL;
  int max_ttl = MAX_HOPS;
  TracerouteResult result = {NULL, 0};
  result.hops = (HopData *)calloc(MAX_HOPS + 4, sizeof(HopData));
  if (!result.hops)
    return result;

  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_DGRAM;

  if (getaddrinfo(destination, NULL, &hints, &res) != 0 || res == NULL) {
    if (res)
      freeaddrinfo(res);
    return result;
  }

  memcpy(&dest_addr, res->ai_addr, sizeof(struct sockaddr_in));
  freeaddrinfo(res);

  char dest_ip_str[INET_ADDRSTRLEN] = {0};
  inet_ntop(AF_INET, &(dest_addr.sin_addr), dest_ip_str, sizeof(dest_ip_str));

  // 1. Outbound UDP probe socket
  int send_sock = socket(AF_INET, SOCK_DGRAM, 0);
  if (send_sock < 0) {
    strncpy(result.hops[0].ip, dest_ip_str, sizeof(result.hops[0].ip) - 1);
    resolve_domain(result.hops[0].ip, result.hops[0].domain,
                   sizeof(result.hops[0].domain));
    result.hops[0].ping = -1;
    result.count = 1;
    return result;
  }

  // 2. Inbound ICMP listener socket (SOCK_DGRAM with IPPROTO_ICMP on Darwin)
  int recv_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
  if (recv_sock < 0) {
    recv_sock = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
  }

  int is_destination_reached = 0;
  int consecutive_timeouts = 0;

  for (int ttl = 1; ttl <= max_ttl; ttl++) {
    HopData hop = {"*", "Unknown", -1};
    uint16_t expected_port = (uint16_t)(BASE_PORT + ttl);

    if (setsockopt(send_sock, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
      break;
    }

    drain_socket(recv_sock);

    dest_addr.sin_port = htons(expected_port);

    char payload[32];
    snprintf(payload, sizeof(payload), "PR_%d", ttl);

    struct timespec start_time, now_time;
    clock_gettime(CLOCK_MONOTONIC, &start_time);

    if (sendto(send_sock, payload, strlen(payload), 0,
               (struct sockaddr *)&dest_addr, sizeof(dest_addr)) <= 0) {
      break;
    }

    double total_timeout_ms = (TIMEOUT_SEC * 1000.0) + (TIMEOUT_USEC / 1000.0);

    if (recv_sock >= 0) {
      // Receive loop: keep reading until we find the packet matching this exact
      // probe's destination port or timeout
      while (1) {
        clock_gettime(CLOCK_MONOTONIC, &now_time);
        double elapsed_ms = (now_time.tv_sec - start_time.tv_sec) * 1000.0 +
                            (now_time.tv_nsec - start_time.tv_nsec) / 1000000.0;
        double remaining_ms = total_timeout_ms - elapsed_ms;
        if (remaining_ms <= 0) {
          break; // Timeout for this hop
        }

        fd_set read_fds;
        FD_ZERO(&read_fds);
        FD_SET(recv_sock, &read_fds);

        struct timeval sel_tv;
        sel_tv.tv_sec = (time_t)(remaining_ms / 1000.0);
        sel_tv.tv_usec = (suseconds_t)(((long)remaining_ms % 1000) * 1000);

        int sel_res = select(recv_sock + 1, &read_fds, NULL, NULL, &sel_tv);
        if (sel_res <= 0 || !FD_ISSET(recv_sock, &read_fds)) {
          break; // Timeout
        }

        unsigned char recv_buf[1024];
        struct sockaddr_in reply_addr;
        socklen_t addr_len = sizeof(reply_addr);

        int n = (int)recvfrom(recv_sock, recv_buf, sizeof(recv_buf), 0,
                              (struct sockaddr *)&reply_addr, &addr_len);
        clock_gettime(CLOCK_MONOTONIC, &now_time);
        elapsed_ms = (now_time.tv_sec - start_time.tv_sec) * 1000.0 +
                     (now_time.tv_nsec - start_time.tv_nsec) / 1000000.0;

        if (n <= 0) {
          break;
        }

        struct icmp *icmp_reply = locate_icmp_header(recv_buf, n);
        if (icmp_reply != NULL) {
          if (icmp_reply->icmp_type == ICMP_TIMXCEED ||
              icmp_reply->icmp_type == ICMP_UNREACH) {
            // Extract embedded original IP and UDP header
            unsigned char *orig_payload = (unsigned char *)icmp_reply + 8;
            int orig_len = n - (int)(orig_payload - recv_buf);

            if (orig_len >= (int)sizeof(struct ip) + 4) {
              struct ip *orig_ip = (struct ip *)orig_payload;
              int orig_ip_len = orig_ip->ip_hl * 4;

              // Check if destination IP matches our target
              if (orig_ip->ip_dst.s_addr != dest_addr.sin_addr.s_addr) {
                continue; // Unrelated packet from another flow/target, keep
                          // waiting
              }

              if (orig_len >= orig_ip_len + 4) {
                unsigned char *orig_udp_hdr = orig_payload + orig_ip_len;
                uint16_t orig_dst_port =
                    (uint16_t)((orig_udp_hdr[2] << 8) | orig_udp_hdr[3]);

                if (orig_dst_port != expected_port && orig_dst_port != 0) {
                  continue; // Belongs to an earlier/different TTL probe,
                            // discard and keep waiting!
                }
              }
            }

            char sender_ip[INET_ADDRSTRLEN] = {0};
            inet_ntop(AF_INET, &(reply_addr.sin_addr), sender_ip,
                      sizeof(sender_ip));

            strncpy(hop.ip, sender_ip, sizeof(hop.ip) - 1);
            hop.ip[sizeof(hop.ip) - 1] = '\0';
            hop.ping = (int)elapsed_ms;
            resolve_domain(hop.ip, hop.domain, sizeof(hop.domain));

            if (reply_addr.sin_addr.s_addr == dest_addr.sin_addr.s_addr ||
                icmp_reply->icmp_type == ICMP_UNREACH) {
              is_destination_reached = 1;
            }
            break; // Successfully matched this hop's response!
          } else if (icmp_reply->icmp_type == ICMP_ECHOREPLY) {
            if (reply_addr.sin_addr.s_addr == dest_addr.sin_addr.s_addr) {
              char sender_ip[INET_ADDRSTRLEN] = {0};
              inet_ntop(AF_INET, &(reply_addr.sin_addr), sender_ip,
                        sizeof(sender_ip));
              strncpy(hop.ip, sender_ip, sizeof(hop.ip) - 1);
              hop.ip[sizeof(hop.ip) - 1] = '\0';
              hop.ping = (int)elapsed_ms;
              resolve_domain(hop.ip, hop.domain, sizeof(hop.domain));
              is_destination_reached = 1;
              break;
            }
          }
        }
      }
    }

    if (strcmp(hop.ip, "*") == 0) {
      consecutive_timeouts++;
    } else {
      consecutive_timeouts = 0;
    }

    result.hops[result.count++] = hop;

    if (is_destination_reached) {
      break;
    }

    // Stop if 5 consecutive hops timeout after at least one responded hop
    if (consecutive_timeouts >= 5 && result.count >= 6) {
      break;
    }
  }

  if (send_sock >= 0)
    close(send_sock);
  if (recv_sock >= 0)
    close(recv_sock);

  // If destination was not reached as the final hop, append it
  if (!is_destination_reached && dest_ip_str[0] != '\0') {
    int already_has_dest = 0;
    for (int k = 0; k < result.count; k++) {
      if (strcmp(result.hops[k].ip, dest_ip_str) == 0) {
        already_has_dest = 1;
        break;
      }
    }
    if (!already_has_dest && result.count < MAX_HOPS) {
      strncpy(result.hops[result.count].ip, dest_ip_str,
              sizeof(result.hops[result.count].ip) - 1);
      resolve_domain(result.hops[result.count].ip,
                     result.hops[result.count].domain,
                     sizeof(result.hops[result.count].domain));
      result.hops[result.count].ping = -1;
      result.count++;
    }
  }

  return result;
}

__attribute__((visibility("default"))) __attribute__((used)) char **
get_traceroute_array(const char *destination, int *hop_count) {
  TracerouteResult result = get_traceroute_data(destination);
  *hop_count = result.count;

  if (result.count == 0 || result.hops == NULL) {
    if (result.hops != NULL)
      free(result.hops);
    return NULL;
  }

  char **traceroute_array = (char **)malloc(result.count * sizeof(char *));
  if (traceroute_array == NULL) {
    free(result.hops);
    return NULL;
  }

  for (int i = 0; i < result.count; i++) {
    size_t buffer_size = 512;
    traceroute_array[i] = (char *)malloc(buffer_size);
    if (traceroute_array[i] == NULL) {
      for (int j = 0; j < i; j++)
        free(traceroute_array[j]);
      free(traceroute_array);
      free(result.hops);
      return NULL;
    }

    snprintf(traceroute_array[i], buffer_size,
             "{hop:%d, ip:%s, name:%s, ping:%d}", i + 1, result.hops[i].ip,
             result.hops[i].domain, result.hops[i].ping);
  }

  if (result.hops != NULL) {
    free(result.hops);
  }

  return traceroute_array;
}

__attribute__((visibility("default"))) __attribute__((used)) void
free_traceroute_array(char **array, int hop_count) {
  if (array == NULL)
    return;

  for (int i = 0; i < hop_count; i++) {
    if (array[i] != NULL) {
      free(array[i]);
    }
  }
  free(array);
}

// Internet Checksum for ICMP packets
static unsigned short checksum(void *b, int len) {
  unsigned short *buf = b;
  unsigned int sum = 0;
  unsigned short result;

  for (sum = 0; len > 1; len -= 2) {
    sum += *buf++;
  }
  if (len == 1) {
    sum += *(unsigned char *)buf;
  }
  sum = (sum >> 16) + (sum & 0xFFFF);
  sum += (sum >> 16);
  result = ~sum;
  return result;
}

__attribute__((visibility("default"))) __attribute__((used)) int
ping_host(const char *destination, int timeout_ms) {
  if (destination == NULL || destination[0] == '\0' ||
      strcmp(destination, "*") == 0 || strcmp(destination, "?") == 0) {
    return -1;
  }

  struct sockaddr_in dest_addr;
  memset(&dest_addr, 0, sizeof(dest_addr));
  dest_addr.sin_family = AF_INET;

  if (inet_pton(AF_INET, destination, &(dest_addr.sin_addr)) <= 0) {
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;

    if (getaddrinfo(destination, NULL, &hints, &res) != 0 || res == NULL) {
      if (res)
        freeaddrinfo(res);
      return -1;
    }
    memcpy(&dest_addr, res->ai_addr, sizeof(struct sockaddr_in));
    freeaddrinfo(res);
  }

  int sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
  if (sockfd < 0) {
    sockfd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
  }
  if (sockfd < 0)
    return -1;

  drain_socket(sockfd);

  struct icmp icmp_hdr;
  memset(&icmp_hdr, 0, sizeof(icmp_hdr));
  icmp_hdr.icmp_type = ICMP_ECHO;
  icmp_hdr.icmp_code = 0;
  icmp_hdr.icmp_id = (uint16_t)(rand() & 0xFFFF);
  icmp_hdr.icmp_seq = (uint16_t)(rand() & 0xFFFF);
  icmp_hdr.icmp_cksum = checksum(&icmp_hdr, sizeof(icmp_hdr));

  struct timespec start_time, now_time;
  clock_gettime(CLOCK_MONOTONIC, &start_time);

  if (sendto(sockfd, &icmp_hdr, sizeof(icmp_hdr), 0,
             (struct sockaddr *)&dest_addr, sizeof(dest_addr)) <= 0) {
    close(sockfd);
    return -1;
  }

  int timeout_limit = timeout_ms > 0 ? timeout_ms : 1000;
  struct timeval tv;
  tv.tv_sec = timeout_limit / 1000;
  tv.tv_usec = (timeout_limit % 1000) * 1000;
  setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

  int latency = -1;
  unsigned char recv_buf[1024];
  struct sockaddr_in reply_addr;
  socklen_t reply_len = sizeof(reply_addr);

  while (1) {
    int n = (int)recvfrom(sockfd, recv_buf, sizeof(recv_buf), 0,
                          (struct sockaddr *)&reply_addr, &reply_len);
    clock_gettime(CLOCK_MONOTONIC, &now_time);

    if (n <= 0)
      break;

    struct icmp *reply = locate_icmp_header(recv_buf, n);
    if (reply != NULL) {
      if (reply->icmp_type == ICMP_ECHOREPLY) {
        if (reply_addr.sin_addr.s_addr == dest_addr.sin_addr.s_addr) {
          double elapsed = (now_time.tv_sec - start_time.tv_sec) * 1000.0 +
                           (now_time.tv_nsec - start_time.tv_nsec) / 1000000.0;
          latency = (int)elapsed;
          break;
        }
      }
    }

    double total_elapsed = (now_time.tv_sec - start_time.tv_sec) * 1000.0 +
                           (now_time.tv_nsec - start_time.tv_nsec) / 1000000.0;
    if (total_elapsed >= timeout_limit)
      break;
  }

  close(sockfd);
  return latency;
}

__attribute__((visibility("default"))) __attribute__((used)) void
ping_all_hops(const char *target_destination, const char **hop_ips, int count, int timeout_ms, int *results) {
  if (target_destination == NULL || target_destination[0] == '\0' || count <= 0 || results == NULL)
    return;

  for (int i = 0; i < count; i++) {
    results[i] = -1;
  }

  struct sockaddr_in dest_addr;
  struct addrinfo hints, *res = NULL;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_DGRAM;

  if (getaddrinfo(target_destination, NULL, &hints, &res) != 0 || res == NULL) {
    if (res) freeaddrinfo(res);
    return;
  }
  memcpy(&dest_addr, res->ai_addr, sizeof(struct sockaddr_in));
  freeaddrinfo(res);

  int send_sock = socket(AF_INET, SOCK_DGRAM, 0);
  if (send_sock < 0) return;

  int recv_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
  if (recv_sock < 0) {
    recv_sock = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
  }
  if (recv_sock < 0) {
    close(send_sock);
    return;
  }

  drain_socket(recv_sock);

  struct timespec hop_start_time[MAX_HOPS];
  struct timespec global_start_time, now_time;
  clock_gettime(CLOCK_MONOTONIC, &global_start_time);

  // Send incremental TTL probes for all hops with individual timestamps and 10ms stagger
  for (int i = 0; i < count && i < MAX_HOPS; i++) {
    int ttl = i + 1;
    if (setsockopt(send_sock, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
      continue;
    }
    uint16_t port = (uint16_t)(BASE_PORT + ttl);
    dest_addr.sin_port = htons(port);
    char payload[32];
    snprintf(payload, sizeof(payload), "PR_%d", ttl);
    clock_gettime(CLOCK_MONOTONIC, &hop_start_time[i]);
    sendto(send_sock, payload, strlen(payload), 0,
           (struct sockaddr *)&dest_addr, sizeof(dest_addr));
    usleep(10000); // 10ms stagger prevents wireless NIC packet batching
  }

  int timeout_limit = timeout_ms > 0 ? timeout_ms : 800;
  int received_count = 0;

  while (received_count < count) {
    clock_gettime(CLOCK_MONOTONIC, &now_time);
    double elapsed_total = (now_time.tv_sec - global_start_time.tv_sec) * 1000.0 +
                           (now_time.tv_nsec - global_start_time.tv_nsec) / 1000000.0;
    double remaining = timeout_limit - elapsed_total;
    if (remaining <= 0) break;

    fd_set read_fds;
    FD_ZERO(&read_fds);
    FD_SET(recv_sock, &read_fds);

    struct timeval tv;
    tv.tv_sec = (time_t)(remaining / 1000.0);
    tv.tv_usec = (suseconds_t)(((long)remaining % 1000) * 1000);

    int sel = select(recv_sock + 1, &read_fds, NULL, NULL, &tv);
    if (sel <= 0 || !FD_ISSET(recv_sock, &read_fds)) break;

    unsigned char recv_buf[1024];
    struct sockaddr_in reply_addr;
    socklen_t addr_len = sizeof(reply_addr);

    int n = (int)recvfrom(recv_sock, recv_buf, sizeof(recv_buf), 0,
                          (struct sockaddr *)&reply_addr, &addr_len);
    clock_gettime(CLOCK_MONOTONIC, &now_time);

    if (n <= 0) break;

    struct icmp *reply = locate_icmp_header(recv_buf, n);
    if (reply != NULL) {
      if (reply->icmp_type == ICMP_TIMXCEED || reply->icmp_type == ICMP_UNREACH) {
        unsigned char *orig_payload = (unsigned char *)reply + 8;
        int orig_len = n - (int)(orig_payload - recv_buf);

        if (orig_len >= (int)sizeof(struct ip) + 4) {
          struct ip *orig_ip = (struct ip *)orig_payload;
          int orig_ip_len = orig_ip->ip_hl * 4;

          if (orig_ip_len >= 20 && orig_len >= orig_ip_len + 4) {
            if (orig_ip->ip_dst.s_addr == dest_addr.sin_addr.s_addr) {
              unsigned char *orig_udp = orig_payload + orig_ip_len;
              uint16_t orig_dst_port = (uint16_t)((orig_udp[2] << 8) | orig_udp[3]);
              int hop_idx = (int)orig_dst_port - BASE_PORT - 1;

              if (hop_idx >= 0 && hop_idx < count && results[hop_idx] == -1) {
                double elapsed = (now_time.tv_sec - hop_start_time[hop_idx].tv_sec) * 1000.0 +
                                 (now_time.tv_nsec - hop_start_time[hop_idx].tv_nsec) / 1000000.0;
                results[hop_idx] = (int)(elapsed + 0.5);
                received_count++;
              }
            }
          }
        }
      } else if (reply->icmp_type == ICMP_ECHOREPLY) {
        int last_idx = count - 1;
        if (reply_addr.sin_addr.s_addr == dest_addr.sin_addr.s_addr && results[last_idx] == -1) {
          double elapsed = (now_time.tv_sec - hop_start_time[last_idx].tv_sec) * 1000.0 +
                           (now_time.tv_nsec - hop_start_time[last_idx].tv_nsec) / 1000000.0;
          results[last_idx] = (int)(elapsed + 0.5);
          received_count++;
        }
      }
    }
  }

  close(send_sock);
  close(recv_sock);
}
