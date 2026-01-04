using Test
using Pkg
using LibGit2

using PkgBump: bump, bumppatch, bumpminor, bumpmajor

# Helper: create a temporary Git repository with Project.toml
function create_temp_git_repo(; version="1.0.0")
    tmpdir = mktempdir()

    # Create Project.toml
    project_content = """
    name = "TestPackage"
    uuid = "12345678-1234-1234-1234-123456789012"
    version = "$version"
    """
    project_file = joinpath(tmpdir, "Project.toml")
    write(project_file, project_content)

    # Create src directory and module file
    src_dir = joinpath(tmpdir, "src")
    mkpath(src_dir)
    write(joinpath(src_dir, "TestPackage.jl"), "module TestPackage\nend\n")

    # Initialize Git repository
    repo = LibGit2.init(tmpdir)

    # Set local git config for CI environments where global config may not exist
    LibGit2.with(LibGit2.GitConfig, repo) do cfg
        LibGit2.set!(cfg, "user.name", "Test User")
        LibGit2.set!(cfg, "user.email", "test@example.com")
    end

    # Initial commit
    LibGit2.add!(repo, "Project.toml")
    LibGit2.add!(repo, "src/TestPackage.jl")
    sig = LibGit2.Signature("Test User", "test@example.com")
    LibGit2.commit(repo, "Initial commit"; author=sig, committer=sig)

    return tmpdir, repo
end

# Helper: run function with temporary project activated
function with_temp_project(f, tmpdir)
    original_project = Base.active_project()
    try
        Pkg.activate(tmpdir)
        f()
    finally
        if !isnothing(original_project)
            Pkg.activate(dirname(original_project))
        else
            Pkg.activate()
        end
    end
end

@testset "Git Integration Tests" begin

    @testset "bump with commit=false, push=false" begin
        tmpdir, repo = create_temp_git_repo()
        try
            with_temp_project(tmpdir) do
                # Version update only, no Git operations
                bump(:patch; commit=false, push=false)

                # Verify version was updated
                project = Pkg.Types.read_project(joinpath(tmpdir, "Project.toml"))
                @test project.version == v"1.0.1"

                # Verify changes are not committed (repo is dirty)
                @test LibGit2.isdirty(repo)
            end
        finally
            rm(tmpdir; recursive=true, force=true)
        end
    end

    @testset "bump with commit=true, push=false" begin
        tmpdir, repo = create_temp_git_repo()
        try
            with_temp_project(tmpdir) do
                initial_branch = LibGit2.branch(repo)

                bump(:minor; commit=true, push=false)

                # Verify version was updated
                project = Pkg.Types.read_project(joinpath(tmpdir, "Project.toml"))
                @test project.version == v"1.1.0"

                # Verify we're back on the original branch
                @test LibGit2.branch(repo) == initial_branch

                # Verify new branch exists
                branch_names = String[]
                for ref in LibGit2.GitBranchIter(repo)
                    push!(branch_names, LibGit2.shortname(ref[1]))
                end
                @test "pkgbump/bump-to-version-1.1.0" in branch_names
            end
        finally
            rm(tmpdir; recursive=true, force=true)
        end
    end

    @testset "bump on dirty repository with commit=true should error" begin
        tmpdir, repo = create_temp_git_repo()
        try
            with_temp_project(tmpdir) do
                # Create uncommitted changes
                write(joinpath(tmpdir, "dirty_file.txt"), "uncommitted content")
                LibGit2.add!(repo, "dirty_file.txt")

                # Should error when trying to commit on dirty repo
                @test_throws ErrorException bump(:patch; commit=true, push=false)
            end
        finally
            rm(tmpdir; recursive=true, force=true)
        end
    end

    @testset "bump on dirty repository with commit=false should succeed" begin
        tmpdir, repo = create_temp_git_repo()
        try
            with_temp_project(tmpdir) do
                # Create uncommitted changes
                write(joinpath(tmpdir, "dirty_file.txt"), "uncommitted content")

                # Should succeed with commit=false
                bump(:patch; commit=false, push=false)

                project = Pkg.Types.read_project(joinpath(tmpdir, "Project.toml"))
                @test project.version == v"1.0.1"
            end
        finally
            rm(tmpdir; recursive=true, force=true)
        end
    end

    @testset "exported functions bumppatch/bumpminor/bumpmajor" begin
        for (func, expected_version) in [
            (bumppatch, v"1.0.1"),
            (bumpminor, v"1.1.0"),
            (bumpmajor, v"2.0.0"),
        ]
            tmpdir, repo = create_temp_git_repo()
            try
                with_temp_project(tmpdir) do
                    func(; commit=false, push=false)

                    project = Pkg.Types.read_project(joinpath(tmpdir, "Project.toml"))
                    @test project.version == expected_version
                end
            finally
                rm(tmpdir; recursive=true, force=true)
            end
        end
    end

    @testset "bump major version with commit" begin
        tmpdir, repo = create_temp_git_repo()
        try
            with_temp_project(tmpdir) do
                bump(:major; commit=true, push=false)

                # Verify version was updated
                project = Pkg.Types.read_project(joinpath(tmpdir, "Project.toml"))
                @test project.version == v"2.0.0"

                # Verify branch was created
                branch_names = String[]
                for ref in LibGit2.GitBranchIter(repo)
                    push!(branch_names, LibGit2.shortname(ref[1]))
                end
                @test "pkgbump/bump-to-version-2.0.0" in branch_names
            end
        finally
            rm(tmpdir; recursive=true, force=true)
        end
    end

    @testset "sequential bumps without commit" begin
        tmpdir, repo = create_temp_git_repo()
        try
            with_temp_project(tmpdir) do
                bump(:patch; commit=false, push=false)
                project = Pkg.Types.read_project(joinpath(tmpdir, "Project.toml"))
                @test project.version == v"1.0.1"

                bump(:patch; commit=false, push=false)
                project = Pkg.Types.read_project(joinpath(tmpdir, "Project.toml"))
                @test project.version == v"1.0.2"

                bump(:minor; commit=false, push=false)
                project = Pkg.Types.read_project(joinpath(tmpdir, "Project.toml"))
                @test project.version == v"1.1.0"
            end
        finally
            rm(tmpdir; recursive=true, force=true)
        end
    end

end
