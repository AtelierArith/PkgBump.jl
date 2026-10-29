using Test
using PkgBump

# A real local repository and remote exercise Git while a small gh executable
# supplies deterministic GitHub responses without making network requests.
function with_register_fixture(f; state="MERGED", sha="abc123", fail="", base=nothing)
    tmpdir, repo = create_temp_git_repo()
    try
        mktempdir() do temp
            remote = joinpath(temp, "remote.git")
            run(pipeline(`git init --bare $remote`; stdout=devnull, stderr=devnull))
            run(`git -C $tmpdir remote add origin $remote`)
            branch = LibGit2.branch(repo)
            run(pipeline(`git -C $tmpdir push -u origin $branch`; stdout=devnull, stderr=devnull))
            fake = joinpath(temp, "gh")
            logfile = joinpath(temp, "calls")
            write(fake, """
            #!/bin/sh
            printf '%s\\n' "\$*" >> "\$GH_TEST_LOG"
            if [ -n "\$GH_TEST_FAIL" ] && [ "\$1 \$2" = "\$GH_TEST_FAIL" ]; then exit 1; fi
            case "\$1 \$2" in
              'repo view') case "\$*" in *defaultBranchRef*) echo "\$GH_TEST_BASE" ;; *) echo owner/repo ;; esac ;;
              'pr create') echo https://github.com/owner/repo/pull/1 ;;
              'pr view') case "\$*" in *mergeCommit*) echo "\$GH_TEST_SHA" ;; *"--json url"*) echo https://github.com/owner/repo/pull/1 ;; *) echo "\$GH_TEST_STATE" ;; esac ;;
            esac
            """)
            chmod(fake, 0o755)
            withenv("PATH" => "$temp:$(ENV["PATH"])", "GH_TEST_LOG" => logfile,
                    "GH_TEST_BASE" => something(base, branch), "GH_TEST_STATE" => state,
                    "GH_TEST_SHA" => sha, "GH_TEST_FAIL" => fail) do
                with_temp_project(tmpdir) do
                    f(tmpdir, logfile)
                end
            end
        end
    finally
        close(repo)
        rm(tmpdir; recursive=true, force=true)
    end
end

@testset "Registration" begin
    @testset "Version selection and registration" begin
        for (register, version, method) in ((registerpatch, "1.0.1", :squash),
                                             (registerminor, "1.1.0", :merge),
                                             (registermajor, "2.0.0", :rebase))
            with_register_fixture() do dir, log
                @test register(; poll_interval=0.01, timeout=1, merge_method=method) ==
                      "https://github.com/owner/repo/pull/1"
                calls = read(log, String)
                @test occursin("pr create --head pkgbump/bump-to-version-$version", calls)
                @test occursin("--auto --$method", calls)
                @test occursin("api repos/owner/repo/commits/abc123/comments -f body=@JuliaRegistrator register", calls)
                ref = "pkgbump/bump-to-version-$(version):Project.toml"
                @test occursin("version = \"$version\"", read(`git -C $dir show $ref`, String))
            end
        end
    end

    @testset "Closed PR, missing merge commit, and timeout do not register" begin
        for (state, sha) in (("CLOSED", "abc123"), ("MERGED", ""), ("OPEN", "abc123"))
            with_register_fixture(; state, sha) do _, log
                @test_throws ErrorException registerpatch(; poll_interval=0.01, timeout=0.03)
                @test !occursin("api repos/", read(log, String))
            end
        end
    end

    @testset "Failed PR creation stops registration" begin
        with_register_fixture(; fail="pr create") do _, log
            @test_throws ProcessFailedException registerpatch(; poll_interval=0.01, timeout=1)
            calls = read(log, String)
            @test !occursin("pr merge", calls)
            @test !occursin("api repos/", calls)
        end
    end

    @testset "GitHub errors are reported" begin
        for failure in ("pr merge", "api repos/owner/repo/commits/abc123/comments")
            with_register_fixture(; fail=failure) do _, log
                @test_throws ProcessFailedException registerpatch(; poll_interval=0.01, timeout=1)
                if failure == "pr merge"
                    @test !occursin("api repos/", read(log, String))
                end
            end
        end
    end

    @testset "Bump creates a PR without requesting registration" begin
        with_register_fixture() do _, log
            bumppatch()
            calls = read(log, String)
            @test occursin("pr create --head pkgbump/bump-to-version-1.0.1", calls)
            @test !occursin("pr merge", calls)
            @test !occursin("api repos/", calls)
        end
    end

    @testset "Validate options before changes" begin
        @test_throws ArgumentError registerpatch(; poll_interval=0)
        @test_throws ArgumentError registerpatch(; timeout=0)
        @test_throws ArgumentError registerpatch(; merge_method=:invalid)
    end

    @testset "Require default branch" begin
        with_register_fixture(; base="another-branch") do dir, log
            @test_throws ErrorException registerpatch()
            @test !occursin("pr create", read(log, String))
            @test Pkg.Types.read_project(joinpath(dir, "Project.toml")).version == v"1.0.0"
        end
    end
end
