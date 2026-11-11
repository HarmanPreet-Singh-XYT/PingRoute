/*
 * macOS backend: libproc. Lists every process, and for each one its open
 * socket file descriptors. Needs no entitlements or root; sandboxed apps
 * cannot see other processes, so the app's sandbox must stay disabled.
 */
#include "../../native/pr_sockets.h"

#include <arpa/inet.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <netinet/tcp_fsm.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/socket.h>

static int32_t translate_state(int tsi) {
    switch (tsi) {
        case TSI_S_ESTABLISHED:  return PR_STATE_ESTABLISHED;
        case TSI_S_SYN_SENT:     return PR_STATE_SYN_SENT;
        case TSI_S_SYN_RECEIVED: return PR_STATE_SYN_RECV;
        case TSI_S_FIN_WAIT_1:   return PR_STATE_FIN_WAIT1;
        case TSI_S_FIN_WAIT_2:   return PR_STATE_FIN_WAIT2;
        case TSI_S_TIME_WAIT:    return PR_STATE_TIME_WAIT;
        case TSI_S_CLOSED:       return PR_STATE_CLOSE;
        case TSI_S__CLOSE_WAIT:   return PR_STATE_CLOSE_WAIT;
        case TSI_S_LAST_ACK:     return PR_STATE_LAST_ACK;
        case TSI_S_LISTEN:       return PR_STATE_LISTEN;
        case TSI_S_CLOSING:      return PR_STATE_CLOSING;
        default:                 return PR_STATE_NONE;
    }
}

/* Returns every pid, growing the buffer until the list fits. The size query
 * form of proc_listpids is not reliable across macOS versions, so we never
 * depend on it. Caller frees. Returns NULL on failure. */
static pid_t *list_all_pids(int *count_out) {
    int cap = 4096; /* pids */
    for (;;) {
        pid_t *pids = malloc((size_t)cap * sizeof(pid_t));
        if (!pids) return NULL;
        int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, cap * (int)sizeof(pid_t));
        if (bytes <= 0) {
            free(pids);
            return NULL;
        }
        /* A completely full buffer may have been truncated: retry larger. */
        if (bytes < (cap - 8) * (int)sizeof(pid_t)) {
            *count_out = bytes / (int)sizeof(pid_t);
            return pids;
        }
        free(pids);
        cap *= 2;
    }
}

/* Appends to a growable array, doubling capacity. Returns 0 on success. */
static int grow(void **buf, int32_t *cap, int32_t count, size_t elem) {
    if (count < *cap) return 0;
    int32_t ncap = *cap ? *cap * 2 : 256;
    void *n = realloc(*buf, (size_t)ncap * elem);
    if (!n) return -1;
    *buf = n;
    *cap = ncap;
    return 0;
}

static int fill_endpoint(const struct in_sockinfo *in, pr_connection *c) {
    if (in->insi_vflag & INI_IPV4) {
        c->family = PR_FAMILY_V4;
        memcpy(c->local_addr, &in->insi_laddr.ina_46.i46a_addr4, 4);
        memcpy(c->remote_addr, &in->insi_faddr.ina_46.i46a_addr4, 4);
    } else if (in->insi_vflag & INI_IPV6) {
        c->family = PR_FAMILY_V6;
        memcpy(c->local_addr, &in->insi_laddr.ina_6, 16);
        memcpy(c->remote_addr, &in->insi_faddr.ina_6, 16);
    } else {
        return -1;
    }
    c->local_port = ntohs((uint16_t)in->insi_lport);
    c->remote_port = ntohs((uint16_t)in->insi_fport);
    return 0;
}

int32_t pr_list_connections(pr_connection **out) {
    *out = NULL;

    int npids = 0;
    pid_t *pids = list_all_pids(&npids);
    if (!pids) return -1;

    pr_connection *list = NULL;
    int32_t count = 0, cap = 0;
    struct proc_fdinfo *fds = NULL;
    int fds_cap = 0;

    for (int i = 0; i < npids; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        int need = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (need <= 0) continue; /* gone, or not ours to inspect */
        if (need > fds_cap) {
            struct proc_fdinfo *n = realloc(fds, (size_t)need);
            if (!n) break;
            fds = n;
            fds_cap = need;
        }
        int used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, fds_cap);
        if (used <= 0) continue;
        int nfds = used / (int)sizeof(struct proc_fdinfo);

        for (int f = 0; f < nfds; f++) {
            if (fds[f].proc_fdtype != PROX_FDTYPE_SOCKET) continue;

            struct socket_fdinfo si;
            int r = proc_pidfdinfo(pid, fds[f].proc_fd, PROC_PIDFDSOCKETINFO,
                                   &si, (int)sizeof(si));
            if (r < (int)sizeof(si)) continue;

            const struct socket_info *s = &si.psi;
            pr_connection c;
            memset(&c, 0, sizeof(c));
            c.pid = pid;
            c.bytes_in = PR_BYTES_UNKNOWN;
            c.bytes_out = PR_BYTES_UNKNOWN;

            if (s->soi_kind == SOCKINFO_TCP) {
                const struct in_sockinfo *in = &s->soi_proto.pri_tcp.tcpsi_ini;
                if (fill_endpoint(in, &c) != 0) continue;
                c.protocol = PR_PROTO_TCP;
                c.state = translate_state(s->soi_proto.pri_tcp.tcpsi_state);
            } else if (s->soi_kind == SOCKINFO_IN && s->soi_protocol == IPPROTO_UDP) {
                const struct in_sockinfo *in = &s->soi_proto.pri_in;
                if (fill_endpoint(in, &c) != 0) continue;
                if (c.remote_port == 0) continue; /* unconnected UDP */
                c.protocol = PR_PROTO_UDP;
                c.state = PR_STATE_NONE;
            } else {
                continue;
            }

            if (grow((void **)&list, &cap, count, sizeof(pr_connection)) != 0) {
                free(fds);
                free(pids);
                free(list);
                return -1;
            }
            list[count++] = c;
        }
    }

    free(fds);
    free(pids);
    if (count == 0) {
        free(list);
        return 0;
    }
    *out = list;
    return count;
}

int32_t pr_list_processes(pr_process **out) {
    *out = NULL;

    int npids = 0;
    pid_t *pids = list_all_pids(&npids);
    if (!pids) return -1;

    /* proc_taskinfo times are in mach absolute time units. */
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);

    pr_process *list = NULL;
    int32_t count = 0, cap = 0;

    for (int i = 0; i < npids; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        struct proc_bsdinfo bsd;
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, (int)sizeof(bsd)) <
            (int)sizeof(bsd))
            continue;

        pr_process p;
        memset(&p, 0, sizeof(p));
        p.pid = pid;
        p.ppid = (int32_t)bsd.pbi_ppid;
        p.start_unix_ms = (int64_t)bsd.pbi_start_tvsec * 1000 +
                          (int64_t)bsd.pbi_start_tvusec / 1000;
        strncpy(p.name, bsd.pbi_name[0] ? bsd.pbi_name : bsd.pbi_comm,
                sizeof(p.name) - 1);
        proc_pidpath(pid, p.path, sizeof(p.path));

        struct proc_taskinfo ti;
        if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, (int)sizeof(ti)) ==
            (int)sizeof(ti)) {
            p.rss_kb = ti.pti_resident_size / 1024;
            uint64_t abs = ti.pti_total_user + ti.pti_total_system;
            p.cpu_time_ns = abs * tb.numer / tb.denom;
        }

        if (grow((void **)&list, &cap, count, sizeof(pr_process)) != 0) {
            free(pids);
            free(list);
            return -1;
        }
        list[count++] = p;
    }

    free(pids);
    if (count == 0) {
        free(list);
        return 0;
    }
    *out = list;
    return count;
}

void pr_free(void *p) { free(p); }

uint32_t pr_capabilities(void) {
    /* Byte counters need private frameworks on macOS, so they are not
     * offered here; the Dart side supplements them from nettop. */
    return PR_CAP_PROCESS_CPU | PR_CAP_UDP_FLOWS;
}

int32_t pr_connection_size(void) { return (int32_t)sizeof(pr_connection); }
int32_t pr_process_size(void) { return (int32_t)sizeof(pr_process); }
