module TestGramian
using Kernel
using Test
using LinearAlgebra
using ToeplitzMatrices
using Kernel: gramian, Gramian

@testset "basic properties" begin
    n = 8
    x = randn(Float64, n)
    k = Kernel.EQ()
    G = gramian(k, x)

    @test issymmetric(G)
    M = Matrix(G)
    @test M ≈ k.(x, x')
    @test issymmetric(G) && issymmetric(M)
    @test isposdef(G) && isposdef(M) # if M is very low-rank, this can fail -> TODO: ispsd()

    G = gramian(k, x, x .+ randn(size(x)))
    M = Matrix(G)
    @test !issymmetric(G) && !issymmetric(M)
    @test !isposdef(G) && !isposdef(M)

    G = gramian(k, x, copy(x))
    @test !issymmetric(G) #&& !issymmetric(M)
    @test !isposdef(G) #&& !isposdef(M)

    # testing standard Gramian
    G = Gramian(x, x)
    @test G ≈ dot.(x, x')

    x = randn(Float64, n)
    k = Kernel.EQ{Float32}()
    G = gramian(k, x)
    println(typeof(k(x[1], x[1])))
    # type promotion
    @test typeof(k(x[1], x[1])) <: typeof(G[1,1]) # test promotion in inner constructor
    @test typeof(k(x[1], x[1])) <: eltype(G) # test promotion in inner constructor
    x = tuple.(x, x)
    G = gramian(k, x)
    @test typeof(k(x[1], x[1])) <: typeof(G[1,1])  # with tuples (or arrays)
    @test typeof(k(x[1], x[1])) <: eltype(G)

    # TODO: MultiKernel test
end

@testset "toeplitz structure" begin
    n = 16
    x = -1:.1:1
    k = Kernel.EQ()
    m = gramian(k, x)
    # @test typeof(m) <: SymmetricToeplitz
    m = gramian(k, x, Val(true)) # periodic boundary conditions
    @test m isa Circulant
end

end # TestGramian
