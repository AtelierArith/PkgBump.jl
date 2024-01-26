using Test

using Aqua
using JET

using PkgBump

@testset "Aqua" begin
    Aqua.test_all(PkgBump, deps_compat=false)
end

@testset "JET" begin
    JET.report_package(PkgBump)
end

@testset "PkgBump.jl" begin
    # Write your tests here.
end
