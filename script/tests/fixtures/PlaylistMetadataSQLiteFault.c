#include <sqlite3.h>
#include <stdatomic.h>
#include <string.h>

/* One explicit test action arms one real SQLite COMMIT failure. All other
 * calls, including the product's ROLLBACK, reach the system implementation. */
static _Atomic int armed;
static _Atomic int failures;
static sqlite3 *failed_database;

void mwx_playlist_fail_next_commit(void) { atomic_store(&armed, 1); }
int mwx_playlist_commit_failure_count(void) { return atomic_load(&failures); }

static int mwx_playlist_step(sqlite3_stmt *statement) {
    const char *sql = sqlite3_sql(statement);
    if (sql && strcmp(sql, "COMMIT") == 0 && atomic_exchange(&armed, 0)) {
        atomic_fetch_add(&failures, 1);
        failed_database = sqlite3_db_handle(statement);
        return SQLITE_IOERR;
    }
    int result = sqlite3_step(statement);
    if (sql && strcmp(sql, "ROLLBACK") == 0 && result == SQLITE_DONE)
        failed_database = NULL;
    return result;
}

static const char *mwx_playlist_errmsg(sqlite3 *database) {
    if (database == failed_database) return "controlled playlist COMMIT failure before publication";
    return sqlite3_errmsg(database);
}

#define INTERPOSE(replacement, replacee) \
    __attribute__((used)) static const struct { \
        const void *replacement_pointer; const void *replacee_pointer; \
    } interpose_##replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(replacement), (const void *)(replacee) \
    }

INTERPOSE(mwx_playlist_step, sqlite3_step);
INTERPOSE(mwx_playlist_errmsg, sqlite3_errmsg);
