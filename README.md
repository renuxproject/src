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

Building with ./build.sh
-------------------------------
Renux brings the classic NetBSD `build.sh` entry point to a modern Berkeley-heritage system.
Instead of (or in addition to) `make buildworld`/`make buildkernel`, you can
drive the whole build from the top of the tree with one script that behaves
like NetBSD's `build.sh`:

    # Build world (userland) and the kernel
    ./build.sh build

    # Build only the kernel (kernel toolchain + kernel, no buildworld needed)
    ./build.sh kernel=GENERIC
    ./build.sh kernel.gdb=GENERIC       # include a GDB-debuggable kernel
    ./build.sh kernels                   # build all kernels

    # Bootable images (kernel + loader, no userland needed)
    ./build.sh bootimage                # UEFI disk (renux-uefi.img) + BIOS ISO (renux-bios.iso)
    ./build.sh iso                      # UEFI ISO (renux-uefi.iso) + BIOS ISO (renux-bios.iso)
    ./build.sh qemu                     # boot UEFI image in QEMU (GUI)
    ./build.sh -L bios qemu             # boot the BIOS ISO in QEMU (SeaBIOS)

    # Other useful operations
    ./build.sh world                     # buildworld only
    ./build.sh distribution             # build distribution
    ./build.sh release                  # build a release
    ./build.sh update                   # git pull --ff-only
    ./build.sh show-params              # show the build parameters
    ./build.sh list-arch                # list supported architectures

    # Options
    ./build.sh -m amd64 -a amd64    kernel=GENERIC   # explicit target
    ./build.sh -j 8                 build           # parallel make
    ./build.sh -n                   kernel=GENERIC   # dry-run (show commands)
    ./build.sh -K                   iso             # kernel-only image
    ./build.sh -I /some/out/dir     bootimage       # output image directory
    ./build.sh -D /some/dest        world           # set DESTDIR
    ./build.sh -U                   world           # unprivileged (NO_ROOT)

`./build.sh` is self-contained and portable: it runs on any Unix host
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
