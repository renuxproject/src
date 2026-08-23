# Renux

A modern BSD operating system, designed to be easy to maintain and debug,
with a focus on portability and performance. The whole tree is meant to be
understood, modified and rebuilt by whoever uses it.

Experimental. Currently targets amd64 (x86-64) only.

## Build

    git clone https://github.com/renuxproject/src.git renux
    cd renux
    ./renux build        # world + GENERIC kernel
    ./renux iso          # bootable hybrid ISO in release/
    ./renux qemu         # boot it in QEMU

One script drives everything and runs on any Unix host: FreeBSD, Linux,
NetBSD, OpenBSD, DragonFly or macOS. Missing host tools are provisioned
automatically; cross-builds need no preinstalled toolchain beyond LLVM.

`./renux --help` lists all operations (`kernel=GENERIC`, `kernels`,
`world`, `worldiso`, `bootimage`, `release`, ...) and options
(`-j N`, `-K`, `-I DIR`, `-n`, `--verbose`, ...).

## Source tree

| Directory | Contents |
| --------- | -------- |
| bin sbin usr.bin usr.sbin | base userland commands |
| lib libexec include | libraries and system headers |
| sys | kernel sources; machine-dependent code lives under `sys/arch/` |
| stand | boot loader |
| share etc | shared resources and `/etc` templates |
| contrib crypto cddl | third-party sources |
| release rescue targets tests tools | build glue and support |

## Documentation

- [docs/HACKING.md](docs/HACKING.md) — building, tuning and debugging
- [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) — contributing changes
- [docs/DECENTRALIZATION.md](docs/DECENTRALIZATION.md) — project philosophy

Copyright information: see [COPYRIGHT](COPYRIGHT); third-party sources keep
their own licenses in their directories.
