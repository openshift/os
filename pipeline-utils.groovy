/* This is sourced by the various Jenkins pipeline files. It
 * provides some commonly used functions.
 */


// let's try not to use env vars here to keep things
// decoupled and easier to grok

def rsync_dir_in(server, key, dir) {
    rsync_dir(key, "${server}:${dir}", dir)
}

def rsync_dir_out(server, key, dir) {
    rsync_dir(key, dir, "${server}:${dir}")
}

def rsync_dir(key, from_dir, to_dir) {
    sh """
        rsync -Hrlpt --stats --delete --delete-after \
            -e 'ssh -i ${key} \
                    -o UserKnownHostsFile=/dev/null \
                    -o StrictHostKeyChecking=no' \
            ${from_dir}/ ${to_dir}
    """
}

def get_rev_version(repo, rev) {
    version = sh_capture("ostree show --repo=${repo} --print-metadata-key=version ${rev}")
    assert (version.startsWith("'") && version.endsWith("'"))
    return version[1..-2] // trim single quotes
}

def sh_capture(cmd) {
    return sh(returnStdout: true, script: cmd).trim()
}

return this
