/*
 * Linux backend.
 *
 * Sockets come from the kernel's NETLINK_SOCK_DIAG interface (the same one
 * `ss` uses), which also returns TCP byte counters through tcp_info. The
 * owning process of each socket is found by matching socket inodes against
 * /proc/<pid>/fd links. No privileges are needed; as with `ss -p`, a
 * regular user can only resolve the owners of their own processes' sockets
 * (other sockets are still listed with pid 0 and skipped by the caller).
 */
#define _GNU_SOURCE
#include "../../native/pr_sockets.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/inet_diag.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/sock_diag.h>
#include <linux/tcp.h>
#include <netinet/in.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

/* ---- growable arrays -------------------------------------------------- */

static int grow(void **buf, int32_t *cap, int32_t count, size_t elem) {
    if (count < *cap) return 0;
    int32_t ncap = *cap ? *cap * 2 : 256;
    void *n = realloc(*buf, (size_t)ncap * elem);
    if (!n) return -1;
    *buf = n;
    *cap = ncap;
    return 0;
}

/* ---- inode -> pid ------------------------------------------------------ */

typedef struct {
    uint32_t inode;
    int32_t pid;
} inode_pid;

static int cmp_inode_pid(const void *a, const void *b) {
    const inode_pid *x = a, *y = b;
    if (x->inode != y->inode) return x->inode < y->inode ? -1 : 1;
    return x->pid < y->pid ? -1 : (x->pid > y->pid);
}

static int is_number(const char *s) {
    if (!*s) return 0;
    for (; *s; s++)
        if (!isdigit((unsigned char)*s)) return 0;
    return 1;
}

/* Builds a sorted table of every socket inode we can see. */
static inode_pid *build_inode_table(int32_t *count_out) {
    DIR *proc = opendir("/proc");
    if (!proc) return NULL;

    inode_pid *table = NULL;
    int32_t count = 0, cap = 0;
    struct dirent *de;
    while ((de = readdir(proc))) {
        if (!is_number(de->d_name)) continue;
        int pid = atoi(de->d_name);

        char fddir[64];
        snprintf(fddir, sizeof(fddir), "/proc/%d/fd", pid);
        DIR *fds = opendir(fddir);
        if (!fds) continue; /* not ours, or exited */
        int dfd = dirfd(fds);

        struct dirent *fe;
        while ((fe = readdir(fds))) {
            if (fe->d_name[0] == '.') continue;
            char link[64];
            ssize_t n = readlinkat(dfd, fe->d_name, link, sizeof(link) - 1);
            if (n <= 0) continue;
            link[n] = '\0';
            unsigned long inode;
            if (sscanf(link, "socket:[%lu]", &inode) != 1) continue;
            if (grow((void **)&table, &cap, count, sizeof(inode_pid)) != 0) {
                closedir(fds);
                closedir(proc);
                free(table);
                return NULL;
            }
            table[count].inode = (uint32_t)inode;
            table[count].pid = pid;
            count++;
        }
        closedir(fds);
    }
    closedir(proc);

    if (count > 1) qsort(table, (size_t)count, sizeof(inode_pid), cmp_inode_pid);
    *count_out = count;
    return table;
}

static int32_t pid_for_inode(const inode_pid *table, int32_t n, uint32_t inode) {
    int32_t lo = 0, hi = n - 1;
    while (lo <= hi) {
        int32_t mid = lo + (hi - lo) / 2;
        if (table[mid].inode == inode) return table[mid].pid;
        if (table[mid].inode < inode) lo = mid + 1; else hi = mid - 1;
    }
    return 0;
}

/* ---- sock_diag --------------------------------------------------------- */

typedef struct {
    pr_connection *list;
    uint32_t *inodes; /* parallel to list */
    int32_t count;
    int32_t cap;
} conn_acc;

/* Linux kernel TCP state numbers already match PR_STATE_*. */
static int accumulate(conn_acc *acc, const struct inet_diag_msg *m,
                      const struct nlmsghdr *nlh, int proto) {
    if (m->idiag_family != AF_INET && m->idiag_family != AF_INET6) return 0;
    if (proto == IPPROTO_TCP && m->idiag_state == PR_STATE_LISTEN) return 0;

    uint16_t rport = ntohs(m->id.idiag_dport);
    if (proto == IPPROTO_UDP && rport == 0) return 0; /* unconnected */

    pr_connection c;
    memset(&c, 0, sizeof(c));
    c.protocol = proto == IPPROTO_TCP ? PR_PROTO_TCP : PR_PROTO_UDP;
    c.family = m->idiag_family == AF_INET ? PR_FAMILY_V4 : PR_FAMILY_V6;
    c.state = proto == IPPROTO_TCP ? m->idiag_state : PR_STATE_NONE;
    size_t alen = m->idiag_family == AF_INET ? 4 : 16;
    memcpy(c.local_addr, m->id.idiag_src, alen);
    memcpy(c.remote_addr, m->id.idiag_dst, alen);
    c.local_port = ntohs(m->id.idiag_sport);
    c.remote_port = rport;
    c.bytes_in = PR_BYTES_UNKNOWN;
    c.bytes_out = PR_BYTES_UNKNOWN;

    int attr_len = (int)(nlh->nlmsg_len - NLMSG_LENGTH(sizeof(*m)));
    for (const struct rtattr *a = (const struct rtattr *)(m + 1);
         RTA_OK(a, attr_len); a = RTA_NEXT(a, attr_len)) {
        if (a->rta_type != INET_DIAG_INFO) continue;
        size_t plen = RTA_PAYLOAD(a);
        const struct tcp_info *ti = RTA_DATA(a);
        /* Older kernels send a shorter tcp_info without byte counters. */
        if (plen >= offsetof(struct tcp_info, tcpi_bytes_received) + sizeof(uint64_t)) {
            c.bytes_in = ti->tcpi_bytes_received;
            c.bytes_out = ti->tcpi_bytes_acked;
        }
    }

    if (acc->count >= acc->cap) {
        int32_t ncap = acc->cap ? acc->cap * 2 : 256;
        pr_connection *nl = realloc(acc->list, (size_t)ncap * sizeof(*nl));
        if (!nl) return -1;
        acc->list = nl;
        uint32_t *ni = realloc(acc->inodes, (size_t)ncap * sizeof(*ni));
        if (!ni) return -1;
        acc->inodes = ni;
        acc->cap = ncap;
    }
    acc->list[acc->count] = c;
    acc->inodes[acc->count] = m->idiag_inode;
    acc->count++;
    return 0;
}

/* Dumps one (family, protocol) table. Returns 0 on success. */
static int dump(int fd, conn_acc *acc, uint8_t family, uint8_t proto) {
    struct {
        struct nlmsghdr nlh;
        struct inet_diag_req_v2 req;
    } msg;
    memset(&msg, 0, sizeof(msg));
    msg.nlh.nlmsg_len = sizeof(msg);
    msg.nlh.nlmsg_type = SOCK_DIAG_BY_FAMILY;
    msg.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    msg.req.sdiag_family = family;
    msg.req.sdiag_protocol = proto;
    msg.req.idiag_ext = 1u << (INET_DIAG_INFO - 1);
    msg.req.idiag_states = ~0u;

    struct sockaddr_nl kernel;
    memset(&kernel, 0, sizeof(kernel));
    kernel.nl_family = AF_NETLINK;
    if (sendto(fd, &msg, sizeof(msg), 0, (struct sockaddr *)&kernel, sizeof(kernel)) < 0)
        return -1;

    /* Heap, not static: callers may run on several isolates at once. */
    const size_t buf_size = 1 << 16;
    char *buf = malloc(buf_size);
    if (!buf) return -1;
    int result = -1;
    for (;;) {
        ssize_t n = recv(fd, buf, buf_size, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (n == 0) break;
        int done = 0, failed = 0;
        for (const struct nlmsghdr *nlh = (const struct nlmsghdr *)buf;
             NLMSG_OK(nlh, (size_t)n); nlh = NLMSG_NEXT(nlh, n)) {
            if (nlh->nlmsg_type == NLMSG_DONE) { done = 1; break; }
            if (nlh->nlmsg_type == NLMSG_ERROR) { failed = 1; break; }
            if (nlh->nlmsg_type != SOCK_DIAG_BY_FAMILY) continue;
            if (accumulate(acc, NLMSG_DATA(nlh), nlh, proto) != 0) {
                failed = 1;
                break;
            }
        }
        if (failed) break;
        if (done) { result = 0; break; }
    }
    free(buf);
    return result;
}

int32_t pr_list_connections(pr_connection **out) {
    *out = NULL;

    int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_SOCK_DIAG);
    if (fd < 0) return -1;

    conn_acc acc;
    memset(&acc, 0, sizeof(acc));
    int rc = 0;
    rc |= dump(fd, &acc, AF_INET, IPPROTO_TCP);
    rc |= dump(fd, &acc, AF_INET6, IPPROTO_TCP);
    /* UDP failing (e.g. module not loaded) is not fatal. */
    dump(fd, &acc, AF_INET, IPPROTO_UDP);
    dump(fd, &acc, AF_INET6, IPPROTO_UDP);
    close(fd);

    if (rc != 0 && acc.count == 0) {
        free(acc.list);
        free(acc.inodes);
        return -1;
    }

    int32_t ntable = 0;
    inode_pid *table = build_inode_table(&ntable);

    /* Keep only sockets whose owner we could resolve. */
    int32_t kept = 0;
    for (int32_t i = 0; i < acc.count; i++) {
        int32_t pid = table ? pid_for_inode(table, ntable, acc.inodes[i]) : 0;
        if (pid <= 0) continue;
        acc.list[i].pid = pid;
        acc.list[kept++] = acc.list[i];
    }
    free(table);
    free(acc.inodes);

    if (kept == 0) {
        free(acc.list);
        return 0;
    }
    *out = acc.list;
    return kept;
}

/* ---- processes --------------------------------------------------------- */

static int64_t boot_time_ms(void) {
    FILE *f = fopen("/proc/stat", "r");
    if (!f) return 0;
    char line[256];
    long long btime = 0;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "btime %lld", &btime) == 1) break;
    }
    fclose(f);
    return btime * 1000;
}

int32_t pr_list_processes(pr_process **out) {
    *out = NULL;
    DIR *proc = opendir("/proc");
    if (!proc) return -1;

    long clk = sysconf(_SC_CLK_TCK);
    if (clk <= 0) clk = 100;
    long page_kb = sysconf(_SC_PAGESIZE) / 1024;
    if (page_kb <= 0) page_kb = 4;
    int64_t boot_ms = boot_time_ms();

    pr_process *list = NULL;
    int32_t count = 0, cap = 0;
    struct dirent *de;
    while ((de = readdir(proc))) {
        if (!is_number(de->d_name)) continue;
        int pid = atoi(de->d_name);

        char path[64];
        snprintf(path, sizeof(path), "/proc/%d/stat", pid);
        FILE *f = fopen(path, "r");
        if (!f) continue;
        char line[1024];
        size_t len = fread(line, 1, sizeof(line) - 1, f);
        fclose(f);
        line[len] = '\0';

        /* "pid (comm) state ..." where comm may contain spaces and ')'. */
        char *open = strchr(line, '(');
        char *close = strrchr(line, ')');
        if (!open || !close || close < open) continue;

        pr_process p;
        memset(&p, 0, sizeof(p));
        p.pid = pid;
        size_t name_len = (size_t)(close - open - 1);
        if (name_len >= sizeof(p.name)) name_len = sizeof(p.name) - 1;
        memcpy(p.name, open + 1, name_len);

        char state;
        int ppid;
        unsigned long utime, stime;
        unsigned long long starttime;
        long rss;
        int got = sscanf(close + 2,
                         "%c %d %*d %*d %*d %*d %*u %*u %*u %*u %*u "
                         "%lu %lu %*d %*d %*d %*d %*d %*d %llu %*u %ld",
                         &state, &ppid, &utime, &stime, &starttime, &rss);
        if (got != 6) continue;

        p.ppid = ppid;
        p.cpu_time_ns = (uint64_t)(utime + stime) * 1000000000ull / (uint64_t)clk;
        p.start_unix_ms = boot_ms + (int64_t)(starttime * 1000ull / (uint64_t)clk);
        p.rss_kb = rss > 0 ? (uint64_t)rss * (uint64_t)page_kb : 0;

        snprintf(path, sizeof(path), "/proc/%d/exe", pid);
        ssize_t n = readlink(path, p.path, sizeof(p.path) - 1);
        if (n > 0) {
            p.path[n] = '\0';
            /* A replaced binary reads "/path/app (deleted)". */
            static const char deleted[] = " (deleted)";
            size_t dl = sizeof(deleted) - 1;
            if ((size_t)n > dl && strcmp(p.path + n - dl, deleted) == 0)
                p.path[n - dl] = '\0';
        } else {
            p.path[0] = '\0';
        }

        if (grow((void **)&list, &cap, count, sizeof(pr_process)) != 0) {
            closedir(proc);
            free(list);
            return -1;
        }
        list[count++] = p;
    }
    closedir(proc);

    if (count == 0) {
        free(list);
        return 0;
    }
    *out = list;
    return count;
}

void pr_free(void *p) { free(p); }

uint32_t pr_capabilities(void) {
    return PR_CAP_CONNECTION_BYTES | PR_CAP_PROCESS_CPU | PR_CAP_UDP_FLOWS;
}

int32_t pr_connection_size(void) { return (int32_t)sizeof(pr_connection); }
int32_t pr_process_size(void) { return (int32_t)sizeof(pr_process); }
