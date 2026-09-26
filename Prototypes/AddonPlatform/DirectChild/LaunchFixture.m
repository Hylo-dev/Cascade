// Harmless delegated-launch target. Writes one owned marker, then exits immediately.
#import <Foundation/Foundation.h>
#include <unistd.h>
int main(void) {
    @autoreleasepool {
        NSURL *products = NSBundle.mainBundle.bundleURL;
        for (int index = 0; index < 4; index++) products = [products URLByDeletingLastPathComponent];
        NSURL *marker = [products URLByAppendingPathComponent:@"launch-observed.json"];
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"pid": @(getpid()),
            @"parentPID": @(getppid()), @"date": @([NSDate date].timeIntervalSince1970),
            @"bundlePath": NSBundle.mainBundle.bundleURL.path} options:0 error:nil];
        return [data writeToURL:marker atomically:YES] ? 0 : 1;
    }
}
