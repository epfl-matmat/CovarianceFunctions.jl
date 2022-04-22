############################ stationary kernels ################################
# using LinearAlgebraExtensions: difference
# notation:
# x, y inputs
# τ = x-y difference of inputs
# r = norm(x-y) norm of τ
# r² = r^2
(k::StationaryKernel)(x, y) = k(difference(x, y)) # if the two argument signature is not defined, default to stationary
(k::IsotropicKernel)(x, y) = k(euclidean2(x, y)) # if the two argument signature is not defined, default to isotropic
(k::IsotropicKernel)(τ) = k(sum(abs2, τ)) # if only the scalar argument form is defined, must be isotropic

############################# constant kernel ##################################
# can be used to rescale existing kernels
# IDEA: Allow Matrix-valued constant
struct Constant{T} <: IsotropicKernel{T}
    c::T
    function Constant(c, check::Bool = true)
        if check && !ispsd(c)
            throw(DomainError("Constant is not positive semi-definite: $c"))
        end
        new{typeof(c)}(c)
    end
end
@functor Constant

# isisotropic(::Constant) = true
# ismercer(k::Constant) = ispsd(k.c)
# Constant(c) = Constant{typeof(c)}(c)

# should type of constant field and r agree? what promotion is necessary?
# do we need the isotropic/ stationary evaluation, if we overwrite the mercer one?
(k::Constant)(r²) = k.c # stationary / isotropic
(k::Constant)(x, y) = k.c # mercer

#################### standard exponentiated quadratic kernel ###################
struct ExponentiatedQuadratic{T} <: IsotropicKernel{T} end
const EQ = ExponentiatedQuadratic
@functor EQ
EQ() = EQ{Union{}}() # defaults to "bottom" type since it doesn't have any parameters
(k::EQ)(r²::Number) = exp(-r²/2)

########################## rational quadratic kernel ###########################
struct RationalQuadratic{T} <: IsotropicKernel{T}
    α::T # relative weighting of small and large length scales
    RationalQuadratic{T}(α) where T = (0 < α) ? new(α) : throw(DomainError("α not positive"))
end
const RQ = RationalQuadratic
@functor RQ
RQ(α::Real) = RQ{typeof(α)}(α)

(k::RQ)(r²::Number) = (1 + r² / (2*k.α))^-k.α

parameters(k::RQ) = [k.α]
nparameters(::RQ) = 1

########################### exponential kernel #################################
struct Exponential{T} <: IsotropicKernel{T} end
const Exp = Exponential
Exp() = Exp{Union{}}()

(k::Exp)(r²::Number) = exp(-sqrt(r²))

############################ γ-exponential kernel ##############################
struct GammaExponential{T<:Real} <: IsotropicKernel{T}
    γ::T
    GammaExponential{T}(γ) where {T} = (0 ≤ γ ≤ 2) ? new(γ) : throw(DomainError("γ not in [0,2]"))
end
const γExp = GammaExponential
@functor γExp
γExp(γ::T) where T = γExp{T}(γ)

(k::γExp)(r²::Number) = exp(-r²^(k.γ/2) / 2)

########################### white noise kernel #################################
struct Delta{T} <: IsotropicKernel{T} end
@functor Delta
const δ = Delta
δ() = δ{Union{}}()

(k::δ)(r²) = all(iszero, r²) ? one(eltype(r²)) : zero(eltype(r²))
function (k::δ)(x, y)
    T = promote_type(eltype(x), eltype(y))
    (x == y) ? one(T) : zero(T) # IDEA: if we checked (x === y) could incorporate noise variance for vector inputs -> EquivDelta?
end
############################ Matern kernel #####################################
# IDEA: use rational types to dispatch to MaternP evaluation, i.e. 5//2 -> MaternP(3)
# seems k/2 are representable exactly in floating point?
struct Matern{T} <: IsotropicKernel{T}
    ν::T
    Matern{T}(ν) where T = (0 < ν) ? new(ν) : throw(DomainError("ν = $ν is negative"))
end
@functor Matern
Matern(ν::T) where {T} = Matern{T}(ν)

# IDEA: could have value type argument to dispatch p parameterization
function (k::Matern)(r²::Number)
    if iszero(r²) # helps with ForwardDiff-differentiability at zero
        one(r²)
    else
        ν = k.ν
        r = sqrt(2ν*r²)
        2^(1-ν) / gamma(ν) * r^ν * besselk(ν, r)
    end
end

################# Matern kernel with ν = p + 1/2 where p ∈ ℕ ###################
struct MaternP{T} <: IsotropicKernel{T}
    p::Int
    MaternP{T}(p::Int) where T = 0 ≤ p ? new(p) : throw(DomainError("p = $p is negative"))
end

MaternP(p::Int = 0) = MaternP{Union{}}(p)
MaternP(k::Matern) = MaternP(floor(Int, k.ν)) # project Matern to closest MaternP

function (k::MaternP)(r²::Number)
    if iszero(r²) # helps with ForwardDiff-differentiability at zero
        return one(r²)
    else
        p = k.p
        val = zero(r²)
        r = sqrt((2p+1)*r²)
        for i in 0:p
            val += (factorial(p+i)/(factorial(i)*factorial(p-i))) * (2r)^(p-i) # putting @fastmath here leads to NaN with ForwardDiff
        end
        return val *= exp(-r) * (factorial(p)/factorial(2p))
    end
end

########################### cosine kernel ######################################
# interesting because it allows negative co-variances
# it is a valid stationary kernel,
# because it is the inverse Fourier transform of point measure at μ (delta distribution)
struct CosineKernel{T, V<:Union{T, AbstractVector{T}}} <: StationaryKernel{T}
    μ::V
end
const Cosine = CosineKernel
@functor Cosine

# IDEA: trig-identity -> low-rank gramian
# NOTE: this is the only stationary non-isotropic kernel so far
(k::CosineKernel)(τ) = cos(2π * dot(k.μ, τ))
(k::CosineKernel)(x, y) = k(difference(x, y))
(k::CosineKernel{<:Real, <:Real})(τ) = cos(2π * k.μ * sum(τ))

####################### spectral mixture kernel ################################
# can be seen as product kernel of Constant, Cosine, ExponentiatedQuadratic
Spectral(w::Real, μ, l) = prod((w, Cosine(μ), ARD(EQ(), l))) # 2π^2/σ.^2)
SpectralMixture(w::AbstractVector, μ, l) = sum(Spectral.(w, μ, l))
const SM = SpectralMixture

############################ Cauchy Kernel #####################################
# there is something else in the literature with the same name ...
struct Cauchy{T} <: IsotropicKernel{T} end
@functor Cauchy
Cauchy() = Cauchy{Union{}}()
(k::Cauchy)(r²::Number) = inv(1+r²) # π is not necessary, we are not normalizing

# for spectroscopy
PseudoVoigt(α) = α*EQ() + (1-α)*Cauchy()

###################### Inverse Multi-Quadratic  ################################
# seems formally similar to Cauchy, Cauchy is equal to power of IMQ
struct InverseMultiQuadratic{T} <: IsotropicKernel{T}
    c::T
end
@functor InverseMultiQuadratic
(k::InverseMultiQuadratic)(r²::Number) = 1/√(r² + k.c^2)
