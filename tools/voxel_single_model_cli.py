"""Command-line guard shared by fixed-identity model generators."""
from __future__ import annotations

import sys


def reject_target_override(model_id: str) -> None:
    """Allow no target or the script's own ID; reject every alternate target."""
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if not args:
        return
    if args == [model_id]:
        return
    raise SystemExit(
        f"This generator owns only '{model_id}'. Run a different model's dedicated generator."
    )
