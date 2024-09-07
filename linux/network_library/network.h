// network.h
#ifndef NETWORK_H
#define NETWORK_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Gets network data as an array of strings.
 * @param destination The target IP address or domain.
 * @param hop_count Pointer to an integer to store the number of hops.
 * @return An array of strings representing each hop's data.
 */
char** get_network_array(const char* destination, int* hop_count);

/**
 * Frees the memory allocated for the network array.
 * @param array The array of strings to be freed.
 * @param hop_count The number of hops.
 */
void free_network_array(char** array, int hop_count);

#ifdef __cplusplus
}
#endif

#endif // NETWORK_H
