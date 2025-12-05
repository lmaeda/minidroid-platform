#include <stdio.h>
#include <unistd.h>

int main() {
    printf("Native Service Started\n");
    while(1) {
        sleep(3600);
    }
    return 0;
}

