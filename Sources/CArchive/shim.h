// Minimal declarations from libarchive 3.7 (archive.h, archive_entry.h).
// macOS ships /usr/lib/libarchive.2.dylib but no headers.
#ifndef CARCHIVE_SHIM_H
#define CARCHIVE_SHIM_H

#include <sys/types.h>
#include <stdint.h>
#include <stddef.h>
#include <time.h>

struct archive;
struct archive_entry;

typedef int64_t la_int64_t;
typedef ssize_t la_ssize_t;

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

#define ARCHIVE_FILTER_NONE 0
#define ARCHIVE_FILTER_GZIP 1
#define ARCHIVE_FILTER_BZIP2 2
#define ARCHIVE_FILTER_XZ 6

#define ARCHIVE_FORMAT_BASE_MASK 0xff0000
#define ARCHIVE_FORMAT_TAR 0x30000
#define ARCHIVE_FORMAT_ZIP 0x50000
#define ARCHIVE_FORMAT_RAR 0xD0000
#define ARCHIVE_FORMAT_7ZIP 0xE0000
#define ARCHIVE_FORMAT_RAR_V5 0x100000

#define ARCHIVE_EXTRACT_OWNER 0x0001
#define ARCHIVE_EXTRACT_PERM 0x0002
#define ARCHIVE_EXTRACT_TIME 0x0004
#define ARCHIVE_EXTRACT_NO_OVERWRITE 0x0008
#define ARCHIVE_EXTRACT_UNLINK 0x0010
#define ARCHIVE_EXTRACT_SECURE_SYMLINKS 0x0100
#define ARCHIVE_EXTRACT_SECURE_NODOTDOT 0x0200
#define ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS 0x10000

#define AE_IFMT 0170000
#define AE_IFREG 0100000
#define AE_IFLNK 0120000
#define AE_IFDIR 0040000

const char *archive_error_string(struct archive *);
int archive_errno(struct archive *);
int archive_format(struct archive *);
int archive_filter_count(struct archive *);
int archive_filter_code(struct archive *, int);

struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_add_passphrase(struct archive *, const char *);
int archive_read_open_filename(struct archive *, const char *_filename, size_t _block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
la_ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
int archive_read_close(struct archive *);
int archive_read_free(struct archive *);

struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_set_format_7zip(struct archive *);
int archive_write_set_format_pax_restricted(struct archive *);
int archive_write_add_filter_gzip(struct archive *);
int archive_write_add_filter_bzip2(struct archive *);
int archive_write_add_filter_xz(struct archive *);
int archive_write_set_options(struct archive *_a, const char *opts);
int archive_write_open_filename(struct archive *, const char *_file);
int archive_write_header(struct archive *, struct archive_entry *);
la_ssize_t archive_write_data(struct archive *, const void *, size_t);
int archive_write_finish_entry(struct archive *);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);

struct archive *archive_write_disk_new(void);
int archive_write_disk_set_options(struct archive *, int flags);

struct archive_entry *archive_entry_new(void);
struct archive_entry *archive_entry_clone(struct archive_entry *);
void archive_entry_free(struct archive_entry *);

const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
void archive_entry_set_pathname_utf8(struct archive_entry *, const char *);
const char *archive_entry_hardlink(struct archive_entry *);
const char *archive_entry_hardlink_utf8(struct archive_entry *);
void archive_entry_set_hardlink_utf8(struct archive_entry *, const char *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_symlink_utf8(struct archive_entry *);
void archive_entry_set_symlink_utf8(struct archive_entry *, const char *);

mode_t archive_entry_filetype(struct archive_entry *);
void archive_entry_set_filetype(struct archive_entry *, unsigned int);
mode_t archive_entry_perm(struct archive_entry *);
void archive_entry_set_perm(struct archive_entry *, mode_t);
la_int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
void archive_entry_set_size(struct archive_entry *, la_int64_t);
time_t archive_entry_mtime(struct archive_entry *);
long archive_entry_mtime_nsec(struct archive_entry *);
int archive_entry_mtime_is_set(struct archive_entry *);
void archive_entry_set_mtime(struct archive_entry *, time_t, long);
int archive_entry_is_encrypted(struct archive_entry *);
void archive_entry_set_uid(struct archive_entry *, la_int64_t);
void archive_entry_set_gid(struct archive_entry *, la_int64_t);
void archive_entry_set_uname_utf8(struct archive_entry *, const char *);
void archive_entry_set_gname_utf8(struct archive_entry *, const char *);

#endif
