/* zlib — compresses the usage-cache snapshot on Linux.
   macOS uses Foundation's `NSData.compressed(using: .zlib)` and never links this. */
#include <zlib.h>
