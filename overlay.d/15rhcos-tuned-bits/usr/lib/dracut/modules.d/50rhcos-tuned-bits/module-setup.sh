#!/bin/bash

check() {
    return 0
}

depends() {
    return 0
}

install() {
    inst_hook pre-udev 00 "$moddir/tuned-workqueue.sh"
}
