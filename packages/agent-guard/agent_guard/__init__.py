"""agent-guard: Enterprise-grade AI agent quality gates and context lifecycle governance."""

from .gates import (
    AssertionFinding,
    AssertionValidator,
    GateResult,
    GateStage,
    QualityGateChecker,
    check_substantive_assertions,
)
from .context_gc import (
    CanonicalStateAssertion,
    ContextPruner,
    SSOTState,
    TombstoneRegistry,
)

__version__ = "0.1.0"

__all__ = [
    "__version__",
    "AssertionFinding",
    "AssertionValidator",
    "GateResult",
    "GateStage",
    "QualityGateChecker",
    "check_substantive_assertions",
    "CanonicalStateAssertion",
    "ContextPruner",
    "SSOTState",
    "TombstoneRegistry",
]
