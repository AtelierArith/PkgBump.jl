using Test

using Aqua
using JET

using PkgBump

@testset "Code quality (Aqua.jl)" begin
    Aqua.test_all(PkgBump, deps_compat=false)
end

if VERSION >= v"1.10"
    @testset "Code linting (JET.jl)" begin
        JET.test_package(PkgBump; target_modules=(PkgBump,))
    end
end

@testset "PkgBump.jl" begin
    # Write your tests here.
end
