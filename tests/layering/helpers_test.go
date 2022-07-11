package e2e_test

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path"
	"strings"
	"testing"
	"time"

	machineClient "github.com/openshift/client-go/machine/clientset/versioned"
	"github.com/openshift/machine-config-operator/test/framework"
	"github.com/openshift/machine-config-operator/test/helpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubernetes/pkg/credentialprovider"
)

// Puts the pull secret for the MCD service account on the underlying node so rpm-ostree can use it.
// get ImagePullSecret for the MCD service account and save to authfilePath on the node
// eventually we should use rest.InClusterConfig() instead of cs with kubeadmin
func putPullSecretOnNode(t *testing.T, ctx context.Context, cs *framework.ClientSet, node *corev1.Node) func() {
	t.Log("placing image pull secret on node")

	// Get the MCD service account
	mcdServiceAccount, err := cs.ServiceAccounts(mcoNamespace).Get(ctx, "machine-config-daemon", metav1.GetOptions{})
	require.Nil(t, err)
	require.Equal(t, 1, len(mcdServiceAccount.ImagePullSecrets))

	// Get the image pull secret attached to the service account
	imagePullSecret, err := cs.Secrets(mcoNamespace).Get(ctx, mcdServiceAccount.ImagePullSecrets[0].Name, metav1.GetOptions{})
	require.Nil(t, err)

	// Extract the dockerconfig from the pull secret
	dockerConfigData := imagePullSecret.Data[corev1.DockerConfigKey]
	var dockerConfig credentialprovider.DockerConfig
	err = json.Unmarshal(dockerConfigData, &dockerConfig)
	require.Nil(t, err)
	dockerConfigJSON := credentialprovider.DockerConfigJSON{
		Auths: dockerConfig,
	}
	authfileData, err := json.Marshal(dockerConfigJSON)
	require.Nil(t, err)

	require.Nil(t, writeFileToNode(t, cs, node, authfileData, authfilePath))

	return func() {
		// Allow cleaning up the pull secret from the node if the node will not
		// reboot and we do not want to delete it.
		t.Log("cleaning up pull secret from node")
		if _, err := ExecCmdOnNode(cs, node, []string{"rm", "-rf", path.Dir(authfilePath)}); err != nil {
			t.Fatalf("could not remove pull secret from node: %s", err)
		}
	}
}

// Gets the status output of rpm-ostree. Note: At this time, we only retrieve a
// small subset of rpm-ostree's full status JSON
func getRPMOStreeStatus(t *testing.T, cs *framework.ClientSet, node *corev1.Node) (*Status, error) {
	result, err := runRPMOstreeCmd(t, cs, node, []string{"rpm-ostree", "status", "--json"})
	if err != nil {
		return nil, fmt.Errorf("could not get rpm-ostree status: %w", err)
	}

	status := &Status{}
	if err := json.Unmarshal(result.Stdout, &status); err != nil {
		return nil, fmt.Errorf("could not parse rpm-ostree status: %w", err)
	}

	return status, nil
}

// Places the derived OS image onto the node using rpm-ostree.
func applyDerivedImage(t *testing.T, cs *framework.ClientSet, node *corev1.Node) error {
	// rpm-ostree rebase --experimental ostree-unverified-image:docker://image-registry.openshift-image-registry.svc.cluster.local:5000/openshift-machine-config-operator/test-boot-in-cluster-image-build

	t.Log("placing the new OS image")

	rpmOSTreeCmd := []string{"rpm-ostree", "rebase", "--experimental", imageURL}
	cmdResult, err := runRPMOstreeCmd(t, cs, node, rpmOSTreeCmd)
	if err != nil {
		return fmt.Errorf("could not place image on node: %w", err)
	}

	t.Logf("new OS image placed in %v", cmdResult.Duration)

	return nil
}

// Rolls back to the original OS image that was on the node.
func rollbackToOriginalImage(t *testing.T, cs *framework.ClientSet, node *corev1.Node) error {
	// Apply the rollback to the previous image
	t.Log("rolling back to previous OS image")

	_, err := runRPMOstreeCmd(t, cs, node, []string{"rpm-ostree", "rollback"})
	if err != nil {
		return fmt.Errorf("could not run rollback command: %w", err)
	}

	return nil
}

// Verifies that we're in the built image
func assertInDerivedImage(t *testing.T, cs *framework.ClientSet, node *corev1.Node) {
	status, err := getRPMOStreeStatus(t, cs, node)
	require.Nil(t, err)
	checkUsingImage(t, cs, node, true, status)
}

// Verifies that we are not in the built image
func assertNotInDerivedImage(t *testing.T, cs *framework.ClientSet, node *corev1.Node) {
	status, err := getRPMOStreeStatus(t, cs, node)
	require.Nil(t, err)
	checkUsingImage(t, cs, node, false, status)
}

// Performs the check that we're either in the derived image or not.
func checkUsingImage(t *testing.T, cs *framework.ClientSet, node *corev1.Node, usingImage bool, status *Status) {
	// These files are placed on the node by the derived container build process.
	expectedFiles := []string{
		"/etc/systemd/system/hello-world.service",
		helloWorldPath,
	}

	for _, deployment := range status.Deployments {
		if deployment.Booted {
			if usingImage {
				t.Log("we expect that we're using the newly derived image")
				// Check that our container image is as expected
				assert.Equal(t, imageURL, deployment.ContainerImageReference)
				// Check that we have the expected files on the node
				assertNodeHasFiles(t, cs, node, expectedFiles)
				// Run the hello world program that we built and placed on the node
				result, err := ExecCmdOnNode(cs, node, []string{helloWorldPath})
				t.Logf("Running hello world command: \n%s", result.String())
				assert.Nil(t, err)
			} else {
				t.Log("we expect that we're using the non-derived image")
				assert.NotEqual(t, imageURL, deployment.ContainerImageReference)
				assertNodeNotHasFiles(t, cs, node, expectedFiles)
			}
		}
	}
}

// Asserts that a node has files in the expected places.
func assertNodeHasFiles(t *testing.T, cs *framework.ClientSet, node *corev1.Node, files []string) {
	for _, file := range files {
		out, err := ExecCmdOnNode(cs, node, []string{"stat", file})
		require.Nil(t, err, "expected to find %s on node %s: %s", file, node.Name, out.String())
		t.Logf("found %s on node %s (this was as expected)", file, node.Name)
	}
}

// Asserts that a node does not have files in the expected places.
func assertNodeNotHasFiles(t *testing.T, cs *framework.ClientSet, node *corev1.Node, files []string) {
	for _, file := range files {
		out, err := ExecCmdOnNode(cs, node, []string{"stat", file})
		require.NotNil(t, err, "expected not to find %s on node %s:\n%s", file, node.Name, out.String())
		t.Logf("did not find %s on node %s (this was as expected)", file, node.Name)
	}
}

// Determines if a node is ready.
func isNodeReady(node *corev1.Node) bool {
	for _, condition := range node.Status.Conditions {
		if condition.Type == corev1.NodeReady && condition.Status == "True" {
			return true
		}
	}

	return false
}

// RebootAndWait reboots a node, waits until it's status is ready.
func rebootAndWait(t *testing.T, ctx context.Context, cs *framework.ClientSet, node *corev1.Node) error {
	t.Logf("rebooting %s", node.Name)

	// Get an updated node object since this one may potentially be out-of-date
	updatedNode, err := cs.Nodes().Get(ctx, node.Name, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("could not get updated node: %w", err)
	}

	prevBootID := updatedNode.Status.NodeInfo.BootID

	// Occasionally, the command pod exits with a 143 when running the reboot
	// command. This makes sense because with the reboot, the pod is being
	// asked to terminate itself. This does not mean that the reboot failed.
	if _, err := ExecCmdOnNode(cs, node, []string{"systemctl", "reboot"}); err != nil && !isGracefulTerminationErr(err) {
		return fmt.Errorf("could not reboot node: %w", err)
	}

	startTime := time.Now()
	err = wait.Poll(2*time.Second, 10*time.Minute, func() (bool, error) {
		n, err := cs.Nodes().Get(ctx, node.Name, metav1.GetOptions{})
		require.Nil(t, err)

		if n.Status.NodeInfo.BootID != prevBootID {
			return isNodeReady(n), nil
		}
		return false, nil
	})

	if err != nil {
		return fmt.Errorf("node %q never rebooted (waited %s)", node.Name, time.Since(startTime))
	}

	t.Logf("node %q has rebooted (waited %s)", node.Name, time.Since(startTime))

	return nil
}

// Ensures that rpm-ostree is running by first interrogating its status from
// systemd, then tries to start it if it is not running. It will try to start
// rpm-ostree up to five times.
func ensureRPMOstreeIsRunning(t *testing.T, cs *framework.ClientSet, node *corev1.Node) error {
	activeState := "ActiveState=active"
	startLimitHit := "Result=start-limit-hit"

	runner := NewNodeCmdRunner(cs, node, mcoNamespace)

	runOpts := NodeCmdOpts{
		Command: []string{"systemctl", "show", "--no-page", "rpm-ostreed"},
		Retries: 5,
		RetryCheckFunc: func(attempt int, cr *CmdResult, err error) bool {
			// We ran into an error trying to get the rpm-ostreed status, retry.
			if err != nil {
				return false
			}

			combined := cr.CombinedOutput()

			if strings.Contains(combined, activeState) && !strings.Contains(combined, startLimitHit) {
				// We're good
				return true
			}

			if strings.Contains(combined, startLimitHit) {
				t.Log("rpm-ostree start limit hit, waiting 60 seconds")
				time.Sleep(60 * time.Second)
			}

			_, err = runner.RunWithOpts(NodeCmdOpts{
				Command: []string{"systemctl", "start", "rpm-ostreed"},
				Stderr:  os.Stderr,
			})

			if err != nil {
				// Give rpm-ostree time to restart before we retry the status check
				t.Log("started rpm-ostree")
				time.Sleep(time.Second)
				return false
			}

			return false
		},
		Stderr: os.Stderr,
	}

	if _, err := runner.RunWithOpts(runOpts); err != nil {
		return fmt.Errorf("failed to start rpm-ostree:\n%w", err)
	}

	return nil
}

// Runs an arbitrary rpm-ostree command after first ensuring that rpm-ostree is
// running. It will retry the command up to five times.
func runRPMOstreeCmd(t *testing.T, cs *framework.ClientSet, node *corev1.Node, cmd []string) (*CmdResult, error) {
	if err := ensureRPMOstreeIsRunning(t, cs, node); err != nil {
		return nil, fmt.Errorf("could not ensure that rpm-ostreed is running: %w", err)
	}

	failureMsg := "Active: failed (Result: start-limit-hit)"

	runner := NewNodeCmdRunner(cs, node, mcoNamespace)

	runOpts := NodeCmdOpts{
		Command: cmd,
		Retries: 5,
		RetryCheckFunc: func(attempt int, cr *CmdResult, err error) bool {
			if err != nil {
				return false
			}

			if strings.Contains(cr.CombinedOutput(), failureMsg) {
				t.Log("encountered start-limit-hit error, will wait and restart rpm-ostree, then try again")
				ensureRPMOstreeIsRunning(t, cs, node)
				return false
			}

			t.Logf("ran '$ %s' successfully, took %s", strings.Join(cmd, " "), cr.Duration)
			return true
		},
		Stderr: os.Stderr,
	}

	t.Logf("running: '$ %s'", strings.Join(cmd, " "))
	result, err := runner.RunWithOpts(runOpts)
	if err != nil {
		return nil, fmt.Errorf("could not run rpm-ostree command: %w", err)
	}

	return result, nil
}

// Deletes the machine using the OpenShift Machine API so that we don't land on
// the same machine if we're doing development on the test
func deleteMachineAndNode(t *testing.T, ctx context.Context, cs *framework.ClientSet, node *corev1.Node) {
	machineID := node.Annotations["machine.openshift.io/machine"]
	machineID = strings.ReplaceAll(machineID, "openshift-machine-api/", "")

	t.Logf("Deleting machine %s and node %s", machineID, node.Name)
	kubeconfig, err := cs.GetKubeconfig()
	require.Nil(t, err)

	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	require.Nil(t, err)

	client := machineClient.NewForConfigOrDie(config)

	require.Nil(t, client.MachineV1beta1().Machines("openshift-machine-api").Delete(ctx, machineID, metav1.DeleteOptions{}))
	require.Nil(t, cs.Nodes().Delete(ctx, node.Name, metav1.DeleteOptions{}))
}

// Gets a random node to use as a target for this test
func getRandomNode(cs *framework.ClientSet, role string) (*corev1.Node, error) {
	nodes, err := helpers.GetNodesByRole(cs, role)
	if err != nil {
		return nil, err
	}

	// #nosec
	rand.Seed(time.Now().UnixNano())
	node := nodes[rand.Intn(len(nodes))]

	return &node, nil
}
