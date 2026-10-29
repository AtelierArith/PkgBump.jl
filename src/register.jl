# Run gh in the project directory so it resolves the correct repository.
gh_output(dir, args...) = strip(read(Cmd(`gh $args`; dir=dir), String))
gh_run(dir, args...) = run(Cmd(`gh $args`; dir=dir))

function register(mode; poll_interval::Real=10, timeout::Real=3600, merge_method::Symbol=:squash)
    poll_interval > 0 || throw(ArgumentError("poll_interval must be positive"))
    timeout > 0 || throw(ArgumentError("timeout must be positive"))
    merge_method in (:squash, :merge, :rebase) ||
        throw(ArgumentError("merge_method must be :squash, :merge, or :rebase"))
    project_file = Base.active_project()::String
    dir = dirname(project_file)
    repo = gh_output(dir, "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner")
    base = gh_output(dir, "repo", "view", "--repo", repo, "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name")
    current = LibGit2.branch(LibGit2.GitRepo(dir))
    current == base || error("Check out the default branch $base before registering (current: $current)")
    project = Pkg.Types.read_project(project_file)
    old = something(project.version, v"0.1.0")::VersionNumber
    version = mode == :patch ? Base.nextpatch(old) : mode == :minor ? Base.nextminor(old) : Base.nextmajor(old)
    branch = "pkgbump/bump-to-version-$version"
    bump(mode)
    pr = gh_output(dir, "pr", "view", branch, "--repo", repo, "--json", "url", "--jq", ".url")
    @info "Created pull request" pr
    gh_run(dir, "pr", "merge", pr, "--repo", repo, "--auto", "--$(merge_method)")
    deadline = time() + timeout
    while true
        state = gh_output(dir, "pr", "view", pr, "--repo", repo, "--json", "state", "--jq", ".state")
        if state == "MERGED"
            sha = gh_output(dir, "pr", "view", pr, "--repo", repo, "--json", "mergeCommit", "--jq", ".mergeCommit.oid")
            isempty(sha) && error("Merged PR $pr has no merge commit SHA")
            gh_run(dir, "api", "repos/$repo/commits/$sha/comments", "-f", "body=@JuliaRegistrator register")
            @info "Registrator requested" pr sha
            return pr
        elseif state != "OPEN"
            error("PR $pr is $state; registration was not requested")
        end
        time() >= deadline && error("Timed out waiting for PR $pr; it may still merge automatically")
        sleep(min(poll_interval, max(0, deadline - time())))
    end
end

"""
    registerpatch(; poll_interval=10, timeout=3600, merge_method=:squash)

Bump the active package's patch version, create and automatically merge a PR,
then request registration on its merge commit using the authenticated `gh` user.
Returns the PR URL. Requires a clean checkout of the default branch, `gh`
authentication, Registrator, and auto-merge enabled on the repository. If the
wait times out, the PR may still merge and registration must be requested manually.
"""
registerpatch(; kwargs...) = register(:patch; kwargs...)

"""Like [`registerpatch`](@ref), but bump the minor version."""
registerminor(; kwargs...) = register(:minor; kwargs...)

"""Like [`registerpatch`](@ref), but bump the major version."""
registermajor(; kwargs...) = register(:major; kwargs...)
