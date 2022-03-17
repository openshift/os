package e2e_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path"
	"strings"
	"testing"
	"time"

	buildv1 "github.com/openshift/api/build/v1"
	imagev1 "github.com/openshift/api/image/v1"
	"github.com/openshift/machine-config-operator/test/framework"
	"github.com/openshift/machine-config-operator/test/helpers"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/kubernetes/pkg/credentialprovider"
)

const (
	imageStreamName = "test-boot-in-cluster-image"
	buildName       = imageStreamName
	// ostreeUnverifiedRegistry means no GPG or container signatures are used.
	// Right now we're usually relying on digested pulls. See
	// https://github.com/openshift/machine-config-operator/blob/master/docs/OSUpgrades.md#questions-and-answers around integrity.
	// See https://docs.rs/ostree-ext/0.5.1/ostree_ext/container/struct.OstreeImageReference.html
	ostreeUnverifiedRegistry = "ostree-unverified-registry"
	imageRegistry            = "image-registry.openshift-image-registry.svc:5000"
	// If this moves from /run, make sure files get cleaned up
	authfilePath  = "/run/ostree/auth.json"
	mcoNamespace  = "openshift-machine-config-operator"
	imagePullSpec = "registry.ci.openshift.org/rhcos-devel/rhel-coreos:%s"
)

type Deployments struct {
	booted                  bool
	ContainerImageReference string `json:"container-image-reference"`
}
type Status struct {
	deployments []Deployments
}

func getImageTag() string {
	branch, found := os.LookupEnv("BRANCH")
	if !found || branch == "" {
		return "latest"
	}

	return strings.ReplaceAll(branch, "release-", "")
}

func TestBootInClusterImage(t *testing.T) {
	cs := framework.NewClientSet("")

	// create a new image stream
	ctx := context.TODO()
	imageStreamConfig := &imagev1.ImageStream{
		ObjectMeta: metav1.ObjectMeta{
			Name:      imageStreamName,
			Namespace: mcoNamespace,
		},
	}
	_, err := cs.ImageStreams(mcoNamespace).Create(ctx, imageStreamConfig, metav1.CreateOptions{})
	require.Nil(t, err)
	defer cs.ImageStreams(mcoNamespace).Delete(ctx, imageStreamName, metav1.DeleteOptions{})

	baseImageBuildArg := fmt.Sprintf(imagePullSpec, getImageTag())

	t.Logf("Imagestream %s created", imageStreamName)

	// push a build to the image stream
	buildConfig := &buildv1.Build{
		ObjectMeta: metav1.ObjectMeta{
			Name: buildName,
		},
		Spec: buildv1.BuildSpec{
			CommonSpec: buildv1.CommonSpec{
				Source: buildv1.BuildSource{
					Type: "Git",
					Git: &buildv1.GitBuildSource{
						URI: "https://github.com/coreos/fcos-derivation-example",
						Ref: "rhcos",
					},
				},
				Strategy: buildv1.BuildStrategy{
					DockerStrategy: &buildv1.DockerBuildStrategy{
						BuildArgs: []corev1.EnvVar{
							{
								Name:  "RHEL_COREOS_IMAGE",
								Value: baseImageBuildArg,
							},
						},
					},
				},
				Output: buildv1.BuildOutput{
					To: &v1.ObjectReference{
						Kind: "ImageStreamTag",
						Name: imageStreamName + ":latest",
					},
				},
			},
		},
	}

	t.Logf("Using %s as the base image", baseImageBuildArg)

	_, err = cs.BuildV1Interface.Builds(mcoNamespace).Create(ctx, buildConfig, metav1.CreateOptions{})
	require.Nil(t, err)
	defer cs.BuildV1Interface.Builds(mcoNamespace).Delete(ctx, buildName, metav1.DeleteOptions{})

	t.Logf("Build %s started", buildName)
	waitForBuild(t, cs, buildConfig.ObjectMeta.Name)
	t.Logf("Build completed!")

	// pick a random worker node
	unlabelFunc := helpers.LabelRandomNodeFromPool(t, cs, "worker", "node-role.kubernetes.io/infra")
	defer unlabelFunc()
	infraNode := helpers.GetSingleNodeByRole(t, cs, "infra")

	t.Logf("Labeled node %s with infra", infraNode.Name)

	// get ImagePullSecret for the MCD service account and save to authfilePath on the node
	// eventually we should use rest.InClusterConfig() instead of cs with kubeadmin
	mcdServiceAccount, err := cs.ServiceAccounts(mcoNamespace).Get(ctx, "machine-config-daemon", metav1.GetOptions{})
	require.Nil(t, err)
	require.Equal(t, 1, len(mcdServiceAccount.ImagePullSecrets))
	imagePullSecret, err := cs.Secrets(mcoNamespace).Get(ctx, mcdServiceAccount.ImagePullSecrets[0].Name, metav1.GetOptions{})
	dockerConfigData := imagePullSecret.Data[corev1.DockerConfigKey]
	var dockerConfig credentialprovider.DockerConfig
	err = json.Unmarshal(dockerConfigData, &dockerConfig)
	require.Nil(t, err)
	dockerConfigJSON := credentialprovider.DockerConfigJSON{
		Auths: dockerConfig,
	}
	authfileData, err := json.Marshal(dockerConfigJSON)
	require.Nil(t, err)
	helpers.ExecCmdOnNode(t, cs, infraNode, "mkdir", "-p", path.Dir(path.Join("/rootfs", authfilePath)))
	// will get cleaned up on reboot since file is in /run
	writeToMCDContainer(t, cs, infraNode, path.Join("/rootfs", authfilePath), authfileData)

	// rpm-ostree rebase --experimental ostree-unverified-image:docker://image-registry.openshift-image-registry.svc.cluster.local:5000/openshift-machine-config-operator/test-boot-in-cluster-image-build
	imageURL := fmt.Sprintf("%s:%s/%s/%s", ostreeUnverifiedRegistry, imageRegistry, mcoNamespace, imageStreamName)
	helpers.ExecCmdOnNode(t, cs, infraNode, "chroot", "/rootfs", "rpm-ostree", "rebase", "--experimental", imageURL)
	// reboot
	rebootAndWait(t, cs, infraNode)
	// check that new image is used
	checkUsingImage := func(usingImage bool) {
		status := helpers.ExecCmdOnNode(t, cs, infraNode, "chroot", "/rootfs", "rpm-ostree", "status", "--json")
		var statusJSON Status
		err = json.Unmarshal([]byte(status), &statusJSON)
		require.Nil(t, err)
		for _, deployment := range statusJSON.deployments {
			if deployment.booted {
				if usingImage {
					require.Equal(t, imageURL, deployment.ContainerImageReference)
				} else {
					require.NotEqual(t, imageURL, deployment.ContainerImageReference)
				}
			}
		}
	}
	checkUsingImage(true)
	// rollback
	helpers.ExecCmdOnNode(t, cs, infraNode, "chroot", "/rootfs", "rpm-ostree", "rollback")
	rebootAndWait(t, cs, infraNode)
	checkUsingImage(false)
}

// WriteToNode finds a node's mcd and writes a file over oc rsh's stdin
// filename should include /rootfs to write to node filesystem
func writeToMCDContainer(t *testing.T, cs *framework.ClientSet, node corev1.Node, filename string, data []byte) {
	mcd, err := helpers.MCDForNode(cs, &node)
	require.Nil(t, err)
	mcdName := mcd.ObjectMeta.Name

	entryPoint := "oc"
	args := []string{"rsh",
		"-n", "openshift-machine-config-operator",
		"-c", "machine-config-daemon",
		mcdName,
		"tee", filename,
	}

	cmd := exec.Command(entryPoint, args...)
	cmd.Stderr = os.Stderr
	cmd.Stdin = bytes.NewReader(data)

	out, err := cmd.Output()
	require.Nil(t, err, "failed to write data to file %q on node %s: %s", filename, node.Name, string(out))
}

// RebootAndWait reboots a node and then waits until the node has rebooted and its status is again Ready
func rebootAndWait(t *testing.T, cs *framework.ClientSet, node corev1.Node) {
	updatedNode, err := cs.Nodes().Get(context.TODO(), node.ObjectMeta.Name, metav1.GetOptions{})
	require.Nil(t, err)
	prevBootID := updatedNode.Status.NodeInfo.BootID
	helpers.ExecCmdOnNode(t, cs, node, "chroot", "/rootfs", "systemctl", "reboot")
	startTime := time.Now()
	if err := wait.Poll(2*time.Second, 20*time.Minute, func() (bool, error) {
		node, err := cs.Nodes().Get(context.TODO(), node.ObjectMeta.Name, metav1.GetOptions{})
		require.Nil(t, err)
		if node.Status.NodeInfo.BootID != prevBootID {
			for _, condition := range node.Status.Conditions {
				if condition.Type == corev1.NodeReady && condition.Status == "True" {
					return true, nil
				}
			}
		}
		return false, nil
	}); err != nil {
		require.Nil(t, err, "node %q never rebooted (waited %s)", node.ObjectMeta.Name, time.Since(startTime))
	}
	t.Logf("node %q has rebooted (waited %s)", node.ObjectMeta.Name, time.Since(startTime))
}

func waitForBuild(t *testing.T, cs *framework.ClientSet, build string) {
	startTime := time.Now()
	if err := wait.Poll(2*time.Second, 20*time.Minute, func() (bool, error) {
		build, err := cs.BuildV1Interface.Builds("openshift-machine-config-operator").Get(context.TODO(), build, metav1.GetOptions{})
		require.Nil(t, err)
		if build.Status.Phase == "Complete" {
			return true, nil
		}
		require.NotContains(t, []string{"Failed", "Error", "Cancelled"}, build.Status.Phase)
		return false, nil
	}); err != nil {
		require.Nil(t, err, "build %q did not complete (waited %s)", build, time.Since(startTime))
	}
	t.Logf("build %q has completed (waited %s)", build, time.Since(startTime))
}
