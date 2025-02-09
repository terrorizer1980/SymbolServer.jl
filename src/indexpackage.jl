module SymbolServer

using Pkg, SHA
using Base: UUID

current_package_name = Symbol(ARGS[1])
current_package_version = VersionNumber(ARGS[2])
current_package_uuid = UUID(ARGS[3])
current_package_treehash = ARGS[4]

@info "Indexing package $current_package_name $current_package_version..."

# This path will always be mounted in the docker container in which we are running
store_path = "/symcache"

current_package_versionwithoutplus = replace(string(current_package_version), '+'=>'_')
cache_package_folder_path = joinpath(store_path, "v1", "packages", string(uppercase(string(current_package_name)[1])), "$(current_package_name)_$current_package_uuid")
filename_without_extension = "v$(current_package_versionwithoutplus)_$current_package_treehash"
filename_with_extension = "$filename_without_extension.jstore"
cache_path = joinpath(cache_package_folder_path, filename_with_extension)
cache_path_compressed = joinpath(cache_package_folder_path, "$filename_without_extension.tar.gz")

mkpath(cache_package_folder_path)

module LoadingBay end

try
    Pkg.add(name=string(current_package_name), version=current_package_version)
catch err
    @info "Could not install package, exiting"
    exit(20)
end

# TODO Make the code below ONLY write a cache file for the package we just added here.
include("faketypes.jl")
include("symbols.jl")
include("utils.jl")
include("serialize.jl")
using .CacheStore

# Load package
m = try
    LoadingBay.eval(:(import $current_package_name))
    getfield(LoadingBay, current_package_name)
catch e
    @info "Could not load package, exiting."
    exit(10)
end

# Get the symbols
env = getenvtree([current_package_name])
symbols(env, m)

 # Strip out paths
modify_dirs(env[current_package_name], f -> modify_dir(f, pkg_src_dir(Base.loaded_modules[Base.PkgId(current_package_uuid, string(current_package_name))]), "PLACEHOLDER"))

# There's an issue here - @enum used within CSTParser seems to add a method that is introduced from Enums.jl...

Pkg.PlatformEngines.probe_platform_engines!()

mktempdir() do path
    # Write them to a file
    open(joinpath(path, filename_with_extension), "w") do io
        CacheStore.write(io, Package(string(current_package_name), env[current_package_name], current_package_uuid, nothing))
    end

    # cp(joinpath(path, filename_with_extension), cache_path)
    Pkg.PlatformEngines.package(path, cache_path_compressed)
end

@info "Finished indexing."

# We are exiting with a custom error code to indicate success. This allows
# the parent process to distinguish between a successful run and one
# where the package exited the process.
exit(37)

end
