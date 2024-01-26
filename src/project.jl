function updateversion!(project::Pkg.Types.Project, project_file::AbstractString, mode::Symbol)
	isnothing(project.version) && (project.version = v"0.1.0")
	mode === :patch && (project.version = Base.nextpatch(project.version))
	mode === :minor && (project.version = Base.nextminor(project.version))
	mode === :major && (project.version = Base.nextmajor(project.version))
	Pkg.Types.write_project(project, project_file)
end

updatepatch!(project::Pkg.Types.Project, project_file) = updateversion!(project, project_file, :patch)
updateminor!(project::Pkg.Types.Project, project_file) = updateversion!(project, project_file, :minor)
updatemajor!(project::Pkg.Types.Project, project_file) = updateversion!(project, project_file, :major)

function updateversion(project_file::AbstractString, mode::Symbol)
	project = Pkg.Types.read_project(project_file)
	updateversion!(project, project_file, mode)
	return project
end

updatepatch(project_file::AbstractString) = updateversion(project_file, :patch)
updateminor(project_file::AbstractString) = updateversion(project_file, :minor)
updatemajor(project_file::AbstractString) = updateversion(project_file, :major)
