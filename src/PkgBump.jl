module PkgBump

import Pkg
using LibGit2

export bumpmajor, bumpminor, bumppatch

"""
    updateversion!(project::Pkg.Types.Project, project_file::AbstractString, mode::Symbol)

Update the version of the given project file according to the specified `mode` (:patch, :minor, :major).
The new version is written directly to the `project_file`.
"""
function updateversion!(
    project::Pkg.Types.Project,
    project_file::AbstractString,
    mode::Symbol,
)
    isnothing(project.version) && (project.version = v"0.1.0")
    mode === :patch && (project.version = Base.nextpatch(project.version::VersionNumber))
    mode === :minor && (project.version = Base.nextminor(project.version::VersionNumber))
    mode === :major && (project.version = Base.nextmajor(project.version::VersionNumber))
    Pkg.Types.write_project(project, project_file)
end

"""
    updatepatch!(project::Pkg.Types.Project, project_file::AbstractString)

Increment the patch version of the given project and write the changes to the `project_file`.
"""
function updatepatch!(project::Pkg.Types.Project, project_file::AbstractString)
    updateversion!(project, project_file, :patch)
end

"""
    updateminor!(project::Pkg.Types.Project, project_file::AbstractString)

Increment the minor version of the given project and write the changes to the `project_file`.
"""
function updateminor!(project::Pkg.Types.Project, project_file::AbstractString)
    updateversion!(project, project_file, :minor)
end

"""
    updatemajor!(project::Pkg.Types.Project, project_file)

Increment the major version of the given project and write the changes to the `project_file`.
"""
function updatemajor!(project::Pkg.Types.Project, project_file::AbstractString)
    updateversion!(project, project_file, :major)
end

"""
    updateversion(project_file::AbstractString, mode::Symbol) -> Pkg.Types.Project

Read the project from `project_file`, update its version according to `mode`, and write the changes back.
Returns the updated project.
"""
function updateversion(project_file::AbstractString, mode::Symbol)
    project = Pkg.Types.read_project(project_file)
    updateversion!(project, project_file, mode)
    return project
end

"""
    updatepatch(project_file::AbstractString)

Update the patch version of the project defined in `project_file`.
"""
updatepatch(project_file::AbstractString) = updateversion(project_file, :patch)

"""
    updateminor(project_file::AbstractString)

Update the minor version of the project defined in `project_file`.
"""
updateminor(project_file::AbstractString) = updateversion(project_file, :minor)

"""
    updatemajor(project_file::AbstractString)

Update the major version of the project defined in `project_file`.
"""
updatemajor(project_file::AbstractString) = updateversion(project_file, :major)

"""
    bump(mode::Symbol; commit=true, push=true)

Bumps the version of the current active project according to `mode`, commits the change to a new branch, and pushes the branch to the remote repository.
"""
function bump(mode::Symbol; commit::Bool=true, push::Bool=true)::Nothing
    mode ∈ [:patch, :minor, :major] ||
        error("Expected one of [:patch, :minor, :major], actual $(mode)")

    # ensure project_file should be a type of String
    project_file = Base.active_project()::String
    project_dir = dirname(project_file)
    repo = LibGit2.GitRepo(project_dir)
    current_branch = LibGit2.branch(repo)

    if commit
        !LibGit2.isdirty(repo) || error("Registry directory is dirty. Stash or commit files.")
    end

    project = Pkg.Types.read_project(project_file)
    current_version = project.version

    updateversion!(project, project_file, mode)
    new_version = project.version
    @info "Update version from $(current_version) to $(new_version)"

    try
        if commit
            branch = "pkgbump/bump-to-version-$(new_version)"
            @info "Switch branch from $(current_branch) to $branch"
            LibGit2.branch!(repo, branch)

            target_file = relpath(Base.active_project(), LibGit2.path(repo))
            @info "Stage $(target_file)"
            LibGit2.add!(repo, target_file)

            @info "Commit changes..."
            LibGit2.commit(repo, "Bump to version $(new_version)")
        else
            @info "Skipped git commit ... since commit keyword is set to $(commit)"
        end

        if push
            @info "Push to remote..."
            run(`git -C $(project_dir) push --set-upstream origin $branch`)
        else
            @info "Skipped git push ... since push keyword is set to $(push)"
        end
    catch e
        println("Failed to commit or push due to error $e")
    finally    
        @info "Switch back to $(current_branch)"
        LibGit2.branch!(repo, curretn_branch)
    end

    @info "Done"
end

"""
    bumppatch(;kwargs)

Bump the patch version of the current active project, commit, and push the changes.
"""
bumppatch(;kwargs...) = bump(:patch; kwargs...)

"""
    bumpminor(;kwargs)

Bump the minor version of the current active project, commit, and push the changes.
"""
bumpminor(;kwargs...) = bump(:minor; kwargs...)

"""
    bumpmajor(;kwargs)

Bump the major version of the current active project, commit, and push the changes.
"""
bumpmajor(;kwargs...) = bump(:major; kwargs...)

end # module
