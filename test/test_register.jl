using Test
using PkgBump
using Base64

# A real local repository and remote exercise Git while a small gh executable
# supplies deterministic GitHub responses without making network requests.
const REQUEST_URL = "https://github.com/owner/repo/commit/abc123#commitcomment-100"
const REPLY_URL = "https://github.com/owner/repo/commit/abc123#commitcomment-101"
const REGISTRY_PR = "https://github.com/JuliaRegistries/General/pull/42"
const SUCCESS_REPLY = "$REPLY_URL\nRegistration pull request created: [JuliaRegistries/General/42]($REGISTRY_PR)"

function with_register_fixture(f; state="MERGED", sha="abc123", fail="", base=nothing,
    reply=SUCCESS_REPLY, pending_polls=0, check_fail=false)
    tmpdir, repo = create_temp_git_repo()
    try
        mktempdir() do temp
            remote = joinpath(temp, "remote.git")
            run(pipeline(`git init --bare $remote`; stdout=devnull, stderr=devnull))
            run(`git -C $tmpdir remote add origin $remote`)
            branch = LibGit2.branch(repo)
            run(
                pipeline(
                    `git -C $tmpdir push -u origin $branch`;
                    stdout=devnull,
                    stderr=devnull,
                ),
            )
            fake = joinpath(temp, "gh")
            logfile = joinpath(temp, "calls")
            polls = joinpath(temp, "polls")
            write(polls, "0")
            write(
                fake,
                """
    #!/bin/sh
    printf '%s\\n' "\$*" >> "\$GH_TEST_LOG"
    if [ -n "\$GH_TEST_FAIL" ] && [ "\$1 \$2" = "\$GH_TEST_FAIL" ]; then exit 1; fi
    case "\$1 \$2" in
      'repo view') case "\$*" in *--repo*) exit 2 ;; *defaultBranchRef*) echo "\$GH_TEST_BASE" ;; *) echo owner/repo ;; esac ;;
      'pr create') echo https://github.com/owner/repo/pull/1 ;;
      'api repos/owner/repo/commits/abc123/comments')
        case "\$*" in
          *"-f body="*) echo "\$GH_TEST_REQUEST_URL" ;;
          *)
            if [ "\$GH_TEST_CHECK_FAIL" = true ]; then exit 1; fi
            n=\$(cat "\$GH_TEST_POLLS")
            n=\$((n + 1))
            printf '%s' "\$n" > "\$GH_TEST_POLLS"
            if [ "\$n" -gt "\$GH_TEST_PENDING_POLLS" ]; then printf '%s\\n' "\$GH_TEST_REPLY"; fi ;;
        esac ;;
      'pr view') case "\$*" in *mergeCommit*) echo "\$GH_TEST_SHA" ;; *"--json url"*) echo https://github.com/owner/repo/pull/1 ;; *) echo "\$GH_TEST_STATE" ;; esac ;;
    esac
    """,
            )
            chmod(fake, 0o755)
            withenv("PATH" => "$temp:$(ENV["PATH"])", "GH_TEST_LOG" => logfile,
                "GH_TEST_BASE" => something(base, branch), "GH_TEST_STATE" => state,
                "GH_TEST_SHA" => sha, "GH_TEST_FAIL" => fail,
                "GH_TEST_REQUEST_URL" => REQUEST_URL,
                "GH_TEST_REPLY" => (
                    reply isa AbstractVector ? join(base64encode.(reply), "\n") :
                    isempty(reply) ? "" : base64encode(reply)
                ),
                "GH_TEST_POLLS" => polls, "GH_TEST_PENDING_POLLS" => string(pending_polls),
                "GH_TEST_CHECK_FAIL" => string(check_fail)) do
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
                @test register(;
                    poll_interval=0.01,
                    timeout=1,
                    merge_method=method,
                    release_notes="Breaking: migration details.",
                ) ==
                      "https://github.com/owner/repo/pull/1"
                calls = read(log, String)
                @test occursin("pr create --head pkgbump/bump-to-version-$version", calls)
                @test occursin("--auto --$method", calls)
                @test occursin(
                    "api repos/owner/repo/commits/abc123/comments -f body=@JuliaRegistrator register",
                    calls,
                )
                ref = "pkgbump/bump-to-version-$(version):Project.toml"
                @test occursin(
                    "version = \"$version\"",
                    read(`git -C $dir show $ref`, String),
                )
            end
        end
    end

    @testset "Release notes are sent to Registrator" begin
        with_register_fixture() do _, log
            registerminor(;
                poll_interval=0.01,
                timeout=1,
                release_notes="Breaking: upgrade dependency.\nSee migration guide.",
            )
            calls = read(log, String)
            @test occursin(
                "Release notes:\n\nBreaking: upgrade dependency.\nSee migration guide.",
                calls,
            )
        end
    end

    @testset "Minor and major releases require nonblank notes" begin
        for register in (registerminor, registermajor), notes in (nothing, "", "  \n ")
            with_register_fixture() do dir, log
                if isnothing(notes)
                    @test_throws ArgumentError register()
                else
                    @test_throws ArgumentError register(; release_notes=notes)
                end
                @test !isfile(log)
                @test Pkg.Types.read_project(joinpath(dir, "Project.toml")).version ==
                      v"1.0.0"
            end
        end
    end

    @testset "Closed PR, missing merge commit, and timeout do not register" begin
        for (state, sha) in (("CLOSED", "abc123"), ("MERGED", ""), ("OPEN", "abc123"))
            with_register_fixture(; state, sha) do _, log
                @test_throws ErrorException registerpatch(;
                    poll_interval=0.01,
                    timeout=0.03,
                )
                @test !occursin("api repos/", read(log, String))
            end
        end
    end

    @testset "Failed PR creation stops registration" begin
        with_register_fixture(; fail="pr create") do _, log
            @test_throws ProcessFailedException registerpatch(;
                poll_interval=0.01,
                timeout=1,
            )
            calls = read(log, String)
            @test !occursin("pr merge", calls)
            @test !occursin("api repos/", calls)
        end
    end

    @testset "GitHub errors are reported" begin
        for failure in ("pr merge", "api repos/owner/repo/commits/abc123/comments")
            with_register_fixture(; fail=failure) do _, log
                @test_throws ProcessFailedException registerpatch(;
                    poll_interval=0.01,
                    timeout=1,
                )
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
        for invalid in (-1, Inf, NaN)
            @test_throws ArgumentError registerpatch(; registrator_timeout=invalid)
        end
    end

    @testset "Require default branch" begin
        with_register_fixture(; base="another-branch") do dir, log
            @test_throws ErrorException registerpatch()
            @test !occursin("pr create", read(log, String))
            @test Pkg.Types.read_project(joinpath(dir, "Project.toml")).version == v"1.0.0"
        end
    end
end

@testset "Registrator responses" begin
    @testset "The posted comment URL is logged before waiting for a reply" begin
        with_register_fixture(; reply="") do _, log
            logs, result = Test.collect_test_logs() do
                registerpatch(; registrator_timeout=0)
            end
            request_index =
                findfirst(entry -> entry.message == "Registrator requested", logs)
            warning_index = findfirst(
                entry -> startswith(entry.message, "No Registrator reply yet"),
                logs,
            )
            @test !isnothing(request_index)
            @test !isnothing(warning_index)
            @test request_index < warning_index
            @test logs[request_index].kwargs[:comment_url] == REQUEST_URL
            @test logs[warning_index].kwargs[:comment_url] == REQUEST_URL
            @test result == "https://github.com/owner/repo/pull/1"
            @test count("-f body=@JuliaRegistrator register", read(log, String)) == 1
        end
    end

    @testset "Check an existing request without bumping or posting" begin
        with_register_fixture() do _, log
            result =
                @test_logs (:info, r"Registrator created registration pull request") registrationstatus(
                    REQUEST_URL,
                )
            @test result.status == :created
            @test result.comment_url == REQUEST_URL
            @test result.reply_url == REPLY_URL
            @test result.registry_pr == REGISTRY_PR
            @test occursin("Registration pull request created:", result.body)
            calls = read(log, String)
            @test !occursin("pr create", calls)
            @test !occursin("-f body=", calls)
            @test occursin("--paginate --jq", calls)
        end
    end

    @testset "Multiple pages keep response bodies separate" begin
        later_reply = "$REPLY_URL\nError while registering package."
        with_register_fixture(; reply=[SUCCESS_REPLY, later_reply]) do _, _
            result = registrationstatus(REQUEST_URL)
            @test result.status == :created
            @test result.body == split(SUCCESS_REPLY, '\n'; limit=2)[2]
            @test result.registry_pr == REGISTRY_PR
        end
    end

    @testset "Delayed reply is polled without reposting" begin
        with_register_fixture(; pending_polls=1) do _, log
            @test registerpatch(; poll_interval=0.01, timeout=1, registrator_timeout=1) ==
                  "https://github.com/owner/repo/pull/1"
            calls = read(log, String)
            @test count("-f body=@JuliaRegistrator register", calls) == 1
            @test count("--paginate --jq", calls) == 2
        end
    end

    @testset "Missing reply has links and can be checked later" begin
        with_register_fixture(; reply="") do _, log
            result = @test_logs (:warn, r"No Registrator reply yet") registrationstatus(
                REQUEST_URL,
            )
            @test result.status == :pending
            @test result.comment_url == REQUEST_URL
            @test isnothing(result.reply_url)
            @test isnothing(result.registry_pr)
            @test count("--paginate --jq", read(log, String)) == 1
            @test (@test_logs (:warn, r"No Registrator reply yet") registrationstatus(
                REQUEST_URL;
                poll_interval=0.01,
                timeout=0.03,
            )).status == :pending
            withenv("GH_TEST_REPLY" => base64encode(SUCCESS_REPLY)) do
                @test registrationstatus(REQUEST_URL).status == :created
            end
            @test !occursin("-f body=", read(log, String))
        end
    end

    @testset "Errors and unexpected bot replies preserve the response" begin
        for body in ("Error while registering package.\nVersion already exists.",
            "Please review https://github.com/example/repo/pull/1")
            with_register_fixture(; reply="$REPLY_URL\n$body") do _, _
                result =
                    @test_logs (:warn, r"Registrator replied without confirming") registrationstatus(
                        REQUEST_URL,
                    )
                @test result.status == :replied
                @test result.reply_url == REPLY_URL
                @test result.body == body
                @test isnothing(result.registry_pr)
            end
        end
    end

    @testset "Response checks fail without submitting again" begin
        with_register_fixture(; check_fail=true) do _, log
            @test registerpatch(; registrator_timeout=0) ==
                  "https://github.com/owner/repo/pull/1"
            @test count("-f body=@JuliaRegistrator register", read(log, String)) == 1
            @test_throws ProcessFailedException registrationstatus(REQUEST_URL)
        end
        with_register_fixture(; reply="") do _, log
            @test registerpatch(; registrator_timeout=0) ==
                  "https://github.com/owner/repo/pull/1"
            @test count("-f body=@JuliaRegistrator register", read(log, String)) == 1
        end
    end

    @testset "Validate lookup options without GitHub requests" begin
        with_register_fixture() do _, log
            @test_throws ArgumentError registrationstatus(
                "https://github.com/owner/repo/pull/1",
            )
            for invalid in (-1, Inf, NaN)
                @test_throws ArgumentError registrationstatus(REQUEST_URL; timeout=invalid)
            end
            for invalid in (0, -1, Inf, NaN)
                @test_throws ArgumentError registrationstatus(
                    REQUEST_URL;
                    poll_interval=invalid,
                )
            end
            @test !isfile(log)
        end
    end
end
