#ifndef NETWORK_H
#define NETWORK_H

#ifdef __cplusplus
extern "C" {
#endif

char** get_traceroute_array(const char* destination, int* hop_count);
void free_traceroute_array(char** array, int hop_count);

#ifdef __cplusplus
}
#endif

#endif // NETWORK_H
