pipeline {
    agent {
        docker { image 'registry.fedoraproject.org/fedora:28' }
    }
    stages {
        stage('build') {
            steps {
                // Just validate the JSON as an initial CI gate
                sh 'yum -y install jq && jq < host.json >/dev/null'
            }
        }
    }
}
