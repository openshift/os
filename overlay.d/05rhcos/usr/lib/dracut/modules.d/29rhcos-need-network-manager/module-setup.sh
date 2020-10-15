# We need a module that runs early (before any module that claims
# it depends on `network`) that pulls in network-manager to
# workaround https://github.com/dracutdevs/dracut/issues/798 which
# means we can't call `dracut --add network-manager` and have it
# properly override the default of `network-legacy` in `40network`.
depends() {
    echo network-manager
}

check() {
    return 0
}
