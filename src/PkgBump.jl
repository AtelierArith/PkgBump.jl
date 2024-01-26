module PkgBump

import Pkg
using LibGit2

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

function updatepatch!(project::Pkg.Types.Project, project_file)
    updateversion!(project, project_file, :patch)
end
function updateminor!(project::Pkg.Types.Project, project_file)
    updateversion!(project, project_file, :minor)
end
function updatemajor!(project::Pkg.Types.Project, project_file)
    updateversion!(project, project_file, :major)
end

function updateversion(project_file::AbstractString, mode::Symbol)
    project = Pkg.Types.read_project(project_file)
    updateversion!(project, project_file, mode)
    return project
end

updatepatch(project_file::AbstractString) = updateversion(project_file, :patch)
updateminor(project_file::AbstractString) = updateversion(project_file, :minor)
updatemajor(project_file::AbstractString) = updateversion(project_file, :major)

function bump(mode::Symbol)
    project_file = Base.active_project()
    project_dir = dirname(project_file)
    repo = LibGit2.GitRepo(project_dir)
    !LibGit2.isdirty(repo) || error("Registry directory is dirty. Stash or commit files.")

    project = Pkg.Types.read_project(project_file)
    current_version = project.version
    updateversion!(project, project_file, mode)
    new_version = project.version
    @info "$(current_version) => $(new_version)"
    # the `project_file` is now updated
    # we add/stage `project_file`
    LibGit2.add!(repo, project_file)
    branch = "pkgbump/bump-to-version-$(new_version)"
    LibGit2.branch!(repo, branch)
    LibGit2.commit(repo, "Bump to version $(new_version)")
    #LibGit2.push(repo, remoteurl=url)
    @info "push to remote..."
    run(`git -C $(project_dir) push --set-upstream origin $branch`)
    @info "Done"
end

bumppatch() = bump(:patch)
bumpminor() = bump(:minor)
bumpmajor() = bump(:major)

end # module
