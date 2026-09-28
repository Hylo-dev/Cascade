//
// OwnerStorage.m
// Cascade
//
#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "OwnerFixtureConfig.h"

extern void ownerRecord(const char *payload);

/// boundedPath rejects paths that cannot be recorded losslessly by this fixed diagnostic.
static bool boundedPath(const char *path) {
    if (!path || !*path || strlen(path) >= 1024 || path[0] != '/') return false;
    for (const unsigned char *cursor = (const unsigned char *)path; *cursor; cursor++)
        if (*cursor < 32 || *cursor > 126 || *cursor == '"' || *cursor == '\\') return false;
    return true;
}

/// ownerStorage uses only the current public sandbox home and immutable prior target paths.
bool ownerStorage(const char *owner, const char *stubIdentity, const char *ownPath,
                  const char *foreignPath, const char *runID, bool create) {
    @autoreleasepool {
        const char *home = NSHomeDirectory().fileSystemRepresentation;
        char expectedHome[1024], directoryName[96], expectedPath[1024], resolved[1024];
        int count = snprintf(expectedHome, sizeof(expectedHome), "%s/Library/Containers/%s/Data", OWNER_USER_HOME, stubIdentity);
        if (count <= 0 || (size_t)count >= sizeof(expectedHome) || !boundedPath(home) || strcmp(home, expectedHome)) {
            ownerRecord("\"kind\":\"storageUnknown\",\"reason\":\"sandboxHomeMismatch\"");
            return false;
        }
        count = snprintf(directoryName, sizeof(directoryName), "CascadeOwner-%s", runID);
        if (count <= 0 || (size_t)count >= sizeof(directoryName)) return false;
        count = snprintf(expectedPath, sizeof(expectedPath), "%s/%s/specimen", home, directoryName);
        if (count <= 0 || (size_t)count >= sizeof(expectedPath) || !boundedPath(expectedPath) ||
            (create ? strcmp(ownPath, "-") != 0 : strcmp(ownPath, expectedPath) != 0)) return false;
        // A fixed-size realpath buffer is safe because Darwin PATH_MAX is 1024.
        // Only our known home and newly created specimen are canonicalized.
        if (!realpath(home, resolved) || strcmp(home, resolved)) return false;
        int homeDescriptor = open(home, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (homeDescriptor < 0) return false;
        int result = 0, failure = 0;
        if (create && mkdirat(homeDescriptor, directoryName, 0700) != 0) {
            result = -1; failure = errno;
        }
        int directory = result == 0 ? openat(homeDescriptor, directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) : -1;
        if (directory < 0 && result == 0) { result = -1; failure = errno; }
        close(homeDescriptor);
        char payload[65];
        memcpy(payload, runID, 32); memcpy(payload + 32, runID, 32); payload[64] = 0;
        payload[0] = payload[1] = !strcmp(owner, "A") ? 'a' : 'b';
        if (result == 0 && create) {
            int output = openat(directory, "specimen", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
            if (output < 0) { result = -1; failure = errno; }
            else {
                if (write(output, payload, 64) != 64) { result = -1; failure = errno ? errno : EIO; }
                if (close(output) != 0 && result == 0) { result = -1; failure = errno; }
            }
        }
        struct stat metadata = {0};
        bool equal = false, regular = false, canonical = false;
        int input = result == 0 ? openat(directory, "specimen", O_RDONLY | O_NOFOLLOW | O_CLOEXEC) : -1;
        if (input < 0 && result == 0) { result = -1; failure = errno; }
        if (input >= 0) {
            if (fstat(input, &metadata) != 0) { result = -1; failure = errno; }
            else {
                regular = S_ISREG(metadata.st_mode) && metadata.st_nlink == 1;
                if (regular && metadata.st_size == 64) {
                    char bytes[65];
                    ssize_t received = read(input, bytes, 64);
                    // The fixed 64-byte read plus one-byte EOF check requests 65 bytes total.
                    char finalByte;
                    ssize_t atEnd = received == 64 ? read(input, &finalByte, 1) : -1;
                    equal = received == 64 && atEnd == 0 && !memcmp(bytes, payload, 64);
                }
            }
            close(input);
        }
        if (directory >= 0) close(directory);
        canonical = result == 0 && realpath(expectedPath, resolved) && !strcmp(expectedPath, resolved);
        char record[3072];
        count = snprintf(record, sizeof(record),
            "\"kind\":\"storageOwn\",\"home\":\"%s\",\"path\":\"%s\",\"created\":%s,\"size\":%lld,\"device\":%llu,\"inode\":%llu,\"contentEqual\":%s,\"regular\":%s,\"canonical\":%s,\"result\":%d,\"errno\":%d",
            home, expectedPath, create ? "true" : "false", (long long)metadata.st_size,
            (unsigned long long)metadata.st_dev, (unsigned long long)metadata.st_ino,
            equal ? "true" : "false", regular ? "true" : "false", canonical ? "true" : "false", result, failure);
        if (count <= 0 || (size_t)count >= sizeof(record)) return false;
        ownerRecord(record);
        if (result != 0 || !equal || !regular || !canonical) return false;
        if (!strcmp(foreignPath, "-")) return !strcmp(owner, "A") && create;
        const char *otherStub = !strcmp(owner, "A") ? OWNER_B_STUB_ID : OWNER_A_STUB_ID;
        char expectedForeign[1024];
        count = snprintf(expectedForeign, sizeof(expectedForeign), "%s/Library/Containers/%s/Data/%s/specimen",
                         OWNER_USER_HOME, otherStub, directoryName);
        if (count <= 0 || (size_t)count >= sizeof(expectedForeign) || !boundedPath(foreignPath) ||
            strcmp(foreignPath, expectedForeign)) return false;
        // These opens never create, truncate, read or write foreign contents.
        errno = 0;
        int readDescriptor = open(foreignPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
        int readError = errno;
        if (readDescriptor >= 0) close(readDescriptor);
        errno = 0;
        int writeDescriptor = open(foreignPath, O_WRONLY | O_NOFOLLOW | O_CLOEXEC);
        int writeError = errno;
        if (writeDescriptor >= 0) close(writeDescriptor);
        bool denied = readDescriptor < 0 && writeDescriptor < 0 &&
            (readError == EACCES || readError == EPERM) && (writeError == EACCES || writeError == EPERM);
        count = snprintf(record, sizeof(record),
            "\"kind\":\"storageCross\",\"path\":\"%s\",\"readResult\":%d,\"readErrno\":%d,\"writeResult\":%d,\"writeErrno\":%d,\"denied\":%s",
            foreignPath, readDescriptor >= 0 ? 0 : -1, readError, writeDescriptor >= 0 ? 0 : -1, writeError, denied ? "true" : "false");
        if (count <= 0 || (size_t)count >= sizeof(record)) return false;
        ownerRecord(record);
        return denied;
    }
}
