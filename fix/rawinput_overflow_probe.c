/* Portable detector for the wow64_NtUserGetRawInputDeviceList() overflow.
 *
 * GetRawInputDeviceList(buf, &count, size) must fill exactly `ret` entries and
 * leave the rest of the caller's buffer untouched.  Wine's WoW64 thunk converts
 * `*count` entries instead -- the capacity the caller passed in -- so every
 * entry past the real device count is copied out of an uninitialised temp block
 * into the caller's buffer.
 *
 * Run as a 32-bit binary.  A clean runtime prints AFFECTED=no.
 */
#include <windows.h>
#include <stdio.h>

#define CAP 240   /* what Gepard asks for */

int main(void)
{
    RAWINPUTDEVICELIST buf[CAP];
    UINT count, ret, i, real, dirty = 0, first_dirty = 0;

    count = 0;
    ret = GetRawInputDeviceList(NULL, &count, sizeof(RAWINPUTDEVICELIST));
    printf("query   : ret=%d  devices=%u\n", (int)ret, count);
    real = count;

    memset(buf, 0xCC, sizeof(buf));
    count = CAP;
    ret = GetRawInputDeviceList(buf, &count, sizeof(RAWINPUTDEVICELIST));
    printf("fill    : ret=%d  count_out=%u  capacity_in=%u\n", (int)ret, count, CAP);

    if (ret == (UINT)-1) { printf("call failed, cannot judge\n"); return 2; }

    for (i = ret; i < CAP; i++)
    {
        if (buf[i].hDevice != (HANDLE)(ULONG_PTR)0xCCCCCCCC || buf[i].dwType != 0xCCCCCCCC)
        {
            if (!dirty) first_dirty = i;
            dirty++;
        }
    }

    printf("devices returned : %u\n", ret);
    printf("entries clobbered past the returned count : %u", dirty);
    if (dirty) printf("  (first at index %u)", first_dirty);
    printf("\n");

    if (dirty)
    {
        printf("sample of clobbered entries:\n");
        for (i = first_dirty; i < first_dirty + 4 && i < CAP; i++)
            printf("    [%3u] hDevice=%p dwType=%08x\n", i, buf[i].hDevice, (unsigned)buf[i].dwType);
    }

    printf("AFFECTED=%s\n", dirty ? "yes" : "no");
    return dirty ? 1 : 0;
}
