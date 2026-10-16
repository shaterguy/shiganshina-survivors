"""Pure-text QA adapter; does not read/write files, import project or run tests.

The caller may write the returned helper text ONLY in an isolated QA copy.
Injecting into the exact script keeps get_script() equality and native eligibility.
A CountingHelper subclass would disable the feature and is not a valid oracle.
This copy is for call counts only; no elapsed time from it is performance evidence.
"""
HELPER_PATH = "game/core/streamed_run_world.gd"
SIGNATURE = "func readiness(state: Dictionary, commands: Array = []) -> Dictionary:\n"
COUNTER = "qa_readiness_calls"


def instrument(helper: str) -> str:
    if helper.count(SIGNATURE) != 1:
        raise ValueError("Expected exactly one pinned readiness signature")
    if COUNTER in helper:
        raise ValueError("Refusing repeated or mixed QA instrumentation")
    return helper.replace(
        SIGNATURE,
        "var qa_readiness_calls: int = 0\n" + SIGNATURE + "\tqa_readiness_calls += 1\n",
        1,
    )
