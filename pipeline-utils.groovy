/* This is sourced by the various Jenkins pipeline files. It
 * provides some commonly used functions.
 */

// let's try not to use env vars here to keep things
// decoupled and easier to grok

def define_properties(timer) {

    // Set this to TRUE to disable the timer, and set DRY_RUN=true by default
    def developmentPipeline = false;

    if (developmentPipeline)
      timer = null;

    /* There's a subtle gotcha here. Don't use `env.$PARAM`, but `params.$PARAM`
     * instead. The former will *not* be set on the first run, since the
     * parameters are not set yet. The latter will be set on the first run as
     * soon as the below is executed. See:
     * https://issues.jenkins-ci.org/browse/JENKINS-40574 */
    properties([
      pipelineTriggers(timer == null ? [] : [cron(timer)]),
      parameters([
        credentials(name: 'ARTIFACT_SSH_CREDS_ID',
                    credentialType: 'com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey',
                    description: "SSH key for artifact server.",
                    defaultValue: 'a5990862-8650-411c-9c19-049ee09344e5',
                    required: true),
        credentials(name: 'AWS_CREDENTIALS',
                    credentialType: 'com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl',
                    description: "AWS credentials.",
                    defaultValue: 'd08c733e-63e0-48f4-a2c4-4e060068f94e',
                    required: true),
        credentials(name: 'AWS_CI_ACCOUNT',
                    credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl',
                    description: "OpenShift AWS CI root account number.",
                    defaultValue: '4d186169-c856-4da0-bd9e-0c976c264e83',
                    required: true),
        credentials(name: 'REGISTRY_CREDENTIALS',
                    credentialType: 'com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl',
                    description: "Credentials for Docker registry.",
                    defaultValue: 'e3fd566b-46c1-44e4-aec9-bb59214c1926',
                    required: true),
        // Past here, we're just using parameters as a way to avoid hardcoding internal values; they
        // are not actually secret.
        booleanParam(name: 'DRY_RUN', defaultValue: developmentPipeline, description: 'If true, do not push changes'),
        credentials(name: 'ARTIFACT_SERVER',
                    credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl',
                    description: "(not secret) Server used to push/receive built artifacts.",
                    defaultValue: 'c051c78a-7210-4dec-92de-6f51616aac79',
                    required: true),
        credentials(name: 'S3_PRIVATE_BUCKET',
                    credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl',
                    description: "(not secret) Private S3 bucket to use when uploading AMIs.",
                    defaultValue: '5c9571a2-c492-421f-b506-ba469afffc10',
                    required: true),
        credentials(name: 'OSTREE_INSTALL_URL',
                    credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl',
                    description: "(not secret) Remote OSTree repo URL to install from when running imagefactory.",
                    defaultValue: '2d6637ef-7f53-4ee2-bd35-7865908560c7',
                    required: true),
        credentials(name: 'INSTALLER_TREE_URL',
                    credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl',
                    description: "(not secret) Local installer tree mirror to use when running imagefactory.",
                    defaultValue: '50db8fac-f9d8-44e1-af0f-be29325a2896',
                    required: true),
      ])
    ])
}

// We currently unpack the oscontainer via podman-inside-docker; since
// overlayfs on overlayfs doesn't work, we need access to a "host workspace"
// which is distinct from ${WORKSPACE} which lives in the Jenkins agent container.
// This is a bit like a Kubernetes emptyDir.
def prepare_host_workspace() {
    def host_workspace_prefix = "/srv/jenkins-host-workspace/${env.JOB_NAME}"
    def host_workspace = "${host_workspace_prefix}.${env.BUILD_NUMBER}"
    sh """
        mkdir -p ${host_workspace_prefix}
        rm ${host_workspace_prefix}/* -rf
        mkdir ${host_workspace}
    """
    echo("Allocated host workspace: ${host_workspace}")
    return host_workspace
}

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
