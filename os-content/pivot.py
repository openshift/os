#!/usr/bin/python
# Execute an OS pivot - see https://github.com/openshift/os

import os,sys,argparse,json,subprocess,time

PIVOT_DONE_PATH = '/etc/os-container-pivot.stamp'
PIVOT_NAME = 'ostree-container-pivot'

def fatal(msg):
    print >>sys.stderr, msg
    sys.exit(1)
def run_with(fn, argv, **kwargs):
    print("Executing: {}".format(subprocess.list2cmdline(argv)))
    return fn(argv, **kwargs)
def run_getoutln(argv, **kwargs):
    return run_with(subprocess.check_output, argv, **kwargs).strip()
def run(argv, **kwargs):
    run_with(subprocess.check_call, argv, **kwargs)

parser = argparse.ArgumentParser()
parser.add_argument("container", help="name of container",
                    action='store')
parser.add_argument("--touch-if-changed", "-T", help="if changed, touch a file",
                    action='store')
parser.add_argument("--keep", "-k", help="Do not remove container image",
                    action='store_true')
parser.add_argument("--reboot", "-R", help="reboot if changed",
                    action='store_true')

args = parser.parse_args()

# This file holds the imageid (container name + sha256) that
# we successfully used for a previous pivot.
previous_pivot = None
if os.path.exists(PIVOT_DONE_PATH):
    with open(PIVOT_DONE_PATH) as f:
        previous_pivot = f.read().strip()
        print("Previous pivot: {}".format(previous_pivot))

# Use skopeo to find the sha256, so we can refer to it reliably
imgdata = json.loads(run_with(subprocess.check_output, ['skopeo', 'inspect', 'docker://'+args.container]))
imgid = args.container + '@' + imgdata['Digest']

if previous_pivot == imgid:
    print("Already pivoted to: {}".format(imgid))
    sys.exit(0)

# Pull the image
run(['podman', 'pull', imgid])
print("Pivoting to: {}".format(imgid))

# Clean up a previous container
def podman_rm(cid):
    run_with(subprocess.call, ['podman', 'kill', cid], stdout=open('/dev/null', 'w'), stderr=subprocess.STDOUT)
    run_with(subprocess.call, ['podman', 'rm', '-f', cid], stderr=open('/dev/null', 'w'))
podman_rm(PIVOT_NAME)

# `podman mount` wants a running container, so let's make a dummy one
cid = run_getoutln(['podman', 'run', '-d', '--name', PIVOT_NAME, '--entrypoint', 'sleep',
                    imgid, 'infinity'])
# Use the container ID to find its mount point
mnt = run_getoutln(['podman', 'mount', cid])
os.chdir(mnt)
# List all refs from the OSTree repository embedded in the container
refs = run_with(subprocess.check_output, ['ostree', '--repo=srv/tree/repo', 'refs']).split()
rlen = len(refs)
# Today, we only support one ref.  Down the line we may do multiple.
if rlen != 1:
    fatal("Found {} refs, expected exactly 1".format(rlen))
target_ref = refs[0]
# Find the concrete OSTree commit
rev = run_getoutln(['ostree', '--repo=srv/tree/repo', 'rev-parse', target_ref])

# Use pull-local to extract the data into the system repo; this is *significantly*
# faster than talking to the container over HTTP.
run(['ostree', 'pull-local', 'srv/tree/repo', rev])

# The leading ':' here means "no remote".  See also
# https://github.com/projectatomic/rpm-ostree/pull/1396
run(['rpm-ostree', 'rebase', ':'+rev])

# Done!  Write our stamp file.  TODO: Teach rpm-ostree how to encode
# this data in the origin.
with open(PIVOT_DONE_PATH, 'w') as f:
    f.write(imgid + '\n')
# Kill our dummy container
podman_rm(PIVOT_NAME)

# By default, delete the image.
if not args.keep:
    run(['podman', 'rmi', imgid])
