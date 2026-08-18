/* Linux has no `SQLite3` system module (that name is Darwin-only), so the
   sqlite3 C API is re-exported under `CSQLite`. Core files pick between the two
   with `#if canImport(SQLite3)`. */
#include <sqlite3.h>
