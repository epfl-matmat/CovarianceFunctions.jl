################################################################################
# assumes A is a matrix of matrices or factorizations each of which has size d by d
struct BlockFactorization{T, AT<:AbstractMatrix{<:AbstractMatOrFac{T}}, U, V} <: Factorization{T}
    A::AT
    nindices::U
    mindices::V
    tol::T
end
const StridedBlockFactorization = BlockFactorization{<:Any, <:Any, <:StepRange, <:StepRange}
const default_tol = 1e-8
# default tolerance is 1e-6
function BlockFactorization(A::AbstractMatrix, nind, mind; tol::Real = default_tol)
    BlockFactorization(A, nind, mind, tol)
end
function BlockFactorization(A::AbstractMatrix, d::Int; tol = default_tol)
    BlockFactorization(A, 1:d:d*size(A, 1)+1, 1:d:d*size(A, 2)+1; tol = tol)
end
function BlockFactorization(A::AbstractMatrix; tol = default_tol)
    BlockFactorization(A, checksquare(A[1]), tol = tol) # this assumes it is strided
end
Base.size(B::BlockFactorization, i::Int) = (1 ≤ i ≤ 2) ? size(B)[i] : 1
Base.size(B::BlockFactorization) = B.nindices[end]-1, B.mindices[end]-1
function Base.Matrix(B::BlockFactorization)
    C = zeros(eltype(B), size(B))
    for j in 1:size(B.A, 2)
        jd = B.mindices[j] : B.mindices[j+1]-1
        for i in 1:size(B.A, 1)
            id = B.nindices[i] : B.nindices[i+1]-1
            M = Matrix(B.A[i, j])
            C[id, jd] .= M
        end
    end
    return C
end
# TODO: test this
function Base.getindex(B::StridedBlockFactorization, i::Int, j::Int)
    ni, nj = mod1(i, B.nindices.step), mod1(j, B.mindices.step)
    ri, rj = rem(i, B.nindices.step)+1, rem(j, B.mindices.step)+1
    return B.A[ni, nj][ri, rj]
end

# function Base.getindex(B::StridedBlockFactorization, i::Int, j::Int)
#     ni, nj = mod1(i, B.nindices.step), mod1(j, B.mindices.step)
#     ri, rj = rem(i, B.nindices.step)+1, rem(j, B.mindices.step)+1
#     return B.A[ni, nj][ri, rj]
# end

############################## matrix multiplication ###########################
function Base.:*(B::BlockFactorization, x::AbstractVector)
    y = zeros(eltype(x), size(B, 1))
    mul!(y, B, x)
end
Base.:*(B::BlockFactorization, X::AbstractMatrix) = mul!(zeros(eltype(x), size(B, 1), size(X, 2)), B, X)

function LinearAlgebra.mul!(y::AbstractVector, B::BlockFactorization, x::AbstractVector, α::Real = 1, β::Real = 0)
    xx = [@view x[B.mindices[i] : B.mindices[i+1]-1] for i in 1:length(B.mindices)-1]
    yy = [@view y[B.nindices[i] : B.nindices[i+1]-1] for i in 1:length(B.nindices)-1]
    blockmul!(yy, B.A, xx, α, β)
    return y
end

# carries out multiplication for general BlockFactorization
function blockmul!(y::AbstractVecOfVec, G::AbstractMatrix{<:AbstractMatOrFac}, x::AbstractVecOfVec,
        α::Real = 1, β::Real = 0, strided::Val{false} = Val(false))
    for i in eachindex(y) # @threads
        @. y[i] = β * y[i]
        for j in eachindex(x)
            Gij = G[i, j] # if it is not strided, we can't pre-allocate memory for blocks
            mul!(y[i], Gij, x[j], α, 1) # woodbury still allocates here because of Diagonal
        end
    end
end

# carries out block multiplication for strided block factorization
function LinearAlgebra.mul!(y::AbstractVector, B::StridedBlockFactorization, x::AbstractVector, α::Real = 1, β::Real = 0)
    length(x) == size(B, 2) || throw(DimensionMismatch("length(x) = $(length(x)) ≠ $(size(B, 2)) = size(B, 2)"))
    length(y) == size(B, 1) || throw(DimensionMismatch("length(y) = $(length(y)) ≠ $(size(B, 1)) = size(B, 1)"))
    X, Y = reshape(x, B.mindices.step, :), reshape(y, B.nindices.step, :)
    xx, yy = [c for c in eachcol(X)], [c for c in eachcol(Y)]
    strided = Val(true)
    blockmul!(yy, B.A, xx, strided, α, β)
    return y
end

# recursively calls mul!, thereby avoiding memory allocation of block-matrix multiplication
function blockmul!(y::AbstractVecOfVec, G::AbstractMatrix{<:AbstractMatOrFac}, x::AbstractVecOfVec,
                  strided::Val{true}, α::Real = 1, β::Real = 0)
    Gijs = [G[1, 1] for _ in 1:nthreads()] # pre-allocate temporary storage for matrix elements
    for i in eachindex(y)
        @. y[i] = β * y[i]
        Gij = Gijs[threadid()]
        for j in eachindex(x)
            evaluate!(Gij, G, i, j) # evaluating G[i, j] but can be more efficient if block has special structure (e.g. Woodbury)
            mul!(y[i], Gij, x[j], α, 1) # woodbury still allocates here because of Diagonal
        end
    end
    return y
end

# fallback for generic matrices or factorizations
function evaluate!(Gij::AbstractMatrix, G::AbstractMatrix{<:AbstractMatOrFac}, i::Int, j::Int)
    Gij .= AbstractMatrix(G[i, j])
end

# function LinearAlgebra.mul!(Y::AbstractMatrix, B::StridedBlockFactorization, X::AbstractMatrix, α::Real = 1, β::Real = 0)
#     k = size(Y, 2)
#     XR, YR = reshape(X, B.mindices.step, :, k), reshape(Y, B.nindices.step, :, k)
#     n, m = size(XR, 2), size(YR, 2)
#     XX, YY = @views [XR[:, i, :] for i in 1:n], [YR[:, i, :] for i in 1:m]
#     mul!(XX, B.A, YY, α, β)
#     return Y
# end

using OptimizationAlgorithms: cg
# linear solves with block factorization via cg
Base.:\(A::BlockFactorization, b::AbstractVector) = cg(A, b; min_res = A.tol)
function LinearAlgebra.ldiv!(y::AbstractVector, A::BlockFactorization, x::AbstractVector)
    cg!(A, x, y; min_res = A.tol) # IDEA: pre-allocate CG?
end

# by default, Gramians of matrix-valued kernels are BlockFactorizations
function gramian(k::MultiKernel, x::AbstractVector, y::AbstractVector)
    G = Gramian(k, x, y)
    BlockFactorization(G)
end
