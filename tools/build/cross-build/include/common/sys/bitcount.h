/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Cross-build shim providing <sys/bitcount.h> for non-FreeBSD hosts.
 * FreeBSD's sys/types.h pulls in sys/bitcount.h; on Linux/macOS hosts the
 * shim include tree must provide it.  Uses __builtin_popcount{,l,ll} so it
 * works with both clang and gcc.
 */
#ifndef _SYS_BITCOUNT_H_
#define	_SYS_BITCOUNT_H_

#define	__const_bitcount8(x) ( \
    !!((x) & (1 << 0)) + \
    !!((x) & (1 << 1)) + \
    !!((x) & (1 << 2)) + \
    !!((x) & (1 << 3)) + \
    !!((x) & (1 << 4)) + \
    !!((x) & (1 << 5)) + \
    !!((x) & (1 << 6)) + \
    !!((x) & (1 << 7)))

#define	__const_bitcount16(x) ( \
    __const_bitcount8(x) + \
    __const_bitcount8((x) >> 8))

#define	__const_bitcount32(x) ( \
    __const_bitcount16(x) + \
    __const_bitcount16((x) >> 16))

#define	__const_bitcount64(x) ( \
    __const_bitcount32(x) + \
    __const_bitcount32((x) >> 32))

static __inline int
__bitcount16(unsigned int _x)
{
	return (__builtin_popcount(_x & 0xffff));
}

static __inline int
__bitcount32(unsigned int _x)
{
	return (__builtin_popcount(_x));
}

static __inline int
__bitcount64(unsigned long long _x)
{
	return (__builtin_popcountll(_x));
}

#define	__bitcountl(x)	__builtin_popcountl((unsigned long)(x))
#define	__bitcount(x)	__builtin_popcount((unsigned int)(x))

#endif /* !_SYS_BITCOUNT_H_ */
