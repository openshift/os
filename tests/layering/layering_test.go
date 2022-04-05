package e2e_test

import (
	"context"
	"flag"
	"testing"

	"github.com/openshift/machine-config-operator/test/framework"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// CLI Flags
var (
	deleteBuild   = flag.Bool("delete-build", false, "Delete the derived build at the end of the test.")
	deleteMachine = flag.Bool("delete-machine", false, "Delete the target machine after test run.")
	streamBuild   = flag.Bool("stream-build", false, "Stream the derived image build to stdout")
	buildLogFile  = flag.String("build-log", "", "Filename to write the derived image build log to")
)

const (
	// If this moves from /run, make sure files get cleaned up
	authfilePath = "/run/ostree/auth.json"

	buildName       = imageStreamName
	helloWorldPath  = "/usr/bin/hello-world"
	imageRegistry   = "image-registry.openshift-image-registry.svc:5000"
	imageStreamName = "test-boot-in-cluster-image"
	imageURL        = ostreeUnverifiedRegistry + ":" + imageRegistry + "/" + mcoNamespace + "/" + imageStreamName
	mcoNamespace    = "openshift-machine-config-operator"

	// ostreeUnverifiedRegistry means no GPG or container signatures are used.
	// Right now we're usually relying on digested pulls. See
	// https://github.com/openshift/machine-config-operator/blob/master/docs/OSUpgrades.md#questions-and-answers around integrity.
	// See https://docs.rs/ostree-ext/0.5.1/ostree_ext/container/struct.OstreeImageReference.html
	ostreeUnverifiedRegistry = "ostree-unverified-registry"
)

type Deployments struct {
	Booted                  bool   `json:"booted"`
	ContainerImageReference string `json:"container-image-reference"`
}

type Status struct {
	Deployments []Deployments `json:"deployments"`
}

func TestBootInClusterImage(t *testing.T) {
	cs := framework.NewClientSet("")
	// Get a random node to run on. Note: We don't need to set the infra role
	// because this test does not involve the MCO.
	targetNode, err := getRandomNode(cs, "worker")
	require.Nil(t, err)

	t.Logf("targeting node %s", targetNode.Name)

	ctx := context.Background()

	// If the delete-build flag is used, delete the Build and ImageStream afterward.
	if deleteBuild != nil && *deleteBuild == true {
		defer func() {
			t.Log("Deleting the ImageStream")
			require.Nil(t, cs.ImageStreams(mcoNamespace).Delete(context.TODO(), imageStreamName, metav1.DeleteOptions{}))
			t.Log("Deleting the Image Build")
			require.Nil(t, cs.BuildV1Interface.Builds(mcoNamespace).Delete(context.TODO(), buildName, metav1.DeleteOptions{}))
		}()
	}

	canDeleteMachine := false
	defer func() {
		// Only if the image is applied should we delete
		if canDeleteMachine {
			if deleteMachine != nil && *deleteMachine == true {
				deleteMachineAndNode(t, ctx, cs, targetNode)
			} else {
				t.Logf("leaving node %s behind, you need to clean it up manually", targetNode.Name)
			}
		} else {
			t.Logf("node %s will not be deleted since it was not touched", targetNode.Name)
		}
	}()

	testCases := []struct {
		name     string
		testFunc func(*testing.T)
	}{
		{
			name: "Derived Image Is Built",
			testFunc: func(t *testing.T) {
				if err := runImageDerivationBuild(t, ctx, cs); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "Not In Derived Image",
			testFunc: func(t *testing.T) {
				assertNotInDerivedImage(t, cs, targetNode)
			},
		},
		{
			name: "Boots Into Derived Image",
			testFunc: func(t *testing.T) {
				nodeRebooted := false
				deletePullSecret := putPullSecretOnNode(t, ctx, cs, targetNode)
				defer func() {
					// The pull secret should be cleared from the node upon reboot since
					// it is placed into the /run directory. However, if the node does
					// not reboot or get deleted, we should clean it up. Although this
					// test targets an ephemeral cluster, so maybe this isn't important?
					if !nodeRebooted && (deleteMachine == nil || *deleteMachine == false) {
						deletePullSecret()
					}
				}()

				// From this point on, we want to delete the underlying machine if the
				// delete-machine flag is used. This is because:
				// - If we failed to apply the OS update, the node could be in an
				// inconsistent state.
				// - If we were successful in applying the OS update, we still want to
				// delete the node afterweard so that if the test is re-run, it will
				// not target the same node.
				canDeleteMachine = true
				if err := applyDerivedImage(t, cs, targetNode); err != nil {
					t.Fatal(err)
				}

				if err := rebootAndWait(t, ctx, cs, targetNode); err != nil {
					t.Fatal(err)
				}

				nodeRebooted = true
				assertInDerivedImage(t, cs, targetNode)
			},
		},
		{
			name: "Rolls Back To Original Image",
			testFunc: func(t *testing.T) {
				if err := rollbackToOriginalImage(t, cs, targetNode); err != nil {
					t.Fatal(err)
				}

				if err := rebootAndWait(t, ctx, cs, targetNode); err != nil {
					t.Fatal(err)
				}

				assertNotInDerivedImage(t, cs, targetNode)
			},
		},
	}

	for i := range testCases {
		t.Run(testCases[i].name, testCases[i].testFunc)
	}
}
