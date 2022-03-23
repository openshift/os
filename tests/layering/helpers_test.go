package e2e_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"os"
	"path"
	"strings"
	"sync"
	"testing"
	"time"

	buildv1 "github.com/openshift/api/build/v1"
	imagev1 "github.com/openshift/api/image/v1"
	machineClient "github.com/openshift/client-go/machine/clientset/versioned"
	"github.com/openshift/machine-config-operator/test/framework"
	"github.com/openshift/machine-config-operator/test/helpers"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	v1 "k8s.io/api/core/v1"
	k8sErrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	aggregatedErr "k8s.io/apimachinery/pkg/util/errors"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubernetes/pkg/credentialprovider"
)

// Gets the RHCOS base image tag from the BRANCH environment variable or
// defaults to "latest"; e.g., registry.ci.openshift.org/rhcos-devel/rhel-coreos:<tag>
func getBaseImageTag() string {
	branch, found := os.LookupEnv("BRANCH")
	if !found || branch == "" {
		return "latest"
	}

	return strings.ReplaceAll(branch, "release-", "")
}

// Builds a derived OS image and places it into an Imagesteam. Attempts to use
// a previously-built image, if one is available.
func maybeBuildDerivedOSImage(t *testing.T, cs *framework.ClientSet) error {
	imageStreamConfig := &imagev1.ImageStream{
		ObjectMeta: metav1.ObjectMeta{
			Name:      imageStreamName,
			Namespace: mcoNamespace,
		},
	}

	_, err := cs.ImageStreams(mcoNamespace).Create(context.TODO(), imageStreamConfig, metav1.CreateOptions{})
	if err != nil && !k8sErrors.IsAlreadyExists(err) {
		// If we have an error and it is not an already exists error, something is wrong.
		return err
	}

	if k8sErrors.IsAlreadyExists(err) {
		// We've already got an imagestream matching this name
		imagestream, err := cs.ImageStreams(mcoNamespace).Get(context.TODO(), imageStreamName, metav1.GetOptions{})
		if err != nil {
			return err
		}

		// Lets see if it has an image we can use
		if len(imagestream.Status.Tags) != 0 {
			t.Logf("image already built, reusing!")
			return nil
		}
	}

	baseImageBuildArg := fmt.Sprintf(imagePullSpec, getBaseImageTag())

	t.Logf("imagestream %s created", imageStreamName)
	t.Logf("using %s as the base image", baseImageBuildArg)

	// Create a new build
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

	// Start our new build
	_, err = cs.BuildV1Interface.Builds(mcoNamespace).Create(context.TODO(), buildConfig, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("could not create build: %w", err)
	}

	t.Log("base image derivation build started")

	build, err := cs.BuildV1Interface.Builds(mcoNamespace).Get(context.TODO(), buildConfig.Name, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("could not get build %s: %w", build.Name, err)
	}

	// Wait for the build to complete
	return waitForBuildToRun(t, cs, build)
}

// Puts the pull secret for the MCD service account on the underlying node so rpm-ostree can use it.
// get ImagePullSecret for the MCD service account and save to authfilePath on the node
// eventually we should use rest.InClusterConfig() instead of cs with kubeadmin
func putPullSecretOnNode(t *testing.T, cs *framework.ClientSet, node *corev1.Node) func() {
	t.Logf("placing image pull secret on node")

	// Get the MCD service account
	mcdServiceAccount, err := cs.ServiceAccounts(mcoNamespace).Get(context.TODO(), "machine-config-daemon", metav1.GetOptions{})
	require.Nil(t, err)
	require.Equal(t, 1, len(mcdServiceAccount.ImagePullSecrets))

	// Get the image pull secret attached to the service account
	imagePullSecret, err := cs.Secrets(mcoNamespace).Get(context.TODO(), mcdServiceAccount.ImagePullSecrets[0].Name, metav1.GetOptions{})
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
		// Clean up the pull secret from the node if the node has not rebooted and we do not want to delete it.
		t.Logf("cleaning up pull secret from node")
		if _, err := ExecCmdOnNode(cs, node, []string{"rm", "-rf", path.Dir(authfilePath)}); err != nil {
			t.Fatalf("could not remove pull secret from node: %s", err)
		}
	}
}

// Writes a file to an arbitrary path on a node
func writeFileToNode(t *testing.T, cs *framework.ClientSet, node *corev1.Node, data []byte, dst string) error {
	runner := NewNodeCmdRunner(cs, node, mcoNamespace)

	if _, err := runner.Run([]string{"mkdir", "-p", path.Dir(dst)}); err != nil {
		return fmt.Errorf("could not create new directory (%s): %w", path.Dir(dst), err)
	}

	runOpts := NodeCmdOpts{
		Command: []string{"tee", dst},
		Stdin:   bytes.NewBuffer(data),
	}

	if _, err := runner.RunWithOpts(runOpts); err != nil {
		return fmt.Errorf("could not write to file (%s): %w", dst, err)
	}

	return nil
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
	t.Logf("rolling back to previous OS image")

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
		"/usr/lib64/libpixman-1.so.0",
		"/etc/systemd/system/hello-world.service",
		helloWorldPath,
	}

	for _, deployment := range status.Deployments {
		if deployment.Booted {
			if usingImage {
				t.Logf("we expect that we're using the newly derived image")
				// Check that our container image is as expected
				assert.Equal(t, imageURL, deployment.ContainerImageReference)
				// Check that we have the expected files on the node
				assertNodeHasFiles(t, cs, node, expectedFiles)
				// Run the hello world program that we built and placed on the node
				result, err := ExecCmdOnNode(cs, node, []string{helloWorldPath})
				t.Logf("Running hello world command: \n%s", result.String())
				assert.Nil(t, err)
			} else {
				t.Logf("we expect that we're using the non-derived image")
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
func rebootAndWait(t *testing.T, cs *framework.ClientSet, node *corev1.Node) error {
	t.Logf("rebooting %s", node.Name)

	// Get an updated node object since this one may potentially be out-of-date
	updatedNode, err := cs.Nodes().Get(context.TODO(), node.ObjectMeta.Name, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("could not get updated node: %w", err)
	}

	prevBootID := updatedNode.Status.NodeInfo.BootID

	if _, err := ExecCmdOnNode(cs, node, []string{"systemctl", "reboot"}); err != nil {
		return fmt.Errorf("could not reboot node: %w", err)
	}

	startTime := time.Now()
	err = wait.Poll(2*time.Second, 10*time.Minute, func() (bool, error) {
		n, err := cs.Nodes().Get(context.TODO(), node.ObjectMeta.Name, metav1.GetOptions{})
		require.Nil(t, err)

		if n.Status.NodeInfo.BootID != prevBootID {
			return isNodeReady(n), nil
		}
		return false, nil
	})

	if err != nil {
		return fmt.Errorf("node %q never rebooted (waited %s)", node.ObjectMeta.Name, time.Since(startTime))
	}

	t.Logf("node %q has rebooted (waited %s)", node.ObjectMeta.Name, time.Since(startTime))

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

			combined := string(cr.Stdout) + string(cr.Stderr)

			if strings.Contains(combined, activeState) && !strings.Contains(combined, startLimitHit) {
				// We're good
				return true
			}

			if strings.Contains(combined, startLimitHit) {
				t.Logf("rpm-ostree start limit hit, waiting 60 seconds")
				time.Sleep(60 * time.Second)
			}

			_, err = runner.RunWithOpts(NodeCmdOpts{
				Command: []string{"systemctl", "start", "rpm-ostreed"},
				Stderr:  os.Stderr,
			})

			if err != nil {
				// Give rpm-ostree time to restart before we retry the status check
				t.Logf("started rpm-ostree")
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

			combinedOut := string(cr.Stdout) + string(cr.Stderr)
			if strings.Contains(combinedOut, failureMsg) {
				t.Logf("encountered start-limit-hit error, will wait and restart rpm-ostree, then try again")
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

func streamBuildLogs(t *testing.T, cs *framework.ClientSet, build *buildv1.Build) error {
	// Configure our output writers for later use with an io.MultiWriter
	outWriters := []io.Writer{}

	if buildLogFile != nil && *buildLogFile != "" {
		t.Logf("writing build log to: %s", *buildLogFile)

		buildLog, err := os.Create(*buildLogFile)
		if err != nil {
			return fmt.Errorf("could not create image_build.log: %w", err)
		}
		defer buildLog.Close()
		outWriters = append(outWriters, buildLog)
	}

	if streamBuild != nil && *streamBuild {
		t.Logf("streaming build logs to stdout")
		outWriters = append(outWriters, os.Stdout)
	}

	// We're not configured to stream any logs, so stop here.
	if len(outWriters) == 0 {
		t.Logf("not capturing build logs")
		return nil
	}

	// Wait for the build to start so we can get the underlying pod.
	err := wait.Poll(2*time.Second, 5*time.Minute, func() (bool, error) {
		b, err := cs.BuildV1Interface.Builds(build.Namespace).Get(context.TODO(), build.Name, metav1.GetOptions{})
		if err != nil {
			return false, fmt.Errorf("could not get build: %w", err)
		}

		return b.Status.Phase == buildv1.BuildPhaseRunning, nil
	})

	if err != nil {
		return fmt.Errorf("build did not start within a reasonable amount of time")
	}

	// Get updated build object
	build, err = cs.BuildV1Interface.Builds(build.Namespace).Get(context.TODO(), build.Name, metav1.GetOptions{})
	buildPodName := build.Annotations[buildv1.BuildPodNameAnnotation]

	// Wait for build container to start
	err = wait.Poll(2*time.Second, 1*time.Minute, func() (bool, error) {
		// TODO: Find constant for this annotation name
		buildPod, err := cs.Pods(build.Namespace).Get(context.TODO(), buildPodName, metav1.GetOptions{})
		if err != nil {
			return false, fmt.Errorf("could not get build pod for build %s: %w", buildName, err)
		}

		return isPodReady(buildPod), nil
	})

	if err != nil {
		return fmt.Errorf("build container did not start within a reasonable amount of time")
	}

	// Get the build pod so we can stream its logs.
	buildPod, err := cs.Pods(build.Namespace).Get(context.TODO(), buildPodName, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("could not get build pod for build %s: %w", buildName, err)
	}

	podLogOpts := &corev1.PodLogOptions{
		Follow:    true,
		Container: buildPod.Spec.Containers[0].Name,
	}

	// Get the io.Reader we read for the build logs
	req := cs.Pods(buildPod.Namespace).GetLogs(buildPod.Name, podLogOpts)
	podLogs, err := req.Stream(context.TODO())
	if err != nil {
		return fmt.Errorf("could not stream build pod logs: %w", err)
	}

	defer podLogs.Close()

	// Copy the contents of the io.Reader to our writers by using an
	// io.MultiWriter
	if _, err := io.Copy(io.MultiWriter(outWriters...), podLogs); err != nil {
		return fmt.Errorf("could not stream build logs to stdout: %w", err)
	}

	return nil
}

// Waits for the build to run while simultaneously streaming the build output
// if either of the flags are set to do so.
func waitForBuildToRun(t *testing.T, cs *framework.ClientSet, build *buildv1.Build) error {
	var wg sync.WaitGroup
	wg.Add(2)

	var streamErr error = nil
	var waitErr error = nil

	go func(to *testing.T) {
		defer wg.Done()
		waitErr = waitForBuild(to, cs, build)
	}(t)

	go func(to *testing.T) {
		defer wg.Done()
		streamErr = streamBuildLogs(to, cs, build)
	}(t)

	wg.Wait()

	return aggregatedErr.NewAggregate([]error{
		streamErr,
		waitErr,
	})
}

// Waits for a build to complete.
func waitForBuild(t *testing.T, cs *framework.ClientSet, build *buildv1.Build) error {
	startTime := time.Now()

	err := wait.Poll(2*time.Second, 20*time.Minute, func() (bool, error) {
		b, err := cs.BuildV1Interface.Builds(build.Namespace).Get(context.TODO(), build.Name, metav1.GetOptions{})
		if err != nil {
			return false, fmt.Errorf("could not get build: %w", err)
		}

		if b.Status.Phase == buildv1.BuildPhaseComplete {
			return true, nil
		}

		require.NotContains(t, []buildv1.BuildPhase{buildv1.BuildPhaseFailed, buildv1.BuildPhaseError, buildv1.BuildPhaseCancelled}, b.Status.Phase)
		return false, nil
	})

	if err != nil {
		return fmt.Errorf("build %q did not complete (waited %s)", build.Name, time.Since(startTime))
	}

	t.Logf("build %q has completed (waited %s)", build.Name, time.Since(startTime))

	return nil
}

// Deletes the machine using the OpenShift Machine API so that we don't land on
// the same machine if we're doing development on the test
func deleteMachineAndNode(t *testing.T, cs *framework.ClientSet, node *corev1.Node) {
	machineID := node.Annotations["machine.openshift.io/machine"]
	machineID = strings.ReplaceAll(machineID, "openshift-machine-api/", "")

	t.Logf("Deleting machine %s and node %s", machineID, node.Name)
	kubeconfig, err := cs.GetKubeconfig()
	require.Nil(t, err)

	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	require.Nil(t, err)

	client := machineClient.NewForConfigOrDie(config)

	require.Nil(t, client.MachineV1beta1().Machines("openshift-machine-api").Delete(context.TODO(), machineID, metav1.DeleteOptions{}))
	require.Nil(t, cs.Nodes().Delete(context.TODO(), node.Name, metav1.DeleteOptions{}))
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
