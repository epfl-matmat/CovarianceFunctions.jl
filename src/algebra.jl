############################# kernel algebra ###################################
# TODO: overwrite differentiation, integration
# TODO: simplify by using traits design, isisotropic, isstationary, ...
# TODO: then, change from MercerKernel to AbstractKernel, also with traits
# TODO: separable sum gramian
# TODO: (Separable) Sum and Product could be one definition with meta programming
################################ Product #######################################
# TODO: constructors which merge products and sums
struct Product{T, AT<:Tuple{Vararg{MercerKernel}}} <: MercerKernel{T}
    args::AT
    function Product(k::Tuple{Vararg{MercerKernel}})
        T = promote_type(eltype.(k)...)
        new{T, typeof(k)}(k)
    end
end
(P::Product)(τ) = prod(k->k(τ), P.args) # TODO could check for isotropy here
(P::Product)(x, y) = prod(k->k(x, y), P.args)
# (P::Product)(x, y) = isstationary(P) ? P(difference(x, y)) : prod(k->k(x, y), P.args)
Product(k::MercerKernel...) = Product(k)
Base.:*(k::MercerKernel...) = Product(k)
Base.:*(c::Number, k::MercerKernel) = Constant(c) * k
Base.:*(k::MercerKernel, c::Number) = Constant(c) * k

################################### Sum ########################################
struct Sum{T, AT<:Tuple{Vararg{MercerKernel}}} <: MercerKernel{T}
    args::AT
    function Sum(k::Tuple{Vararg{MercerKernel}})
        T = promote_type(eltype.(k)...)
        new{T, typeof(k)}(k)
    end
end
(S::Sum)(τ) = sum(k->k(τ), S.args) # should only be called if S is stationary
(S::Sum)(x, y) = sum(k->k(x, y), S.args)
# (S::Sum)(τ) = isstationary(S) ? sum(k->k(τ), S.args) : error("One argument evaluation not possible for non-stationary kernel")
# (S::Sum)(x, y) = isstationary(S) ? S(difference(x, y)) : sum(k->k(x, y), S.args)
Sum(k::MercerKernel...) = Sum(k)
Base.:+(k::MercerKernel...) = Sum(k)
Base.:+(k::MercerKernel, c::Number) = k + Constant(c)
Base.:+(c::Number, k::MercerKernel) = k + Constant(c)

################################## Power #######################################
struct Power{T, K<:MercerKernel{T}} <: MercerKernel{T}
    k::K
    p::Int
end
(P::Power)(τ) = P.k(τ)^P.p
(P::Power)(x, y) = P.k(x, y)^P.p
Base.:^(k::MercerKernel, p::Int) = Power(k, p)

############################ Separable Product #################################
using LinearAlgebraExtensions: LazyGrid
# TODO: this could subsume Separable in multi
# product kernel, but separately evaluates component kernels on different parts of the input
struct SeparableProduct{T, K<:Tuple{Vararg{MercerKernel}}} <: MercerKernel{T}
    args::K # kernel for input covariances
    function SeparableProduct(k::Tuple{Vararg{MercerKernel}})
        T = promote_type(eltype.(k)...)
        new{T, typeof(k)}(k)
    end
end
# both x and y have to be vectors of inputs to individual kernels
# TODO: check input lengths
# could also consist of tuples ... so restricting to AbstractVector might not be good
function (K::SeparableProduct)(x, y)
    val = one(eltype(K))
    for (i, k) in enumerate(K.args)
        val *= k(x[i], y[i])
    end
    return val
end
# if we had kernel input type, could compare with eltype(X)
function gramian(K::SeparableProduct, X::LazyGrid, Y::LazyGrid)
    kronecker((gramian(kxy...) for kxy in zip(K.args, X.args, Y.args))...)
end
# TODO: if points are not on a grid, can still evaluate dimensions separately,
# and take elementwise product. Might lead to efficiency gains
############################### Separable Sum ##################################
# what about separable sums? do they give rise to kronecker sums? yes!
struct SeparableSum{T, K<:Tuple{Vararg{MercerKernel}}} <: MercerKernel{T}
    args::K # kernel for input covariances
    function SeparableSum(k::Tuple{Vararg{MercerKernel}})
        T = promote_type(eltype.(k)...)
        new{T, typeof(k)}(k)
    end
end
# TODO: check input lengths
function (K::SeparableSum)(x, y)
    val = zero(eltype(K))
    for (i, k) in enumerate(K.args)
        val += k(x[i], y[i])
    end
    return val
end

function gramian(K::SeparableSum, X::LazyGrid, Y::LazyGrid)
    ⊕((gramian(kxy...) for kxy in zip(K.args, X.args, Y.args))...)
end

# convenient constructor
# e.g. separable(*, k1, k2)
separable(::typeof(*), k::MercerKernel...) = SeparableProduct(k)
separable(::typeof(+), k::MercerKernel...) = SeparableSum(k)
# d-separable product of k
function separable(::typeof(^), k::MercerKernel, d::Integer)
    SeparableProduct(tuple((k for _ in 1:d)...))
end

######################## Kernel Input Transfomations ###########################
############################## symmetric kernel ################################
# make this useable for multi-dimensional inputs!
# in more dimensions, could have more general axis of symmetry
struct Symmetric{T, K<:MercerKernel} <: MercerKernel{T}
    k::K # kernel to be symmetrized
    z::T # center
end
# const Sym = Symmetric
Symmetric(k::MercerKernel{T}) where T = Symmetric(k, zero(T))

# for 1D axis symmetry
function (k::Symmetric)(x, y)
    x -= k.z; y -= k.z;
    k.k(x, y) + k.k(-x, y)
end

######################## Kernel output transformations #########################
############################## rescaled kernel #################################
# TODO: should be called DiagonalRescaling in analogy to the matrix case
# diagonal rescaling of covariance functions
# generalizes multiplying by constant kernel to multiplying by function
struct VerticalRescaling{T, K<:MercerKernel{T}, F} <: MercerKernel{T}
    k::K
    a::F
end
(k::VerticalRescaling)(x, y) = k.a(x) * k.k(x, y) * k.a(y)
# TODO: preserve structure if k.k is stationary and x, y are regular grids,
# since that introduces Toeplitz structure
# function gramian(k::VerticalRescaling, x::AbstractVector, y::AbstractVector)
#     # Diagonal(k.a.(x)) * gramian(k.k, x, y) * Diagonal(k.a.(y)))
#     LazyProduct(Diagonal(k.a.(x)), gramian(k.k, x, y), Diagonal(k.a.(y))))
# end

# normalizes an arbitary kernel so that k(x,x) = 1
normalize(k::MercerKernel) = VerticalRescaling(k, x->1/√k(x, x))

############################## Derivative ######################################
# TODO: specializations for Isotropic, Stationary?
struct Derivative{T, K<:MercerKernel{T}} <: MercerKernel{T}
    k::K
end

function (k::Derivative)(x::Real, y::Real)
    FD.derivative(y->FD.derivative(x->k.k(x, y), x), y)
end

# struct ANOVA{T, K} <: MercerKernel{T}
#     k::K
# end
#
# function (A::ANOVA)(x, y)
#     for (i, k) in enumerate(A.k)
#         k(x[i], y[i])
#     end
# end