#ifndef NETWORK_H
#define NETWORK_H

#ifdef __cplusplus
extern "C" {
#endif

// The function prototype
char** get_traceroute_array(const char* destination, int* hop_count);

// Function to free the allocated memory in the returned array
void free_traceroute_array(char** array, int hop_count);

// Function to ping
long ping(const char* target);

#ifdef __cplusplus
}
#endif

#endif  // NETWORK_H
