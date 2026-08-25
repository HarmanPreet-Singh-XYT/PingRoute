#ifndef NETWORK_H
#define NETWORK_H

#ifdef __cplusplus
extern "C" {
#endif

__attribute__((visibility("default"))) __attribute__((used))
char** get_traceroute_array(const char* destination, int* hop_count);

__attribute__((visibility("default"))) __attribute__((used))
void free_traceroute_array(char** array, int hop_count);

__attribute__((visibility("default"))) __attribute__((used))
int ping_host(const char* destination, int timeout_ms);

__attribute__((visibility("default"))) __attribute__((used))
void ping_all_hops(const char* target_destination, const char** hop_ips, int count, int timeout_ms, int* results);

#ifdef __cplusplus
}
#endif

#endif // NETWORK_H
