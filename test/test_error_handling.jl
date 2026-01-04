using Test
using Pkg

import PkgBump: bump, updateversion

@testset "Error Handling Tests" begin

    @testset "Invalid mode argument in bump()" begin
        # Note: These tests require a valid Git repository context
        # We test the validation logic by checking error messages
        @test_throws ErrorException bump(:invalid_mode; commit=false, push=false)
        @test_throws ErrorException bump(:PATCH; commit=false, push=false)  # uppercase
        @test_throws ErrorException bump(:Patch; commit=false, push=false)  # mixed case
        @test_throws ErrorException bump(:foo; commit=false, push=false)
    end

    @testset "Non-existent project file" begin
        @test_throws Exception updateversion("/nonexistent/path/Project.toml", :patch)
    end

    @testset "Invalid Project.toml format" begin
        mktempdir() do tmpdir
            project_file = joinpath(tmpdir, "Project.toml")
            write(project_file, "invalid toml content {{{")

            @test_throws Exception updateversion(project_file, :patch)
        end
    end

    @testset "Missing required fields in Project.toml" begin
        mktempdir() do tmpdir
            # Project.toml without name field
            project_file = joinpath(tmpdir, "Project.toml")
            write(project_file, """
            uuid = "12345678-1234-1234-1234-123456789012"
            version = "1.0.0"
            """)

            # Pkg.Types.read_project should still work (name is optional in some contexts)
            # but let's verify it doesn't crash
            project = Pkg.Types.read_project(project_file)
            @test project.version == v"1.0.0"
        end
    end

    @testset "Empty Project.toml" begin
        mktempdir() do tmpdir
            project_file = joinpath(tmpdir, "Project.toml")
            write(project_file, "")

            # Should be able to read empty project
            project = Pkg.Types.read_project(project_file)
            @test isnothing(project.version)
        end
    end

end
