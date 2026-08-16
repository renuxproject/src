Copyright (c) 2026 Renan Lucas Vieira Hilário.

# Renux Decentralization

Renux is a community-driven operating system designed to enable
**decentralized development, distribution and governance**. Decentralization
is a property of the project's ecosystem - code, development, infrastructure,
distribution and governance - not just a slogan on a website.

> Renux is not decentralized because it has many contributors. It is
> decentralized because **no contributor has absolute authority over the
> project**.

## Fundamental principles

1. **Forkability** - anyone may modify and redistribute Renux under its license.
2. **Independence** - no specific infrastructure is required to keep developing
   Renux.
3. **No central authority** - no person, company, forge or organization has
   absolute authority over the project.
4. **Interoperability** - independent projects must be able to reuse Renux
   components.
5. **Community governance** - changes should be discussed publicly whenever
   possible.
6. **Right to fork** - disagreements may legitimately result in forks.
7. **No "official" hierarchy** - a fork is not automatically inferior to the
   project that gave rise to it.

## Governance

- There is no central entity that controls Renux.
- Anyone may create a distribution or variant of Renux.
- There is no obligation to accept decisions from a "central committee".
- Maintainers may keep their own components.
- Important decisions should be public and open to discussion.
- The original project is just **one implementation / line of development**,
  not "the authority" over Renux.

## Code and infrastructure: no single point of failure

The repository must not be a single point of failure. Any of these may exist
at any time, without needing authorization from the others:

    Renux
     |-- git.disroot.org/renux/src
     |-- github.com/renuxproject/src (mirror)
     |-- any other forge, mirror or tarball

If any single forge disappears, anyone should be able to clone another copy
and keep going:

    git clone https://other-forge.example/renux/src

## Forks are first-class citizens

Forks and independent efforts are legitimate parts of the ecosystem:

    Renux
     |-- Renux (original line of development)
     |-- Renux Desktop
     |-- Renux Server
     |-- Renux Hardened
     `-- Renux of another community

None of them needs permission to be called Renux. The only practical concern
is trademark, so the project separates three things:

- **code** - freedom defined by the license;
- **documentation** - under its own license;
- **the "Renux" brand** - rules for brand usage.

## Distribution

There is no mandatory "official repository". Communities may keep their own
repositories, and users choose which ones they trust:

    repo.renux.org
    repo.example.org
    repo.mycommunity.net
    repo.company.com

## System modularity

Decentralization is not limited to git: the system is built so that components
(kernel, init, libc, userland, network, storage, packaging) can evolve
relatively independently, mirroring the `sys/arch` separation already present
in the tree.
