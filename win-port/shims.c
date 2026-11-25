/* WIN-PORT shims: link-stage compatibility for zig(mingw) + V8(MSVC /MD) hybrid link. */
#include <wchar.h>
#include <stdlib.h>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

/* V8's chromium libc++ expects wcstold as dllimport (__imp_ indirect slot). */
void *__imp_wcstold = (void *)wcstold;

/* MSVC TLS machinery members removed from filtered msvcrt.lib (clashed with zig crt2.o). */
char __tls_guard = 0;
void __dyn_tls_on_demand_init(void *h) { (void)h; }

/* UCRT-only _strtold_l: mingw lacks it; locale arg ignored (C-locale parse). */
long double _strtold_l(const char *s, char **e, void *loc)
{
    (void)loc;
    return strtold(s, e);
}
void *__imp__strtold_l = (void *)_strtold_l;

/* c_v8.lib (chromium libc++) references strtold as dllimport; provide the
 * __imp_ slot explicitly so lld-link does not warn LNK4217 about the local
 * definition in libmingw32. */
void *__imp_strtold = (void *)strtold;

/* localtime_s: not in msvcrt.dll nor ucrt.lib present here; Win32 API impl. */
#undef localtime_s
static int filetime_to_tm(struct tm *_tm, const time_t *_time, BOOL local, int *offset)
{
    SYSTEMTIME st;
    FILETIME ft, lft;
    unsigned __int64 t = (unsigned __int64)*_time * 10000000ULL + 116444736000000000ULL;
    ft.dwLowDateTime = (DWORD)t;
    ft.dwHighDateTime = (DWORD)(t >> 32);
    if (local && !FileTimeToLocalFileTime(&ft, &lft)) return 1;
    if (!FileTimeToSystemTime(local ? &lft : &ft, &st)) return 1;
    if (local && offset) {
        unsigned __int64 local_ticks = ((unsigned __int64)lft.dwHighDateTime << 32) | lft.dwLowDateTime;
        *offset = (int)(((__int64)local_ticks - (__int64)t) / 10000000);
    }
    _tm->tm_year = st.wYear - 1900;
    _tm->tm_mon = st.wMonth - 1;
    _tm->tm_mday = st.wDay;
    _tm->tm_hour = st.wHour;
    _tm->tm_min = st.wMinute;
    _tm->tm_sec = st.wSecond;
    _tm->tm_wday = st.wDayOfWeek;
    _tm->tm_yday = 0;
    _tm->tm_isdst = -1;
    return 0;
}

int localtime_s(struct tm *_tm, const time_t *_time)
{
    return filetime_to_tm(_tm, _time, TRUE, NULL);
}

int lp_win_localtime(struct tm *_tm, const time_t *_time, int *offset)
{
    return filetime_to_tm(_tm, _time, TRUE, offset);
}

int lp_win_gmtime(struct tm *_tm, const time_t *_time)
{
    return filetime_to_tm(_tm, _time, FALSE, NULL);
}
