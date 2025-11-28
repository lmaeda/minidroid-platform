#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// Processes the input string by copying it into a buffer and printing it.
// This function contains a buffer overflow vulnerability.
void process_input(char *input) {
    // Declare a buffer of size 50.
    char buffer[50];
    // SAST VULNERABILITY: Buffer Overflow (CWE-120)
    // Snyk Code should catch this.
    // Copy the input string into the buffer without any size checks.
    strcpy(buffer, input); 
    // Print the processed buffer.
    printf("Processed: %s\n", buffer);
}

// Main function of the native service.
int main(int argc, char **argv) {
    // Check if there is a command-line argument.
    if (argc > 1) {
        // If there is an argument, process it.
        process_input(argv[1]);
    } else {
        // If there are no arguments, print a waiting message.
        printf("Minidroid Native Service. Waiting for input...\n");
    }
    // Return 0 to indicate successful execution.
    return 0;
}
