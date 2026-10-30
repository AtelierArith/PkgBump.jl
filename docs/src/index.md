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

## Follow a registration request

`registerpatch()`, `registerminor()`, and `registermajor()` log the posted
Registrator comment URL, wait for its response, and display the registry PR URL
when available. The returned URL is still the version-bump PR. Use
`registrator_timeout` (default 120 seconds) to adjust the response wait separately
from the PR merge `timeout`.

Check an existing request without bumping or posting again:

```julia
url = "https://github.com/OWNER/REPO/commit/SHA#commitcomment-ID"
result = registrationstatus(url)
# Or wait for a response:
result = registrationstatus(url; timeout=120)
```

The result contains `status`, `comment_url`, `reply_url`, `registry_pr`, and
`body`. A `:pending` status means no response was found; `:replied` means a bot
response needs review; `:created` confirms a registry PR was created, but does
not confirm its merge. Missing replies and response-check errors during
`registerpatch()` produce warnings with the request URL. Use that URL to check
again rather than invoking another version bump.

```@index
```

```@autodocs
Modules = [PkgBump]
```
