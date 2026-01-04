using Test
using Pkg

import PkgBump: updateversion!, updateversion,
                updatepatch!, updateminor!, updatemajor!,
                updatepatch, updateminor, updatemajor

# Helper function to create a temporary Project.toml
function create_temp_project(; version=nothing, name="TestProject")
    content = """
    name = "$name"
    uuid = "12345678-1234-1234-1234-123456789012"
    """
    if !isnothing(version)
        content *= """version = "$version"\n"""
    end
    return content
end

@testset "Version Update Unit Tests" begin

    @testset "updateversion! - patch mode" begin
        mktempdir() do tmpdir
            project_file = joinpath(tmpdir, "Project.toml")
            write(project_file, create_temp_project(version="1.2.3"))

            project = Pkg.Types.read_project(project_file)
            updateversion!(project, project_file, :patch)

            # Verify in-memory project object was updated
            @test project.version == v"1.2.4"
        end
    end

    @testset "updateversion! - minor mode" begin
        mktempdir() do tmpdir
            project_file = joinpath(tmpdir, "Project.toml")
            write(project_file, create_temp_project(version="1.2.3"))

            project = Pkg.Types.read_project(project_file)
            updateversion!(project, project_file, :minor)

            @test project.version == v"1.3.0"
        end
    end

    @testset "updateversion! - major mode" begin
        mktempdir() do tmpdir
            project_file = joinpath(tmpdir, "Project.toml")
            write(project_file, create_temp_project(version="1.2.3"))

            project = Pkg.Types.read_project(project_file)
            updateversion!(project, project_file, :major)

            @test project.version == v"2.0.0"
        end
    end

    @testset "updateversion! - version is nothing (initialization)" begin
        mktempdir() do tmpdir
            # Test each mode when version is nothing
            for (mode, expected) in [
                (:patch, v"0.1.1"),  # 0.1.0 -> 0.1.1
                (:minor, v"0.2.0"),  # 0.1.0 -> 0.2.0
                (:major, v"1.0.0"),  # 0.1.0 -> 1.0.0
            ]
                project_file = joinpath(tmpdir, "Project_$(mode).toml")
                write(project_file, create_temp_project(version=nothing))

                project = Pkg.Types.read_project(project_file)
                @test isnothing(project.version)

                updateversion!(project, project_file, mode)
                @test project.version == expected
            end
        end
    end

    @testset "updateversion (file path version)" begin
        mktempdir() do tmpdir
            project_file = joinpath(tmpdir, "Project.toml")
            write(project_file, create_temp_project(version="2.0.0"))

            project = updateversion(project_file, :patch)
            @test project.version == v"2.0.1"
        end
    end

    @testset "convenience functions updatepatch/updateminor/updatemajor" begin
        mktempdir() do tmpdir
            # updatepatch test
            project_file = joinpath(tmpdir, "Project_patch.toml")
            write(project_file, create_temp_project(version="1.0.0"))
            project = updatepatch(project_file)
            @test project.version == v"1.0.1"

            # updateminor test
            project_file = joinpath(tmpdir, "Project_minor.toml")
            write(project_file, create_temp_project(version="1.0.0"))
            project = updateminor(project_file)
            @test project.version == v"1.1.0"

            # updatemajor test
            project_file = joinpath(tmpdir, "Project_major.toml")
            write(project_file, create_temp_project(version="1.0.0"))
            project = updatemajor(project_file)
            @test project.version == v"2.0.0"
        end
    end

    @testset "in-place convenience functions updatepatch!/updateminor!/updatemajor!" begin
        mktempdir() do tmpdir
            # updatepatch! test
            project_file = joinpath(tmpdir, "Project_patch.toml")
            write(project_file, create_temp_project(version="1.0.0"))
            project = Pkg.Types.read_project(project_file)
            updatepatch!(project, project_file)
            @test project.version == v"1.0.1"

            # updateminor! test
            project_file = joinpath(tmpdir, "Project_minor.toml")
            write(project_file, create_temp_project(version="1.0.0"))
            project = Pkg.Types.read_project(project_file)
            updateminor!(project, project_file)
            @test project.version == v"1.1.0"

            # updatemajor! test
            project_file = joinpath(tmpdir, "Project_major.toml")
            write(project_file, create_temp_project(version="1.0.0"))
            project = Pkg.Types.read_project(project_file)
            updatemajor!(project, project_file)
            @test project.version == v"2.0.0"
        end
    end

    @testset "version boundary cases" begin
        mktempdir() do tmpdir
            test_cases = [
                (v"0.0.0", :patch, v"0.0.1"),
                (v"0.0.99", :patch, v"0.0.100"),
                (v"0.99.99", :minor, v"0.100.0"),
                (v"99.99.99", :major, v"100.0.0"),
                (v"0.0.0", :minor, v"0.1.0"),
                (v"0.0.0", :major, v"1.0.0"),
            ]

            for (input_ver, mode, expected) in test_cases
                project_file = joinpath(tmpdir, "Project_$(input_ver)_$(mode).toml")
                write(project_file, create_temp_project(version=string(input_ver)))
                project = updateversion(project_file, mode)
                @test project.version == expected
            end
        end
    end

end
