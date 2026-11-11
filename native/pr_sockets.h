#ifndef PR_SOCKETS_H
#define PR_SOCKETS_H

/*
 * PingRoute socket/process inventory.
 *
 * One C API, three implementations (libproc on macOS, netlink + /proc on
 * Linux, iphlpapi + ToolHelp on Windows). Everything returned is a plain
 * snapshot: the caller copies what it needs and releases the arrays with
 * pr_free().
 *
 * No privileges are required. Like lsof/ss/netstat, an unprivileged caller
 * only sees other users' sockets and processes where the OS allows it.
 */

#include <stdint.h>

#ifdef _WIN32
#define PR_API __declspec(dllexport)
#else
#define PR_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define PR_PROTO_TCP 6
#define PR_PROTO_UDP 17

#define PR_FAMILY_V4 4
#define PR_FAMILY_V6 6

/* TCP states, numbered like the Linux kernel (values are the same on every
 * platform; each backend translates its own numbering). */
#define PR_STATE_NONE        0
#define PR_STATE_ESTABLISHED 1
#define PR_STATE_SYN_SENT    2
#define PR_STATE_SYN_RECV    3
#define PR_STATE_FIN_WAIT1   4
#define PR_STATE_FIN_WAIT2   5
#define PR_STATE_TIME_WAIT   6
#define PR_STATE_CLOSE       7
#define PR_STATE_CLOSE_WAIT  8
#define PR_STATE_LAST_ACK    9
#define PR_STATE_LISTEN      10
#define PR_STATE_CLOSING     11

/* Value of bytes_in / bytes_out when the platform cannot report them. */
#define PR_BYTES_UNKNOWN ((uint64_t)0xFFFFFFFFFFFFFFFFULL)

/* pr_capabilities() bits. */
#define PR_CAP_CONNECTION_BYTES 0x1u /* per-connection byte counters */
#define PR_CAP_PROCESS_CPU      0x2u /* cumulative cpu time per process */
#define PR_CAP_UDP_FLOWS        0x4u /* connected UDP sockets are listed */

typedef struct pr_connection {
    int32_t pid;
    int32_t protocol; /* PR_PROTO_* */
    int32_t family;   /* PR_FAMILY_* */
    int32_t state;    /* PR_STATE_*; PR_STATE_NONE for UDP */
    uint8_t local_addr[16];  /* network order; first 4 bytes for IPv4 */
    uint8_t remote_addr[16];
    uint16_t local_port;     /* host order */
    uint16_t remote_port;    /* host order */
    uint32_t reserved;
    uint64_t bytes_in;
    uint64_t bytes_out;
} pr_connection;

typedef struct pr_process {
    int32_t pid;
    int32_t ppid;
    uint64_t rss_kb;
    uint64_t cpu_time_ns;     /* cumulative user+system; 0 if unknown */
    int64_t start_unix_ms;    /* 0 if unknown */
    char name[128];           /* UTF-8, NUL terminated */
    char path[1024];          /* UTF-8 executable path, may be empty */
} pr_process;

/* Allocates *out (release with pr_free). Returns the element count, or -1
 * on failure (*out is then NULL). A count of 0 also sets *out to NULL. */
PR_API int32_t pr_list_connections(pr_connection **out);
PR_API int32_t pr_list_processes(pr_process **out);

PR_API void pr_free(void *p);

PR_API uint32_t pr_capabilities(void);

/* Sizes of the structs above, so a binding can verify its own layout. */
PR_API int32_t pr_connection_size(void);
PR_API int32_t pr_process_size(void);

#ifdef __cplusplus
}
#endif

#endif /* PR_SOCKETS_H */
