"""JI-060: an endpoint parameter left out of the request arrives as the text of its
default.

`flag` defaults to False, `n` to 0.0 and `s` to "". Called with only `a`, the endpoint
should see False, 0.0 and "": it sees the strings "False" and "0.0". "False" is a
non-empty string, so `if flag` takes the wrong branch.
"""

def:pub probe(
    a: str, flag: bool = False, n: float = 0.0, s: str = ""
) -> dict[str, str] {
    return {
        "flag": type(flag).__name__ + ":" + repr(flag),
        "n": type(n).__name__ + ":" + repr(n),
        "s": type(s).__name__ + ":" + repr(s),
        "branch": "flag is true" if flag else "flag is false"
    };
}
