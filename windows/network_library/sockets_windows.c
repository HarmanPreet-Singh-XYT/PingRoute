/*
 * Windows backend: iphlpapi for sockets, ToolHelp + psapi for processes.
 *
 * GetExtendedTcpTable / GetExtendedUdpTable need no elevation. Per-connection
 * byte counters would need ETW or elevated EStats, so they are reported as
 * unknown (PR_CAP_CONNECTION_BYTES is not advertised).
 */
#define WIN32_LEAN_AND_MEAN
#define _WINSOCK_DEPRECATED_NO_WARNINGS
#include "../../native/pr_sockets.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "psapi.lib")

static int grow_conn(pr_connection **list, int32_t *cap, int32_t count) {
    if (count < *cap) return 0;
    int32_t ncap = *cap ? *cap * 2 : 256;
    pr_connection *n = realloc(*list, (size_t)ncap * sizeof(**list));
    if (!n) return -1;
    *list = n;
    *cap = ncap;
    return 0;
}

/* Fetches an iphlpapi table, retrying while it grows between calls. */
static void *fetch_table(ULONG family, int tcp) {
    ULONG size = 32 * 1024;
    for (int attempt = 0; attempt < 8; attempt++) {
        void *buf = malloc(size);
        if (!buf) return NULL;
        DWORD rc = tcp
            ? GetExtendedTcpTable(buf, &size, FALSE, family, TCP_TABLE_OWNER_PID_ALL, 0)
            : GetExtendedUdpTable(buf, &size, FALSE, family, UDP_TABLE_OWNER_PID, 0);
        if (rc == NO_ERROR) return buf;
        free(buf);
        if (rc != ERROR_INSUFFICIENT_BUFFER) return NULL;
        size += size / 4 + 4096; /* headroom: the table can grow */
    }
    return NULL;
}

/* MIB_TCP_STATE_* -> PR_STATE_* */
static int32_t translate_state(DWORD s) {
    switch (s) {
    case MIB_TCP_STATE_CLOSED:     return PR_STATE_CLOSE;
    case MIB_TCP_STATE_LISTEN:     return PR_STATE_LISTEN;
    case MIB_TCP_STATE_SYN_SENT:   return PR_STATE_SYN_SENT;
    case MIB_TCP_STATE_SYN_RCVD:   return PR_STATE_SYN_RECV;
    case MIB_TCP_STATE_ESTAB:      return PR_STATE_ESTABLISHED;
    case MIB_TCP_STATE_FIN_WAIT1:  return PR_STATE_FIN_WAIT1;
    case MIB_TCP_STATE_FIN_WAIT2:  return PR_STATE_FIN_WAIT2;
    case MIB_TCP_STATE_CLOSE_WAIT: return PR_STATE_CLOSE_WAIT;
    case MIB_TCP_STATE_CLOSING:    return PR_STATE_CLOSING;
    case MIB_TCP_STATE_LAST_ACK:   return PR_STATE_LAST_ACK;
    case MIB_TCP_STATE_TIME_WAIT:  return PR_STATE_TIME_WAIT;
    default:                       return PR_STATE_NONE;
    }
}

/* Ports in the tables are network order stored in the low 16 bits. */
static uint16_t port_of(DWORD p) { return ntohs((u_short)(p & 0xFFFF)); }

static int add_tcp4(pr_connection **list, int32_t *cap, int32_t *count) {
    MIB_TCPTABLE_OWNER_PID *t = fetch_table(AF_INET, 1);
    if (!t) return -1;
    for (DWORD i = 0; i < t->dwNumEntries; i++) {
        const MIB_TCPROW_OWNER_PID *r = &t->table[i];
        if (r->dwState == MIB_TCP_STATE_LISTEN || r->dwOwningPid == 0) continue;
        if (grow_conn(list, cap, *count) != 0) { free(t); return -1; }
        pr_connection *c = &(*list)[(*count)++];
        memset(c, 0, sizeof(*c));
        c->pid = (int32_t)r->dwOwningPid;
        c->protocol = PR_PROTO_TCP;
        c->family = PR_FAMILY_V4;
        c->state = translate_state(r->dwState);
        memcpy(c->local_addr, &r->dwLocalAddr, 4);
        memcpy(c->remote_addr, &r->dwRemoteAddr, 4);
        c->local_port = port_of(r->dwLocalPort);
        c->remote_port = port_of(r->dwRemotePort);
        c->bytes_in = c->bytes_out = PR_BYTES_UNKNOWN;
    }
    free(t);
    return 0;
}

static int add_tcp6(pr_connection **list, int32_t *cap, int32_t *count) {
    MIB_TCP6TABLE_OWNER_PID *t = fetch_table(AF_INET6, 1);
    if (!t) return -1;
    for (DWORD i = 0; i < t->dwNumEntries; i++) {
        const MIB_TCP6ROW_OWNER_PID *r = &t->table[i];
        if (r->dwState == MIB_TCP_STATE_LISTEN || r->dwOwningPid == 0) continue;
        if (grow_conn(list, cap, *count) != 0) { free(t); return -1; }
        pr_connection *c = &(*list)[(*count)++];
        memset(c, 0, sizeof(*c));
        c->pid = (int32_t)r->dwOwningPid;
        c->protocol = PR_PROTO_TCP;
        c->family = PR_FAMILY_V6;
        c->state = translate_state(r->dwState);
        memcpy(c->local_addr, r->ucLocalAddr, 16);
        memcpy(c->remote_addr, r->ucRemoteAddr, 16);
        c->local_port = port_of(r->dwLocalPort);
        c->remote_port = port_of(r->dwRemotePort);
        c->bytes_in = c->bytes_out = PR_BYTES_UNKNOWN;
    }
    free(t);
    return 0;
}

/* The Windows UDP tables carry no remote endpoint, so there are no
 * "connected UDP" flows to report here (PR_CAP_UDP_FLOWS is not set). */

int32_t pr_list_connections(pr_connection **out) {
    *out = NULL;
    pr_connection *list = NULL;
    int32_t cap = 0, count = 0;
    int e4 = add_tcp4(&list, &cap, &count);
    int e6 = add_tcp6(&list, &cap, &count);
    if (e4 != 0 && e6 != 0) {
        free(list);
        return -1;
    }
    if (count == 0) {
        free(list);
        return 0;
    }
    *out = list;
    return count;
}

/* ---- processes --------------------------------------------------------- */

static void utf8_from_wide(const wchar_t *w, char *dst, size_t cap) {
    dst[0] = '\0';
    if (cap == 0) return;
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, dst, (int)cap, NULL, NULL);
    if (n <= 0) dst[0] = '\0';
    else dst[cap - 1] = '\0'; /* truncated output is not NUL terminated */
}

static uint64_t filetime_u64(FILETIME ft) {
    return ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
}

int32_t pr_list_processes(pr_process **out) {
    *out = NULL;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return -1;

    pr_process *list = NULL;
    int32_t cap = 0, count = 0;
    PROCESSENTRY32W e;
    e.dwSize = sizeof(e);
    if (Process32FirstW(snap, &e)) {
        do {
            if (e.th32ProcessID == 0) continue;
            if (count >= cap) {
                int32_t ncap = cap ? cap * 2 : 256;
                pr_process *n = realloc(list, (size_t)ncap * sizeof(*n));
                if (!n) { CloseHandle(snap); free(list); return -1; }
                list = n;
                cap = ncap;
            }
            pr_process *p = &list[count++];
            memset(p, 0, sizeof(*p));
            p->pid = (int32_t)e.th32ProcessID;
            p->ppid = (int32_t)e.th32ParentProcessID;
            utf8_from_wide(e.szExeFile, p->name, sizeof(p->name));

            HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                   e.th32ProcessID);
            if (!h) continue; /* protected/system process: name only */

            wchar_t wpath[MAX_PATH * 2];
            DWORD plen = (DWORD)(sizeof(wpath) / sizeof(wpath[0]));
            if (QueryFullProcessImageNameW(h, 0, wpath, &plen))
                utf8_from_wide(wpath, p->path, sizeof(p->path));

            FILETIME created, exited, kernel, user;
            if (GetProcessTimes(h, &created, &exited, &kernel, &user)) {
                /* 100 ns units */
                p->cpu_time_ns = (filetime_u64(kernel) + filetime_u64(user)) * 100ull;
                /* FILETIME epoch 1601 -> unix epoch 1970 */
                uint64_t t = filetime_u64(created);
                if (t > 116444736000000000ull)
                    p->start_unix_ms = (int64_t)((t - 116444736000000000ull) / 10000ull);
            }

            PROCESS_MEMORY_COUNTERS pmc;
            if (GetProcessMemoryInfo(h, &pmc, sizeof(pmc)))
                p->rss_kb = (uint64_t)pmc.WorkingSetSize / 1024;
            CloseHandle(h);
        } while (Process32NextW(snap, &e));
    }
    CloseHandle(snap);

    if (count == 0) {
        free(list);
        return 0;
    }
    *out = list;
    return count;
}

void pr_free(void *p) { free(p); }

uint32_t pr_capabilities(void) { return PR_CAP_PROCESS_CPU; }

int32_t pr_connection_size(void) { return (int32_t)sizeof(pr_connection); }
int32_t pr_process_size(void) { return (int32_t)sizeof(pr_process); }
