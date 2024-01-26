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
    mode === :patch && (project.version = Base.nextpatch(project.version))
    mode === :minor && (project.version = Base.nextminor(project.version))
    mode === :major && (project.version = Base.nextmajor(project.version))
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
    bump(mode::Symbol)

Bumps the version of the current active project according to `mode`, commits the change to a new branch, and pushes the branch to the remote repository.
"""
function bump(mode::Symbol)
    mode ∈ [:patch, :minor, :major] ||
        error("Expected one of [:patch, :minor, :major], actual $(mode)")

    # ensure project_file should be a type of String
    project_file::String = Base.active_project()
    project_dir = dirname(project_file)
    repo = LibGit2.GitRepo(project_dir)
    !LibGit2.isdirty(repo) || error("Registry directory is dirty. Stash or commit files.")

    project = Pkg.Types.read_project(project_file)
    current_version = project.version

    updateversion!(project, project_file, mode)
    @info "Update version from $(current_version) to $(new_version)"
    new_version = project.version

    @info "Commit changes..."
    LibGit2.add!(repo, project_file)
    branch = "pkgbump/bump-to-version-$(new_version)"
    LibGit2.branch!(repo, branch)
    LibGit2.commit(repo, "Bump to version $(new_version)")

    @info "Push to remote..."
    run(`git -C $(project_dir) push --set-upstream origin $branch`)

    @info "Done"
end

"""
    bumppatch()

Bump the patch version of the current active project, commit, and push the changes.
"""
bumppatch() = bump(:patch)

"""
    bumpminor()

Bump the minor version of the current active project, commit, and push the changes.
"""
bumpminor() = bump(:minor)

"""
    bumpmajor()

Bump the major version of the current active project, commit, and push the changes.
"""
bumpmajor() = bump(:major)

end # module
