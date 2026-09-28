// Isolate raise(SIGKILL) on a libdispatch workqueue thread from XPC/sandbox.
#include <dispatch/dispatch.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1],"immediate-exit") && strcmp(argv[1],"wait-signal"))) return 85;
    int immediate = !strcmp(argv[1],"immediate-exit");
    setbuf(stdout,NULL);
    alarm(2);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
        if (raise(SIGKILL)) _exit(84);
        if (immediate) _exit(84);
        // A successful signal request can return before process termination.
        for (;;) pause();
    });
    dispatch_main();
}
