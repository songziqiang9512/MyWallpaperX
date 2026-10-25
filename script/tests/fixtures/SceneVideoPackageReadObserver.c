/* Test-only pread observation for one actual Root FD and package-entry range. */
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <stdatomic.h>
#include <pthread.h>

static pthread_mutex_t state_lock = PTHREAD_MUTEX_INITIALIZER;
static int target_fd = -1;
static dev_t target_device;
static ino_t target_inode;
static uint64_t range_begin, range_end;
static _Atomic uint64_t payload_bytes, payload_calls;

int mwx_video_entry_observe(int fd, uint64_t begin, uint64_t length) {
    struct stat value;
    if (!length || length > UINT64_MAX - begin || fstat(fd, &value) != 0 || !S_ISREG(value.st_mode)) return -1;
    pthread_mutex_lock(&state_lock);
    target_fd = fd; target_device = value.st_dev; target_inode = value.st_ino;
    range_begin = begin; range_end = begin + length;
    atomic_store(&payload_bytes, 0); atomic_store(&payload_calls, 0);
    pthread_mutex_unlock(&state_lock);
    return 0;
}
uint64_t mwx_video_entry_bytes(void) { return atomic_load(&payload_bytes); }
uint64_t mwx_video_entry_calls(void) { return atomic_load(&payload_calls); }

static ssize_t observe_pread(int fd, void *buffer, size_t count, off_t offset) {
    ssize_t result = pread(fd, buffer, count, offset);
    int saved_errno = errno;
    if (result > 0 && offset >= 0) {
        struct stat value;
        pthread_mutex_lock(&state_lock);
        if (fd == target_fd && fstat(fd, &value) == 0 && value.st_dev == target_device && value.st_ino == target_inode) {
            uint64_t begin = (uint64_t)offset;
            uint64_t end = begin + (uint64_t)result;
            uint64_t lower = begin > range_begin ? begin : range_begin;
            uint64_t upper = end < range_end ? end : range_end;
            if (upper > lower) {
                atomic_fetch_add(&payload_bytes, upper - lower);
                atomic_fetch_add(&payload_calls, 1);
            }
        }
        pthread_mutex_unlock(&state_lock);
    }
    errno = saved_errno;
    return result;
}
__attribute__((used)) static struct { const void *replacement; const void *original; }
interpose_pread __attribute__((section("__DATA,__interpose"))) = { (const void *)observe_pread, (const void *)pread };
