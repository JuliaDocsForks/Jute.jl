using Documenter
using Jute


makedocs(
    modules = [Jute],
    format = :html,
    sitename = "Jute.jl",
    authors = "Bogdan Opanchuk",
    pages = [
        "Home" => "index.md",
        "Manual" => "manual.md",
        "Public API" => "public.md",
        "Internals" => "internals.md",
        "Version history" => "history.md",
    ],
)

deploydocs(
    julia = "nightly",
    repo = "github.com/fjarri/Jute.jl.git",
    target = "build",
    deps = nothing,
    make = nothing,
)
