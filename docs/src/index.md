```@meta
CurrentModule = PkgBump
```

# PkgBump

Documentation for [PkgBump](https://github.com/terasakisatoshi/PkgBump.jl).

## Description
`PkgBump.jl` automatically increments the version in a Julia Project file. Package developers only have to run one of the three functions:

```julia
# Roughly speaking
bumppatch: v"x.y.z" -> v"x.y.(z+1)"
bumpminor: v"x.y.z" -> v"x.(y+1).0"
bumpmajor: v"x.y.z" -> v"(x+1).0.0"
```

Internally, we use the `Base.nextpatch`, `Base.nextminor`, `Base.nextmajor` functions respectively.

```@index
```

```@autodocs
Modules = [PkgBump]
```
