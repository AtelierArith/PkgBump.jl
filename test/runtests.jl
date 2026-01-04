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
    include("test_version_update.jl")
    include("test_error_handling.jl")
    include("test_git_integration.jl")
end
