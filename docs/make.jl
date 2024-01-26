using PkgBump
using Documenter

DocMeta.setdocmeta!(PkgBump, :DocTestSetup, :(using PkgBump); recursive=true)

makedocs(;
    modules=[PkgBump],
    authors="Satoshi Terasaki <terasakisatoshi.math@gmail.com> and contributors",
    sitename="PkgBump.jl",
    format=Documenter.HTML(;
        canonical="https://atelierarith.github.io/PkgBump.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/atelierarith/PkgBump.jl",
    devbranch="main",
)
