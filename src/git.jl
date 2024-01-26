function push2remote()
    project_file = Base.active_project()
    project_dir = dirname(project_file)
    repo = LibGit2.GitRepo(project_dir)
    !LibGit2.isdirty(repo) || error("Registry directory is dirty. Stash or commit files.")

    project = Pkg.Types.read_project(project_file)
    current_version = project.version
    updatepatch!(project, project_file)
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