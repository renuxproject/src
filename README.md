Renux Source:
---------------
Renux is a modern BSD operating system, designed to be easy to maintain and
debug, with a focus on portability and performance. The whole tree is meant
to be understandable and modifiable.

This is the top level of the Renux source directory.

For copyright information, please see [the file COPYRIGHT](COPYRIGHT) in this directory.
Additional copyright information also exists for some sources in this tree - please see the specific source directories for more information.

The Makefile in this directory supports a number of targets for building components (or all) of the Renux source tree.
See build(7), config(8), for more information, including setting make(1) variables, in the way NetBSD conventions.

Building with ./renux
-------------------------------
Renux brings the classic NetBSD-style `renux` entry point to a modern Berkeley-heritage system.
Instead of (or in addition to) `make buildworld`/`make buildkernel`, you can
drive the whole build from the top of the tree with one script that behaves
like NetBSD's `renux`:

    # Build world (userland) and the kernel
    ./renux build

    # Build only the kernel (kernel toolchain + kernel, no buildworld needed)
    ./renux kernel=GENERIC
    ./renux kernel.gdb=GENERIC       # include a GDB-debuggable kernel
    ./renux kernels                   # build all kernels

    # Bootable images (kernel + loader, no userland needed)
    ./renux bootimage                # UEFI disk (renux-uefi.img) + BIOS ISO (renux-bios.iso)
    ./renux iso                      # UEFI ISO (renux-uefi.iso) + BIOS ISO (renux-bios.iso)
    ./renux qemu                     # boot UEFI image in QEMU (GUI)
    ./renux -L bios qemu             # boot the BIOS ISO in QEMU (SeaBIOS)

    # Other useful operations
    ./renux world                     # buildworld only
    ./renux distribution             # build distribution
    ./renux release                  # build a release
    ./renux update                   # git pull --ff-only
    ./renux show-params              # show the build parameters
    ./renux list-arch                # list supported architectures

    # Options
    ./renux -m amd64 -a amd64    kernel=GENERIC   # explicit target
    ./renux -j 8                 build           # parallel make
    ./renux -n                   kernel=GENERIC   # dry-run (show commands)
    ./renux -K                   iso             # kernel-only image
    ./renux -I /some/out/dir     bootimage       # output image directory
    ./renux -D /some/dest        world           # set DESTDIR
    ./renux -U                   world           # unprivileged (NO_ROOT)

`./renux` is self-contained and portable: it runs on any Unix host
(FreeBSD, Linux, NetBSD, OpenBSD, DragonFly or macOS), automatically
provisions missing host tools (e.g. `time`, `bc`, `hostname`) into
`obj/host-shims`, builds a kernel without requiring a prior `buildworld`
when using the `kernel=` operations, and tolerates a host compiler newer
than the one officially supported (kernel builds go out with `-Werror`
disabled for portability).

The `iso`/`bootimage`/`qemu` operations build the EFI loader from `stand/`
with the same cross toolchain and produce a kernel-only boot medium:
`EFI/BOOT/BOOTX64.EFI` plus `/boot/kernel/kernel` on a FAT32 ESP, wrapped in
a GPT disk (`renux.img`) or an El Torito ISO (`renux.iso`).  These boot
straight into the kernel; a full system requires `world`/`distribution`.

For copyright information, please see [the file COPYRIGHT](COPYRIGHT) in this directory.

For information on the CPU architectures and platforms supported by the
Renux project, see the documentation shipped with this tree.

Hacking:
--------
Renux is designed to be hacked. See [docs/HACKING.md](docs/HACKING.md) for
building, runtime tuning (sysctl), kernel modules (kld), DTrace and kernel
debugging - no recompiling required for most of it.

Source Roadmap:
---------------
| Directory | Description |
| --------- | ----------- |
| bin | System/user commands. |
| cddl | Source code for third-party software under the Common Development and Distribution License. |
| contrib | Source code for third-party software. |
| crypto | Source code for cryptographic libraries and commands (see [crypto/README](crypto/README)). |
| etc | Template files for /etc. |
| gnu | Source code for third-party software under the GNU General Public License (GPL) or Lesser General Public License (LGPL). Please see [gnu/COPYING](gnu/COPYING) and [gnu/COPYING.LIB](gnu/COPYING.LIB) for more information. |
| include | System include files. |
| kerberos5 | Build system for Kerberos 5 (Heimdal). |
| krb5 | Build system for Kerberos 5 (MIT). |
| lib | System libraries. |
| libexec | System commands intended to be executed by other commands or daemons. |
| release | Makefiles and scripts used for building releases and VM images. |
| rescue | Build system for statically linked /rescue commands. |
| sbin | System commands. |
| secure | Build system for cryptographic libraries and commands (excluding Kerberos). |
| share | Shared resources. |
| stand | Boot loader sources. |
| sys | Kernel sources (see [sys/README.md](sys/README.md)). |
| targets | Support for experimental `DIRDEPS_BUILD` |
| tests | Tests which can be run by Kyua.  See [tests/README](tests/README) for additional information. |
| tools | Ancillary utilities and tests (not included in the build). |
| usr.bin | User commands. |
| usr.sbin | System administration commands. |

For information on synchronizing your source tree with the development
branches of the Renux projects, please see the documentation and mailing
lists for the Renux project.
