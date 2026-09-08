// Linux correctness diagnostics only. Never preload this library for timing.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uio.h>
#include <unistd.h>

static _Atomic unsigned long writes, barriers, skipped, shortened, interrupted;

static int measured(int fd) {
    char link[64], path[1024];
    snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
    ssize_t len = readlink(link, path, sizeof(path) - 1);
    if (len < 0) return 0;
    path[len] = 0;
    return strstr(path, "/paged-measured/") != NULL;
}

static int fault(int fd, off_t offset) {
    if (!measured(fd) || offset < 4096) return 0;
    atomic_fetch_add(&writes, 1);
    const char *mode = getenv("COMMONWARE_IO_FAULT");
    if (!mode) return 0;
    if (!strcmp(mode, "skip") && offset == 4096) {
        atomic_fetch_add(&skipped, 1);
        return 1;
    }
    if (!strcmp(mode, "short") && !atomic_exchange(&shortened, 1)) return 2;
    if (!strcmp(mode, "eintr") && !atomic_exchange(&interrupted, 1)) return 3;
    if (!strcmp(mode, "zero")) return 4;
    return 0;
}

ssize_t pwritev2(int fd, const struct iovec *iov, int count, off_t offset, int flags) {
    ssize_t (*real)(int, const struct iovec *, int, off_t, int) = dlsym(RTLD_NEXT, "pwritev2");
    size_t total = 0;
    for (int i = 0; i < count; i++) total += iov[i].iov_len;
    int f = fault(fd, offset);
    if (f == 1) return (ssize_t)total;
    if (f == 3) { errno = EINTR; return -1; }
    if (f == 4) return 0;
    if (measured(fd) && (flags & RWF_DSYNC)) atomic_fetch_add(&barriers, 1);
    if (f == 2) {
        struct iovec partial = iov[0];
        partial.iov_len = (partial.iov_len + 1) / 2;
        return real(fd, &partial, 1, offset, flags);
    }
    return real(fd, iov, count, offset, flags);
}

ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset) {
    ssize_t (*real)(int, const void *, size_t, off_t) = dlsym(RTLD_NEXT, "pwrite");
    int f = fault(fd, offset);
    if (f == 1) return (ssize_t)count;
    if (f == 3) { errno = EINTR; return -1; }
    if (f == 4) return 0;
    if (f == 2) count = (count + 1) / 2;
    return real(fd, buf, count, offset);
}

ssize_t pwrite64(int fd, const void *buf, size_t count, off64_t offset) {
    return pwrite(fd, buf, count, offset);
}

int fdatasync(int fd) {
    int (*real)(int) = dlsym(RTLD_NEXT, "fdatasync");
    if (measured(fd)) atomic_fetch_add(&barriers, 1);
    return real(fd);
}

int fsync(int fd) {
    int (*real)(int) = dlsym(RTLD_NEXT, "fsync");
    if (measured(fd)) atomic_fetch_add(&barriers, 1);
    return real(fd);
}

__attribute__((destructor)) static void report(void) {
    fprintf(stderr, "IO_CHECK {\"writes\":%lu,\"barriers\":%lu,\"skipped\":%lu,"
        "\"shortened\":%lu,\"interrupted\":%lu}\n",
        atomic_load(&writes), atomic_load(&barriers), atomic_load(&skipped),
        atomic_load(&shortened), atomic_load(&interrupted));
}
