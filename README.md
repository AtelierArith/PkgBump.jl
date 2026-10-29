# PkgBump [![Build Status](https://github.com/atelierarith/PkgBump.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/atelierarith/PkgBump.jl/actions/workflows/CI.yml?query=branch%3Amain) [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://atelierarith.github.io/PkgBump.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://atelierarith.github.io/PkgBump.jl/dev/)
# PkgBump.jl

Automatically increments the version in a Julia Project file. Package developers only have to run one of the three functions:

```julia
# Roughly speaking
bumppatch: v"x.y.z" -> v"x.y.(z+1)"
bumpminor: v"x.y.z" -> v"x.(y+1).0"
bumpmajor: v"x.y.z" -> v"(x+1).0.0"
```

Internally, we use the `Base.nextpatch`, `Base.nextminor`, `Base.nextmajor` functions respectively.

## How to Use

### Installing PkgBump.jl in a Shared Environment

```console
$ git clone https://github.com/AtelierArith/PkgBump.jl
$ ls
PkgBump.jl
$ julia -e 'using Pkg; Pkg.activate(); Pkg.develop(path="PkgBump.jl")'
```

### Updating Your Julia Project File

To create a release for `MyPkg.jl` located at `path/to/your/MyPkg.jl`, execute the following commands:

```console
$ cd path/to/your/MyPkg.jl
$ ls # Verify the presence of Project.toml or JuliaProject.toml
Output: Project.toml src test ...
$ julia --project -e 'using PkgBump; PkgBump.bumppatch()'
```

This command requires the GitHub CLI (`gh`) to be installed and authenticated. It updates the Julia project file (`Project.toml` or `JuliaProject.toml`), commits the changes, and pushes them to a remote repository named `pkgbump/bump-to-version-$(new_version)`, where `new_version` is the next patch version of the current version of `MyPkg.jl`. It also creates a pull request. Other options include `bumpminor` and `bumpmajor`.

### References

- [Pkg.jl](https://pkgdocs.julialang.org/v1/)
- [LibGit2.jl](https://docs.julialang.org/en/v1/stdlib/LibGit2/)
- [LocalRegistry.jl](https://github.com/GunnarFarneback/LocalRegistry.jl)

### Registering a release

Run `PkgBump.registerpatch()`, `registerminor()`, or `registermajor()` from the
package's active project to bump the version, create a pull request, enable
auto-merge, and request Registrator on the merge commit. Authenticate `gh` as a
user allowed to register the package, install Registrator, enable auto-merge,
and start from a clean checkout of the default branch. The default merge method
is squash; pass `merge_method=:merge` or `:rebase` if needed. The default wait
is one hour, adjustable with `timeout` and `poll_interval` (seconds). If the
wait times out or is interrupted, the PR can still merge; request Registrator
manually on its merge commit.

`registerminor` and `registermajor` require nonempty release notes. For a breaking
release, describe the breaking changes and how to upgrade:

```julia
registerminor(; release_notes="Breaking: describe the change and how to upgrade.")
```

Release notes are optional for `registerpatch`.
