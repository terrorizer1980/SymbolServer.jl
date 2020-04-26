@static if VERSION < v"1.1"
    const PackageEntry = Vector{Dict{String,Any}}
else
    using Pkg.Types: PackageEntry
end

"""
    manifest(c::Pkg.Types.Context)
Retrieves the manifest of a Context.
"""
manifest(c::Pkg.Types.Context) = c.env.manifest

"""
    project(c::Pkg.Types.Context)
Retrieves the project of a Context.
"""
project(c::Pkg.Types.Context) = c.env.project

"""
    isinproject(context, package::Union{String,UUID})
Checks whether a package is in the dependencies of a given context, e.g. is directly loadable.
"""
function isinproject end

"""
    isinmanifest(context, package::Union{String,UUID})
Checks whether a package is in the manifest of a given context, e.g. is either directly loadable or is a dependency of an loadable package.
"""
function isinmanifest end

@static if VERSION < v"1.1"
    isinmanifest(context::Pkg.Types.Context, module_name::String) = module_name in keys(manifest(context))
    isinmanifest(context::Pkg.Types.Context, uuid::UUID) = any(get(p[1], "uuid", "") == string(uuid) for (u, p) in manifest(context))
    isinmanifest(manifest::Dict{String,Any}, uuid::AbstractString) = any(get(p[1], "uuid", "") == uuid for (u, p) in manifest)
    isinmanifest(manifest::Dict{String,Any}, uuid::UUID) = isinmanifest(manifest, string(uuid))

    isinproject(context::Pkg.Types.Context, package_name::String) = haskey(deps(project(context)), package_name)
    isinproject(context::Pkg.Types.Context, package_uuid::UUID) = any(u == package_uuid for (n, u) in deps(project(context)))

    function packageuuid(c::Pkg.Types.Context, name::String)
        for pkg in manifest(c)
            if first(pkg) == name
                return UUID(last(pkg)[1]["uuid"])
            end
        end
    end
    packageuuid(pkg::Pair{Any,Any}) = last(pkg) isa String ? UUID(last(pkg)) : UUID(first(last(pkg))["uuid"])
    packageuuid(pkg::Pair{String,Any}) = last(pkg) isa String ? UUID(last(pkg)) : UUID(first(last(pkg))["uuid"])

    function packagename(c::Pkg.Types.Context, uuid)
        for (n, p) in c.env.manifest
            if get(first(p), "uuid", "") == string(uuid)
                return n
            end
        end
        return nothing
    end
    function packagename(manifest::Dict{String,Any}, uuid::String)
        for (n, p) in manifest
            if get(first(p), "uuid", "") == string(uuid)
                return n
            end
        end
        return nothing
    end
    packagename(manifest::Dict{String,Any}, uuid::UUID) = packagename(manifest, string(uuid))

    function deps(uuid::UUID, c::Pkg.Types.Context)
        if any(p[1]["uuid"] == string(uuid) for (n, p) in manifest(c))
            return manifest(c)[string(uuid)][1].deps
        else
            return Dict{Any,Any}()
        end
    end
    deps(d::Dict{String,Any}) = get(d, "deps", Dict{String,Any}())
    deps(pe::PackageEntry) = get(pe[1], "deps", Dict{String,Any}())
    path(pe::PackageEntry) = get(pe[1], "path", nothing)
    version(pe::PackageEntry) = get(pe[1], "version", nothing)

    function frommanifest(c::Pkg.Types.Context, uuid)
        for (n, p) in c.env.manifest
            if get(first(p), "uuid", "") == string(uuid)
                return p
            end
        end
        return nothing
    end
    function frommanifest(manifest, uuid)
        for (n, p) in manifest
            if get(first(p), "uuid", "") == string(uuid)
                return p
            end
        end
        return nothing
    end
    function get_filename_from_name(manifest, uuid)
        temp_var = [p[2][1] for p in manifest if get(p[2][1], "uuid", "") == string(uuid)]
        isempty(temp_var) && return nothing

        pkg_info = first(temp_var)

        name_for_cash_file = if get(pkg_info, "git-tree-sha1", nothing)!==nothing
            "-normal-" * string(pkg_info["git-tree-sha1"])
        elseif get(pkg_info, "path", nothing)!==nothing
            # We have a deved package, we use the hash of the folder name
            "-deved-" * string(bytes2hex(sha256(pkg_info["path"])))
        else
            # We have a stdlib, we use the uuid
            "-stdlib-" * string(uuid)
        end

        return "Julia-$VERSION-$(Sys.ARCH)-$name_for_cash_file.jstore"
    end
    is_package_deved(manifest, uuid) = get(first([p[2][1] for p in manifest if get(p[2][1], "uuid", "") == string(uuid)]), "path", "") != ""
else
    isinmanifest(context::Pkg.Types.Context, module_name::String) = any(p.name == module_name for (u, p) in manifest(context))
    isinmanifest(context::Pkg.Types.Context, uuid::UUID) = haskey(manifest(context), uuid)
    isinmanifest(manifest::Dict{UUID, PackageEntry}, uuid::UUID) = haskey(manifest, uuid)

    isinproject(context::Pkg.Types.Context, package_name::String) = haskey(deps(project(context)), package_name)
    isinproject(context::Pkg.Types.Context, package_uuid::UUID) = any(u == package_uuid for (n, u) in deps(project(context)))

    function packageuuid(c::Pkg.Types.Context, name::String)
        for pkg in manifest(c)
            if last(pkg).name == name
                return first(pkg)
            end
        end
    end
    packageuuid(pkg::Pair{String,UUID}) = last(pkg)
    packageuuid(pkg::Pair{UUID,PackageEntry}) = first(pkg)
    packagename(c::Pkg.Types.Context, uuid::UUID) = manifest(c)[uuid].name
    packagename(manifest::Dict{UUID, PackageEntry}, uuid::UUID) = manifest[uuid].name

    function deps(uuid::UUID, c::Pkg.Types.Context)
        if haskey(manifest(c), uuid)
            return deps(manifest(c)[uuid])
        else
            return Dict{String,Base.UUID}()
        end
    end
    deps(pe::PackageEntry) = pe.deps
    deps(proj::Pkg.Types.Project) = proj.deps
    deps(pkg::Pair{String,UUID}, c::Pkg.Types.Context) = deps(packageuuid(pkg), c)
    path(pe::PackageEntry) = pe.path
    version(pe::PackageEntry) = pe.version
    frommanifest(c::Pkg.Types.Context, uuid) = manifest(c)[uuid]
    frommanifest(manifest::Dict{UUID, PackageEntry}, uuid) = manifest[uuid]

    function get_filename_from_name(manifest, uuid)
        haskey(manifest, uuid) || return nothing

        pkg_info = manifest[uuid]

        tree_hash = VERSION >= v"1.3" ? pkg_info.tree_hash : get(pkg_info.other, "git-tree-sha1", nothing)

        name_for_cash_file = if tree_hash!==nothing
            # We have a normal package, we use the tree hash
            "-normal-" * string(tree_hash)
        elseif pkg_info.path!==nothing
            # We have a deved package, we use the hash of the folder name
            "-deved-" * string(bytes2hex(sha256(pkg_info.path)))
        else
            # We have a stdlib, we use the uuid
            "-stdlib-" * string(uuid)
        end

        return "Julia-$VERSION-$(Sys.ARCH)-$name_for_cash_file.jstore"
    end

    is_package_deved(manifest, uuid) = manifest[uuid].path!==nothing
end

function sha2_256_dir(path, sha = sha = zeros(UInt8, 32))
    (uperm(path) & 0x04) != 0x04 && return
    startswith(path, ".") && return
    if isfile(path) && endswith(path, ".jl")
        s1 = open(path) do f
            sha2_256(f)
        end
        sha .+= s1
    elseif isdir(path)
        for f in readdir(path)
            sha = sha2_256_dir(joinpath(path, f), sha)
        end
    end
    return sha
end

function sha_pkg(pe::PackageEntry)
    path(pe) isa String && isdir(path(pe)) && isdir(joinpath(path(pe), "src")) ? sha2_256_dir(joinpath(path(pe), "src")) : nothing
end

function _doc(object)
    binding = Base.Docs.aliasof(object, typeof(object))
    !(binding isa Base.Docs.Binding) && return ""
    sig = Union{}
    if Base.Docs.defined(binding)
        result = Base.Docs.getdoc(Base.Docs.resolve(binding), sig)
        result === nothing || return result
    end
    results, groups = Base.Docs.DocStr[], Base.Docs.MultiDoc[]
    # Lookup `binding` and `sig` for matches in all modules of the docsystem.
    for mod in Base.Docs.modules
        dict = Base.Docs.meta(mod)
        if haskey(dict, binding)
            multidoc = dict[binding]
            push!(groups, multidoc)
            for msig in multidoc.order
                sig <: msig && push!(results, multidoc.docs[msig])
            end
        end
    end
    if isempty(groups)
        alias = Base.Docs.aliasof(binding)
        alias == binding ? "" : _doc(alias, sig)
    elseif isempty(results)
        for group in groups, each in group.order
            push!(results, group.docs[each])
        end
    end
    md = try
        Base.Docs.catdoc(map(Base.Docs.parsedoc, results)...)
    catch err
        nothing
    end
    return md === nothing ? "" : string(md)
end

_lookup(vr::FakeUnion, depot::EnvStore, cont = false) = nothing
_lookup(vr::FakeTypeName, depot::EnvStore, cont = false) = _lookup(vr.name, depot, cont)
_lookup(vr::FakeUnionAll, depot::EnvStore, cont = false) = _lookup(vr.body, depot, cont)
function _lookup(vr::VarRef, depot::EnvStore, cont = false)
    if vr.parent === nothing
        if haskey(depot, vr.name)
            val = depot[vr.name]
            if cont && val isa VarRef
                return _lookup(val, depot, cont)
            else
                return val
            end
        else
            return nothing
        end
    else
        par = _lookup(vr.parent, depot)
        if par !== nothing && par isa ModuleStore && haskey(par, vr.name)
            val = par[vr.name]
            if cont && val isa VarRef
                return _lookup(val, depot, cont)
            else
                return val
            end
        else
            return nothing
        end
    end
end

function issubmodof(m::Module, M::Module)
    if m == M
        return true
    elseif parentmodule(m) === m
        return false
    elseif parentmodule(m) == M
        return true
    else
        return issubmodof(parentmodule(m), M)
    end
end



function Base.print(io::IO, f::FunctionStore)
    println(io, f.name, " is a Function.")
    nm = length(f.methods)
    println(io, "# $nm method", nm == 1 ? "" : "s", "for function ", f.name)
    for i = 1:nm
        print(io, "[$i] ")
        println(io, f.methods[i])
    end
end

function Base.print(io::IO, m::MethodStore)
    print(io, m.name, "(")
    for i = 1:length(m.sig)
        if m.sig[i][1] != Symbol("#unused#")
            print(io, m.sig[i][1])
        end
        print(io, "::", m.sig[i][2])
        i != length(m.sig) && print(io, ", ")
    end
    print(io, ")")
end

function Base.print(io::IO, t::DataTypeStore)
    print(io, t.name, " <: ", t.super)
    for i = 1:length(t.fieldnames)
        print(io, "\n  ", t.fieldnames[i], "::", t.types[i])
    end
end

Base.print(io::IO, m::ModuleStore) = print(io, m.name)
Base.print(io::IO, x::GenericStore) = print(io, x.name, "::", x.typ)

extends_methods(f) = false
extends_methods(f::FunctionStore) = f.name != f.extends
get_top_module(vr::VarRef) = vr.parent === nothing ? vr.name : get_top_module(vr.parent)
