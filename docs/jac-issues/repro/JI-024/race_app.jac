node Item {
    has key: str;
}

def:pub ensure(wanted: str) -> int {
    # The persistence reference's find-or-create, on the anonymous (guest) root.
    if not [root-->[?:Item, key==wanted]] {
        root ++> Item(key=wanted);
    }
    return len([root-->[?:Item, key==wanted]]);
}

def:pub count(wanted: str) -> int {
    return len([root-->[?:Item, key==wanted]]);
}
