# Run gh in the project directory so it resolves the correct repository.
gh_output(dir, args...) = strip(read(Cmd(`gh $args`; dir=dir), String))
gh_run(dir, args...) = run(Cmd(`gh $args`; dir=dir))

# Keep the request URL as the lookup key, so checking again never bumps or posts.
function registration_status(dir, comment_url; poll_interval, timeout)
    isfinite(poll_interval) && poll_interval > 0 ||
        throw(ArgumentError("poll_interval must be finite and positive"))
    isfinite(timeout) && timeout >= 0 ||
        throw(ArgumentError("timeout must be finite and nonnegative"))
    request = match(
        r"^https://github\.com/([^/]+/[^/]+)/commit/([0-9a-fA-F]+)#commitcomment-([0-9]+)$",
        comment_url,
    )
    isnothing(request) && throw(
        ArgumentError("Expected a GitHub commit comment URL including #commitcomment-ID"),
    )
    repo, sha, comment_id = request.captures
    # Ignore older replies and other authors, including quoted bot messages.
    query =
        "[.[] | select(.id > $comment_id and .user.login == \"JuliaRegistrator\")] | " *
        "sort_by(.id) | first | if . == null then empty else (.html_url + \"\\n\" + .body) | @base64 end"
    deadline = time() + timeout
    while true
        encoded_reply = gh_output(dir, "api", "repos/$repo/commits/$sha/comments",
            "--paginate", "--jq", query)
        if !isempty(encoded_reply)
            # gh applies --jq to each page. Decode the first matching reply only;
            # base64 keeps multiline bodies and later pages from mixing together.
            reply = String(base64decode(first(split(encoded_reply, '\n'))))
            parts = split(reply, '\n'; limit=2)
            reply_url = String(first(parts))
            body = length(parts) == 2 ? String(parts[2]) : ""
            registration = match(
                r"^Registration pull request (?:created|updated):[^\n]*?(https://[^\s)]+/pull/[0-9]+)",
                body,
            )
            registry_pr =
                isnothing(registration) ? nothing : String(registration[1]::AbstractString)
            status = isnothing(registry_pr) ? :replied : :created
            result =
                (; status, comment_url=String(comment_url), reply_url, registry_pr, body)
            if status == :created
                @info "Registrator created registration pull request (registry merge pending)" comment_url reply_url registry_pr
            else
                @warn "Registrator replied without confirming a registration pull request; review its response" comment_url reply_url body
            end
            return result
        end
        if time() >= deadline
            @warn "No Registrator reply yet; check this comment or call registrationstatus again. Do not bump again to retry." comment_url
            return (; status=:pending, comment_url=String(comment_url), reply_url=nothing,
                registry_pr=nothing, body="")
        end
        sleep(min(poll_interval, max(0, deadline - time())))
    end
end

"""
    registrationstatus(comment_url; poll_interval=10, timeout=0)

Check Registrator's response to a GitHub commit comment URL (including
`#commitcomment-ID`). This only reads comments; it never bumps or posts again.
Works from any directory. By default checks once; set `timeout` in seconds to
wait for a reply. Logs links and returns a named tuple with `status`,
`comment_url`, `reply_url`, `registry_pr`, and the response `body`.

`status` is `:pending` if no reply was found, `:created` if Registrator confirmed
creation of a registry PR, or `:replied` for another response (inspect `body`).
`:created` does not mean the registry PR has merged or registration is complete.
"""
function registrationstatus(comment_url::AbstractString; poll_interval::Real=10,
    timeout::Real=0)
    return registration_status(pwd(), comment_url; poll_interval, timeout)
end

function register(mode; poll_interval::Real=10, timeout::Real=3600,
    merge_method::Symbol=:squash,
    release_notes::AbstractString="", registrator_timeout::Real=120)
    mode in (:minor, :major) && isempty(strip(release_notes)) &&
        throw(ArgumentError("release_notes must be nonempty for minor and major releases"))
    isfinite(poll_interval) && poll_interval > 0 ||
        throw(ArgumentError("poll_interval must be finite and positive"))
    timeout > 0 || throw(ArgumentError("timeout must be positive"))
    merge_method in (:squash, :merge, :rebase) ||
        throw(ArgumentError("merge_method must be :squash, :merge, or :rebase"))
    isfinite(registrator_timeout) && registrator_timeout >= 0 ||
        throw(ArgumentError("registrator_timeout must be finite and nonnegative"))
    project_file = Base.active_project()::String
    dir = dirname(project_file)
    repo =
        gh_output(dir, "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner")
    base = gh_output(
        dir,
        "repo",
        "view",
        repo,
        "--json",
        "defaultBranchRef",
        "--jq",
        ".defaultBranchRef.name",
    )
    current = LibGit2.branch(LibGit2.GitRepo(dir))
    current == base ||
        error("Check out the default branch $base before registering (current: $current)")
    project = Pkg.Types.read_project(project_file)
    old = something(project.version, v"0.1.0")::VersionNumber
    version =
        mode == :patch ? Base.nextpatch(old) :
        mode == :minor ? Base.nextminor(old) : Base.nextmajor(old)
    branch = "pkgbump/bump-to-version-$version"
    bump(mode)
    pr = gh_output(
        dir,
        "pr",
        "view",
        branch,
        "--repo",
        repo,
        "--json",
        "url",
        "--jq",
        ".url",
    )
    @info "Created pull request" pr
    gh_run(dir, "pr", "merge", pr, "--repo", repo, "--auto", "--$(merge_method)")
    deadline = time() + timeout
    while true
        state = gh_output(
            dir,
            "pr",
            "view",
            pr,
            "--repo",
            repo,
            "--json",
            "state",
            "--jq",
            ".state",
        )
        if state == "MERGED"
            sha = gh_output(
                dir,
                "pr",
                "view",
                pr,
                "--repo",
                repo,
                "--json",
                "mergeCommit",
                "--jq",
                ".mergeCommit.oid",
            )
            isempty(sha) && error("Merged PR $pr has no merge commit SHA")
            body = "@JuliaRegistrator register"
            isempty(strip(release_notes)) ||
                (body *= "\n\nRelease notes:\n\n" * release_notes)
            comment_url = gh_output(dir, "api", "repos/$repo/commits/$sha/comments",
                "-f", "body=$body", "--jq", ".html_url")
            @info "Registrator requested" pr sha comment_url
            try
                registration_status(
                    dir,
                    comment_url;
                    poll_interval,
                    timeout=registrator_timeout,
                )
            catch err
                err isa ProcessFailedException || rethrow()
                @warn "Registrator request was posted, but checking its response failed. Use registrationstatus to check again; do not bump again." comment_url exception=(
                    err,
                    catch_backtrace(),
                )
            end
            return pr
        elseif state != "OPEN"
            error("PR $pr is $state; registration was not requested")
        end
        time() >= deadline &&
            error("Timed out waiting for PR $pr; it may still merge automatically")
        sleep(min(poll_interval, max(0, deadline - time())))
    end
end

"""
    registerpatch(; poll_interval=10, timeout=3600, merge_method=:squash,
                  release_notes="", registrator_timeout=120)

Bump the active package's patch version, create and automatically merge a PR,
then request registration on its merge commit using the authenticated `gh` user.
Returns the PR URL. Requires a clean checkout of the default branch, `gh`
authentication, Registrator, and auto-merge enabled on the repository. If the
wait times out, the PR may still merge and registration must be requested manually.
Use `release_notes` to include notes in the Registrator request.

Logs the posted comment URL, then waits up to `registrator_timeout` seconds
for Registrator and logs its reply and registry PR URL. Set this timeout to zero
to check once. Missing replies or response-check failures warn without posting
again. Check later with [`registrationstatus`](@ref) using the logged comment URL.
This checks PR creation only, not completion of registry review or merging.
"""
registerpatch(; kwargs...) = register(:patch; kwargs...)

"""Like [`registerpatch`](@ref), but bump the minor version. Nonempty `release_notes` are required."""
registerminor(; kwargs...) = register(:minor; kwargs...)

"""Like [`registerpatch`](@ref), but bump the major version. Nonempty `release_notes` are required."""
registermajor(; kwargs...) = register(:major; kwargs...)
