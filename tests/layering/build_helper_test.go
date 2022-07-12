package e2e_test

import (
	"context"
	"fmt"
	"io"
	"os"
	"sync"
	"testing"
	"time"

	buildv1 "github.com/openshift/api/build/v1"
	imagev1 "github.com/openshift/api/image/v1"
	"github.com/openshift/machine-config-operator/test/framework"
	"github.com/openshift/os/tests/layering/fixtures"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	v1 "k8s.io/api/core/v1"
	k8sErrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	aggregatedErr "k8s.io/apimachinery/pkg/util/errors"
	"k8s.io/apimachinery/pkg/util/wait"
)

// Gets the value of an environment variable or defaults to the provided
// default.
func getEnvVarOrDefault(envVarName, defaultValue string) string {
	value, found := os.LookupEnv(envVarName)
	if found && value != "" {
		return value
	}

	return defaultValue
}

// Holds the methods and objects needed to start a derived OS build image.
type builder struct {
	t         *testing.T
	clientSet *framework.ClientSet
}

// Creates a new builder struct and begins the build.
func runImageDerivationBuild(t *testing.T, ctx context.Context, cs *framework.ClientSet) error {
	b := &builder{
		t:         t,
		clientSet: cs,
	}

	return b.build(ctx)
}

// Begins the derived image build process
func (b *builder) build(ctx context.Context) error {
	imageStream, err := b.getImageStream(ctx)
	if err != nil {
		return fmt.Errorf("could not create or get imagestream: %w", err)
	}

	// Lets see if it has an image we can use
	if len(imageStream.Status.Tags) != 0 {
		b.t.Log("image already built, reusing!")
		return nil
	}

	if err := b.createConfigMap(ctx); err != nil {
		return err
	}

	return b.buildDerivedOSImage(ctx)
}

// Gets a preexisting ImageStream or creates a new one.
func (b *builder) getImageStream(ctx context.Context) (*imagev1.ImageStream, error) {
	// Check if we have an ImageStream matching this name.
	imageStream, err := b.clientSet.ImageStreams(mcoNamespace).Get(ctx, imageStreamName, metav1.GetOptions{})
	if err == nil {
		// We have a matching imagestream.
		return imageStream, nil
	}

	if k8sErrors.IsNotFound(err) {
		// We don't have a matching imagestream.
		return b.createImageStream(ctx)
	}

	// Something else happened.
	return nil, fmt.Errorf("could not get imagestream: %w", err)
}

// Creates an imagestream to push our built image to.
func (b *builder) createImageStream(ctx context.Context) (*imagev1.ImageStream, error) {
	imageStreamConfig := &imagev1.ImageStream{
		ObjectMeta: metav1.ObjectMeta{
			Name:      imageStreamName,
			Namespace: mcoNamespace,
		},
	}

	imageStream, err := b.clientSet.ImageStreams(mcoNamespace).Create(ctx, imageStreamConfig, metav1.CreateOptions{})
	if err != nil {
		return nil, fmt.Errorf("could not create imagestream: %w", err)
	}

	b.t.Logf("imagestream %s created", imageStreamName)

	return imageStream, err
}

// Creates a configmap which contains the hello-world.go and
// hello-world.service files for injection into the image build context.
func (b *builder) createConfigMap(ctx context.Context) error {
	configMap := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name: buildConfigMapName,
		},
		Data: map[string]string{
			"hello-world.go":      fixtures.HelloWorldSrc,
			"hello-world.service": fixtures.HelloWorldService,
		},
	}

	_, err := b.clientSet.CoreV1Interface.ConfigMaps(mcoNamespace).Create(ctx, configMap, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("could not create build configmap: %w", err)
	}

	return nil
}

// Actually perform the OS derivation build and waits for it to complete.
func (b *builder) buildDerivedOSImage(ctx context.Context) error {
	baseImagePullSpec := getEnvVarOrDefault("BASE_IMAGE_PULLSPEC", "registry.ci.openshift.org/rhcos-devel/rhel-coreos:latest")

	b.t.Log("base image pullspec:", baseImagePullSpec)

	// Create a new build
	buildConfig := &buildv1.Build{
		ObjectMeta: metav1.ObjectMeta{
			Name: buildName,
		},
		Spec: buildv1.BuildSpec{
			CommonSpec: buildv1.CommonSpec{
				Source: buildv1.BuildSource{
					ConfigMaps: []buildv1.ConfigMapBuildSource{
						{
							ConfigMap: corev1.LocalObjectReference{
								Name: buildConfigMapName,
							},
							DestinationDir: ".",
						},
					},
					Dockerfile: &fixtures.Dockerfile,
				},
				Strategy: buildv1.BuildStrategy{
					DockerStrategy: &buildv1.DockerBuildStrategy{
						BuildArgs: []corev1.EnvVar{
							{
								Name:  "BASE_OS_IMAGE",
								Value: baseImagePullSpec,
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
	build, err := b.clientSet.BuildV1Interface.Builds(mcoNamespace).Create(ctx, buildConfig, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("could not create build: %w", err)
	}

	b.t.Logf("base image derivation build started")

	// Wait for the build to complete
	return b.waitForBuildToRun(ctx, build)
}

// Waits for the build to run while allowing build logs to be streamed (if
// desired). It might be overkill to spawn two goroutines which both wait until
// the build is complete, but this was the simplest way to do this.
func (b *builder) waitForBuildToRun(ctx context.Context, build *buildv1.Build) error {
	var wg sync.WaitGroup
	wg.Add(2)

	var streamErr error = nil
	var waitErr error = nil

	// We have to pass the testing.T object in because the testing suite gets
	// grumpy if a failure occurs within a goroutine where it was not
	// explicitly passed in.
	go func(to *testing.T) {
		defer wg.Done()
		waitErr = b.waitForBuildToComplete(to, ctx, build)
	}(b.t)

	go func(to *testing.T) {
		defer wg.Done()
		streamErr = b.streamBuildLogs(to, ctx, build)
	}(b.t)

	wg.Wait()

	return aggregatedErr.NewAggregate([]error{
		streamErr,
		waitErr,
	})
}

// Waits for a build to complete.
func (b *builder) waitForBuildToComplete(t *testing.T, ctx context.Context, build *buildv1.Build) error {
	startTime := time.Now()

	if err := b.waitForBuildToStart(ctx, build); err != nil {
		return fmt.Errorf("build did not start: %w", err)
	}

	buildPod, err := b.getPodForBuild(ctx, build)
	if err != nil {
		return fmt.Errorf("could not get build pod: %w", err)
	}

	b.t.Logf("build pod scheduled on node: %s", buildPod.Spec.NodeName)

	err = wait.Poll(2*time.Second, 20*time.Minute, func() (bool, error) {
		pollBuild, err := b.clientSet.BuildV1Interface.Builds(build.Namespace).Get(ctx, build.Name, metav1.GetOptions{})
		if err != nil {
			return false, fmt.Errorf("could not get build: %w", err)
		}

		if pollBuild.Status.Phase == buildv1.BuildPhaseComplete {
			return true, nil
		}

		require.NotContains(t, []buildv1.BuildPhase{buildv1.BuildPhaseFailed, buildv1.BuildPhaseError, buildv1.BuildPhaseCancelled}, pollBuild.Status.Phase)
		return false, nil
	})

	if err != nil {
		return fmt.Errorf("build %q did not complete (waited %s)", build.Name, time.Since(startTime))
	}

	t.Logf("build %q has completed (waited %s)", build.Name, time.Since(startTime))

	return nil
}

// Resolves the build name to a pod name, assuming the build has begun.
func (b *builder) getPodForBuild(ctx context.Context, build *buildv1.Build) (*corev1.Pod, error) {
	// Get updated build object
	updatedBuild, err := b.clientSet.BuildV1Interface.Builds(build.Namespace).Get(ctx, build.Name, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("could not get pod for build: %w", err)
	}
	buildPodName := updatedBuild.Annotations[buildv1.BuildPodNameAnnotation]

	return b.clientSet.Pods(updatedBuild.Namespace).Get(ctx, buildPodName, metav1.GetOptions{})
}

// Waits for the build to start and for the underlying build pod containers to be running.
func (b *builder) waitForBuildToStart(ctx context.Context, build *buildv1.Build) error {
	err := wait.Poll(2*time.Second, 5*time.Minute, func() (bool, error) {
		pollBuild, err := b.clientSet.BuildV1Interface.Builds(build.Namespace).Get(ctx, build.Name, metav1.GetOptions{})
		if err != nil {
			return false, fmt.Errorf("could not get build: %w", err)
		}

		return pollBuild.Status.Phase == buildv1.BuildPhaseRunning, nil
	})

	if err != nil {
		return fmt.Errorf("build did not start within a reasonable amount of time")
	}

	// Wait for build container to start
	err = wait.Poll(2*time.Second, 1*time.Minute, func() (bool, error) {
		buildPod, err := b.getPodForBuild(ctx, build)
		if err != nil {
			return false, err
		}

		return isPodReady(buildPod), nil
	})

	if err != nil {
		return fmt.Errorf("build container did not start within a reasonable amount of time")
	}

	return nil
}

// Streams the derived image build logs to a file and/or to stdout, depending
// upon what flags are set.
func (b *builder) streamBuildLogs(t *testing.T, ctx context.Context, build *buildv1.Build) error {
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
		t.Log("streaming build logs to stdout")
		outWriters = append(outWriters, os.Stdout)
	}

	// We're not configured to stream any logs, so stop here.
	if len(outWriters) == 0 {
		t.Log("not capturing build logs")
		return nil
	}

	if err := b.waitForBuildToStart(ctx, build); err != nil {
		return fmt.Errorf("build did not start: %w", err)
	}

	return b.writeBuildLogs(ctx, outWriters, build)
}

// Copies the streamed build logs to the supplied writers. Note: It is the
// callers responsibility to close any open writers after calling this
// function.
func (b *builder) writeBuildLogs(ctx context.Context, writers []io.Writer, build *buildv1.Build) error {
	buildPod, err := b.getPodForBuild(ctx, build)
	if err != nil {
		return fmt.Errorf("could not get build pod for build %s: %w", build.Name, err)
	}

	podLogOpts := &corev1.PodLogOptions{
		Follow:    true,
		Container: buildPod.Spec.Containers[0].Name,
	}

	// Get the io.Reader we read for the build logs
	req := b.clientSet.Pods(buildPod.Namespace).GetLogs(buildPod.Name, podLogOpts)
	podLogs, err := req.Stream(ctx)
	if err != nil {
		return fmt.Errorf("could not stream build pod logs: %w", err)
	}

	defer podLogs.Close()

	// Copy the contents of the io.Reader to our writers by using an
	// io.MultiWriter
	if _, err := io.Copy(io.MultiWriter(writers...), podLogs); err != nil {
		return fmt.Errorf("could not stream build logs to stdout: %w", err)
	}

	return nil
}
