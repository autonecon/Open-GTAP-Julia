# ZERO_HESS=1: give Ipopt an identically zero Hessian of the Lagrangian (empty
# structure) instead of JuMP's AD Hessian. The model is a square system with a
# zero objective, so the Newton step does not depend on the Hessian; building
# the AD Hessian is most of the solve time and memory on larger maps. The
# solution is the same as with the exact Hessian; only the iterations to
# reach it can differ.
using JuMP
const _NL = JuMP.MOI.Nonlinear
struct ZeroHessAD <: _NL.AbstractAutomaticDifferentiation end
struct ZeroHessEval <: JuMP.MOI.AbstractNLPEvaluator
    inner::JuMP.MOI.AbstractNLPEvaluator
end
_NL.Evaluator(model::_NL.Model, ::ZeroHessAD, vars::Vector{JuMP.MOI.VariableIndex}) =
    _NL.Evaluator(model, ZeroHessEval(_NL.Evaluator(model, _NL.SparseReverseMode(), vars).backend))
JuMP.MOI.features_available(::ZeroHessEval) = [:Grad, :Jac, :Hess]
JuMP.MOI.initialize(e::ZeroHessEval, f::Vector{Symbol}) = JuMP.MOI.initialize(e.inner, filter(!=(:Hess), f))
JuMP.MOI.hessian_lagrangian_structure(::ZeroHessEval) = Tuple{Int64,Int64}[]
JuMP.MOI.eval_hessian_lagrangian(::ZeroHessEval, H, x, σ, μ) = nothing
for fn in (:eval_objective, :eval_objective_gradient, :eval_constraint, :eval_constraint_jacobian, :jacobian_structure,
           :eval_constraint_jacobian_product, :eval_constraint_jacobian_transpose_product)
    @eval JuMP.MOI.$fn(e::ZeroHessEval, args...) = JuMP.MOI.$fn(e.inner, args...)
end
"""Use the zero Hessian on `model` when ZERO_HESS=1."""
zero_hessian!(model) = get(ENV, "ZERO_HESS", "0") == "1" && set_attribute(model, JuMP.MOI.AutomaticDifferentiationBackend(), ZeroHessAD())
