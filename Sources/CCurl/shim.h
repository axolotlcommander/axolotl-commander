// System libcurl (the macOS SDK ships the headers) plus typed wrappers for the
// variadic curl_easy_setopt / curl_easy_getinfo, which Swift cannot call.
#ifndef CCURL_SHIM_H
#define CCURL_SHIM_H

#include <curl/curl.h>

static inline CURLcode icmd_curl_global_init(void) {
    return curl_global_init(CURL_GLOBAL_DEFAULT);
}

static inline CURLcode icmd_curl_setopt_long(CURL *h, CURLoption o, long v) {
    return curl_easy_setopt(h, o, v);
}

static inline CURLcode icmd_curl_setopt_off(CURL *h, CURLoption o, curl_off_t v) {
    return curl_easy_setopt(h, o, v);
}

static inline CURLcode icmd_curl_setopt_ptr(CURL *h, CURLoption o, void *v) {
    return curl_easy_setopt(h, o, v);
}

static inline CURLcode icmd_curl_setopt_str(CURL *h, CURLoption o, const char *v) {
    return curl_easy_setopt(h, o, v);
}

static inline CURLcode icmd_curl_setopt_slist(CURL *h, CURLoption o, struct curl_slist *v) {
    return curl_easy_setopt(h, o, v);
}

/// CURLOPT_WRITEFUNCTION or CURLOPT_HEADERFUNCTION.
static inline CURLcode icmd_curl_setopt_write(CURL *h, CURLoption o, curl_write_callback cb) {
    return curl_easy_setopt(h, o, cb);
}

static inline CURLcode icmd_curl_setopt_read(CURL *h, curl_read_callback cb) {
    return curl_easy_setopt(h, CURLOPT_READFUNCTION, cb);
}

static inline CURLcode icmd_curl_setopt_xferinfo(CURL *h, curl_xferinfo_callback cb) {
    return curl_easy_setopt(h, CURLOPT_XFERINFOFUNCTION, cb);
}

static inline CURLcode icmd_curl_getinfo_long(CURL *h, CURLINFO i, long *v) {
    return curl_easy_getinfo(h, i, v);
}

static inline CURLcode icmd_curl_getinfo_off(CURL *h, CURLINFO i, curl_off_t *v) {
    return curl_easy_getinfo(h, i, v);
}

static inline CURLcode icmd_curl_getinfo_string(CURL *h, CURLINFO i, const char **v) {
    return curl_easy_getinfo(h, i, (char **)v);
}

#endif
