/*
 * Simple Hello World for CodeQL testing
 * This file demonstrates basic C constructs that CodeQL can analyze.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Function to greet a user */
void greet(const char *name) {
    printf("Hello, %s!\n", name);
}

/* Function demonstrating a potential buffer issue (for CodeQL to find) */
void unsafe_copy(char *dest, const char *src) {
    strcpy(dest, src);  /* CodeQL should flag this */
}

/* Function with proper bounds checking */
void safe_copy(char *dest, size_t dest_size, const char *src) {
    strncpy(dest, src, dest_size - 1);
    dest[dest_size - 1] = '\0';
}

int main(int argc, char *argv[]) {
    const char *name = "World";
    
    if (argc > 1) {
        name = argv[1];
    }
    
    greet(name);
    
    /* Demonstrate safe string handling */
    char buffer[64];
    safe_copy(buffer, sizeof(buffer), name);
    printf("Copied safely: %s\n", buffer);
    
    return EXIT_SUCCESS;
}
