#include <sqlite3.h>
#include <string.h>

/* Test-only dyld interposition. Every non-injected call reaches system SQLite.
 * A duplicate close is counted but not forwarded to a freed pointer, making
 * the old ownership bug a deterministic assertion failure rather than UB.
 */
static sqlite3 *fault_database;
static int phase;
static int injected_full;
static int injected_rollback;
static int close_calls;
static int close_v2_calls;
static int did_close;

int mwx_sqlite_fault_full_count(void) { return injected_full; }
int mwx_sqlite_fault_rollback_count(void) { return injected_rollback; }
int mwx_sqlite_fault_close_count(void) { return close_calls; }
int mwx_sqlite_fault_close_v2_count(void) { return close_v2_calls; }

static int mwx_sqlite_step(sqlite3_stmt *statement) {
    sqlite3 *database = sqlite3_db_handle(statement);
    const char *sql = sqlite3_sql(statement);
    const char *creation = "CREATE TABLE collections_meta(";
    const int is_creation = sql && strncmp(sql, creation, strlen(creation)) == 0;
    if (phase == 0 && is_creation) {
        fault_database = database;
        phase = 1;
        injected_full += 1;
        return SQLITE_FULL;
    }
    if (phase == 1 && database == fault_database && sql &&
        strcmp(sql, "ROLLBACK") == 0) {
        phase = 2;
        injected_rollback += 1;
        return SQLITE_IOERR;
    }
    // dyld excludes calls from the replacement image itself from interposition.
    int result = sqlite3_step(statement);
    if (phase == 3 && is_creation && result == SQLITE_DONE) phase = 4;
    return result;
}

static const char *mwx_sqlite_errmsg(sqlite3 *database) {
    if (database == fault_database && phase == 1)
        return "fault injected SQLITE_FULL at collections_meta creation";
    if (database == fault_database && phase == 2)
        return "fault injected SQLITE_IOERR at rollback";
    return sqlite3_errmsg(database);
}

static int record_close(sqlite3 *database, int is_v2) {
    if (database != fault_database || (phase != 2 && phase != 3)) return 0;
    if (is_v2) close_v2_calls += 1;
    else close_calls += 1;
    if (did_close) return 1;
    did_close = 1;
    phase = 3;
    return 0;
}

static int mwx_sqlite_close(sqlite3 *database) {
    if (record_close(database, 0)) return SQLITE_MISUSE;
    return sqlite3_close(database);
}

static int mwx_sqlite_close_v2(sqlite3 *database) {
    if (record_close(database, 1)) return SQLITE_MISUSE;
    return sqlite3_close_v2(database);
}

#define INTERPOSE(replacement, replacee) \
    __attribute__((used)) static const struct { \
        const void *replacement_pointer; const void *replacee_pointer; \
    } interpose_##replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(replacement), (const void *)(replacee) \
    }

INTERPOSE(mwx_sqlite_step, sqlite3_step);
INTERPOSE(mwx_sqlite_errmsg, sqlite3_errmsg);
INTERPOSE(mwx_sqlite_close, sqlite3_close);
INTERPOSE(mwx_sqlite_close_v2, sqlite3_close_v2);
