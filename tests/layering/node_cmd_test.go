package e2e_test

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/openshift/machine-config-operator/test/framework"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/remotecommand"
	"k8s.io/kubectl/pkg/scheme"
)

// An error that may occur when executing a command
type NodeCmdError struct {
	CmdResult
	execErr error
}

func (n *NodeCmdError) Error() string {
	return fmt.Sprintf("error: %s\n%s", n.execErr, n.String())
}

func (n *NodeCmdError) Unwrap() error {
	return n.execErr
}

// Contains the output of a command
type CmdResult struct {
	Command  []string
	Stdin    []byte
	Stdout   []byte
	Stderr   []byte
	Duration time.Duration
}

func (c *CmdResult) String() string {
	sb := &strings.Builder{}

	if len(c.Command) != 0 {
		fmt.Fprintln(sb, "command:", strings.Join(c.Command, " "))
	}

	if len(c.Stdin) != 0 {
		fmt.Fprintln(sb, "stdin:")
		if _, err := sb.Write(c.Stdin); err != nil {
			panic(err)
		}
	} else {
		fmt.Fprintln(sb, "stdin: <empty>")
	}

	if len(c.Stdout) != 0 {
		fmt.Fprintln(sb, "stdout:")
		if _, err := sb.Write(c.Stdout); err != nil {
			panic(err)
		}
	} else {
		fmt.Fprintln(sb, "stdout: <empty>")
	}

	if len(c.Stderr) != 0 {
		fmt.Fprintln(sb, "stderr:")
		if _, err := sb.Write(c.Stderr); err != nil {
			panic(err)
		}
	} else {
		fmt.Fprintln(sb, "stderr: <empty>")
	}

	fmt.Fprintf(sb, "took %v\n", c.Duration)

	return sb.String()
}

// Options to use while executing a command on a node
type NodeCmdOpts struct {
	// The actual command itself
	Command []string
	// How many retries, if any
	Retries int
	// A function that determines if a retry is successful
	RetryCheckFunc func(int, *CmdResult, error) bool
	// The stdin to give to the command (optional)
	Stdin io.Reader
	// The stdout emitted from the command (optional)
	// Useful for capturing stdout someplace else
	Stdout io.Writer
	// The stderr emitted from the command (optional)
	// Useful for capturing stderr someplace else
	Stderr io.Writer
}

// Holds the command runner implementation
type NodeCmdRunner struct {
	node      *corev1.Node
	clientSet *framework.ClientSet
	namespace string
}

// One-shot that execs a command on an arbitrary node in the default namespace
func ExecCmdOnNode(cs *framework.ClientSet, node *corev1.Node, cmd []string) (*CmdResult, error) {
	return NewNodeCmdRunner(cs, node, mcoNamespace).Run(cmd)
}

// Creates a reusable command runner object
func NewNodeCmdRunner(cs *framework.ClientSet, node *corev1.Node, namespace string) *NodeCmdRunner {
	return &NodeCmdRunner{
		node:      node,
		clientSet: cs,
		namespace: namespace,
	}
}

// Runs the command without additional options
func (n *NodeCmdRunner) Run(cmd []string) (*CmdResult, error) {
	return n.RunWithOpts(NodeCmdOpts{Command: cmd})
}

// Runs the command with the additional options including retrying
func (n *NodeCmdRunner) RunWithOpts(runOpts NodeCmdOpts) (*CmdResult, error) {
	return n.runAndMaybeRetry(runOpts)
}

// Creates a pod on the target node in the given namespace to run the command in.
func (n *NodeCmdRunner) createCmdPod() (*corev1.Pod, error) {
	containerName := "cmd-container"

	var user int64 = 0
	privileged := true
	hostPathDirectoryType := corev1.HostPathDirectory

	// This PodSpec was largely cribbed from the output of
	// $ oc debug node/<nodename> -o yaml
	cmdPodSpec := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			GenerateName: "cmd-pod-",
			Namespace:    n.namespace,
		},
		TypeMeta: metav1.TypeMeta{
			Kind:       "Pod",
			APIVersion: "v1",
		},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{
				{
					Name: containerName,
					Command: []string{
						"/bin/sh",
					},
					Image: "image-registry.openshift-image-registry.svc:5000/openshift/tools:latest",
					SecurityContext: &corev1.SecurityContext{
						Privileged: &privileged,
						RunAsUser:  &user,
					},
					Stdin:     true,
					StdinOnce: true,
					TTY:       true,
					VolumeMounts: []corev1.VolumeMount{
						{
							Name:      "host",
							MountPath: "/host",
						},
					},
				},
			},
			HostNetwork:   true,
			HostPID:       true,
			NodeName:      n.node.Name,
			RestartPolicy: corev1.RestartPolicyNever,
			Volumes: []corev1.Volume{
				{
					Name: "host",
					VolumeSource: corev1.VolumeSource{
						HostPath: &corev1.HostPathVolumeSource{
							Path: "/",
							Type: &hostPathDirectoryType,
						},
					},
				},
			},
		},
	}

	return n.clientSet.Pods(cmdPodSpec.Namespace).Create(context.TODO(), cmdPodSpec, metav1.CreateOptions{})
}

// Waits for the pod to become ready so we can exec into it. The long timeout
// is needed for when the pod takes longer to be scheduled on the node
// post-reboot.
func (n *NodeCmdRunner) waitForCmdPodToBeReady(pod *corev1.Pod) (*corev1.Pod, error) {
	err := wait.Poll(1*time.Second, 3*time.Minute, func() (bool, error) {
		p, err := n.clientSet.Pods(pod.Namespace).Get(context.TODO(), pod.Name, metav1.GetOptions{})
		if err != nil {
			return false, nil
		}

		if p == nil {
			return false, nil
		}

		return isPodReady(p), nil
	})

	if err != nil {
		return nil, fmt.Errorf("timed out while creating command pod: %w", err)
	}

	return n.clientSet.Pods(pod.Namespace).Get(context.TODO(), pod.Name, metav1.GetOptions{})
}

// Creates a new command pod and waits until it is ready.
func (n *NodeCmdRunner) getCmdPodAndWait() (*corev1.Pod, error) {
	cmdPod, err := n.createCmdPod()
	if err != nil {
		return nil, fmt.Errorf("could not create command pod: %w", err)
	}

	return n.waitForCmdPodToBeReady(cmdPod)
}

// Runs the command, optionally retrying for as many times as is necessary.
// This will create a new pod, exec into it to run the command, then terminate
// the pod at the very end. If no RetryCheckFunc is provided, the default will
// be to run until the command no longer returns an error.
func (n *NodeCmdRunner) runAndMaybeRetry(runOpts NodeCmdOpts) (*CmdResult, error) {
	// We can't run this command.
	if len(runOpts.Command) == 0 {
		return nil, fmt.Errorf("zero-length command passed")
	}

	// Gets a pod and waits for it to be ready.
	cmdPod, err := n.getCmdPodAndWait()
	if err != nil {
		return nil, fmt.Errorf("could not create command pod: %w", err)
	}

	defer func() {
		// Delete the pod when we're finished.
		n.clientSet.Pods(cmdPod.Namespace).Delete(context.TODO(), cmdPod.Name, metav1.DeleteOptions{})
	}()

	// We don't have any retries, so just run the command.
	if runOpts.Retries <= 1 {
		return n.run(runOpts, cmdPod)
	}

	// Default is to keep retrying until we no longer get an error
	retryFunc := func(_ int, _ *CmdResult, runErr error) bool {
		return runErr == nil
	}

	if runOpts.RetryCheckFunc != nil {
		retryFunc = runOpts.RetryCheckFunc
	}

	var result *CmdResult = nil

	// Retry the command for the specified retries.
	for i := 1; i <= runOpts.Retries; i++ {
		runResult, runErr := n.run(runOpts, cmdPod)
		if retryFunc(i, runResult, runErr) {
			return runResult, nil
		}
	}

	return result, fmt.Errorf("max retries (%d) reached", runOpts.Retries)
}

// Actually runs the command via an exec. This implementation was mostly
// cribbed from
// https://github.com/kubernetes/kubectl/blob/master/pkg/cmd/exec/exec.go
func (n *NodeCmdRunner) run(runOpts NodeCmdOpts, cmdPod *corev1.Pod) (*CmdResult, error) {
	restClient := n.clientSet.CoreV1Interface.RESTClient()

	execOpts := &corev1.PodExecOptions{
		Container: cmdPod.Spec.Containers[0].Name,
		Command:   getCommandToRun(runOpts.Command),
		Stdin:     runOpts.Stdin != nil,
		Stdout:    true,
		Stderr:    true,
		TTY:       false,
	}

	req := restClient.Post().
		Resource("pods").
		Name(cmdPod.Name).
		Namespace(cmdPod.Namespace).
		SubResource("exec")

	req.VersionedParams(execOpts, scheme.ParameterCodec)

	// TODO: Figure out a better way to get the config from our clientset than
	// having to read it back in.
	kubeconfig, err := n.clientSet.GetKubeconfig()
	if err != nil {
		return nil, fmt.Errorf("could not get kubeconfig: %w", err)
	}

	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return nil, fmt.Errorf("could not get config: %w", err)
	}

	exec, err := remotecommand.NewSPDYExecutor(config, "POST", req.URL())
	if err != nil {
		return nil, fmt.Errorf("could not get command executor: %w", err)
	}

	stdinBuf := bytes.NewBuffer([]byte{})
	stdoutBuf, stdout := getWriterAndBuffer(runOpts.Stdout)
	stderrBuf, stderr := getWriterAndBuffer(runOpts.Stderr)

	streamOpts := remotecommand.StreamOptions{
		Stdout: stdout,
		Stderr: stderr,
		Tty:    false,
	}

	// Wire in stdin using io.TeeReader so its contents are available in the result object.
	if runOpts.Stdin != nil {
		streamOpts.Stdin = io.TeeReader(runOpts.Stdin, stdinBuf)
	}

	// Run the actual command
	start := time.Now()
	err = exec.Stream(streamOpts)
	end := time.Since(start)

	results := CmdResult{
		Command:  runOpts.Command,
		Duration: end,
		Stdin:    stdinBuf.Bytes(),
		Stdout:   stdoutBuf.Bytes(),
		Stderr:   stderrBuf.Bytes(),
	}

	if err != nil {
		err = &NodeCmdError{
			CmdResult: results,
			execErr:   err,
		}
	}

	return &results, err
}

// Creates a new buffer and io.MultiWriter so we can collect stdin / stderr to
// multiple places simultaneously.
func getWriterAndBuffer(w io.Writer) (*bytes.Buffer, io.Writer) {
	buf := bytes.NewBuffer([]byte{})
	if w == nil {
		return buf, buf
	}

	return buf, io.MultiWriter(buf, w)
}

// Prepends chroot /host onto the command we want to run.
func getCommandToRun(cmd []string) []string {
	if strings.HasPrefix(strings.Join(cmd, " "), "chroot /host") {
		return cmd
	}

	return append([]string{"chroot", "/host"}, cmd...)
}

// Determines if the command pod is ready. These checks might be a little
// heavy-handed, but they work well.
func isPodReady(pod *corev1.Pod) bool {
	// Check that the pod is not in the running phase
	if pod.Status.Phase != corev1.PodRunning {
		return false
	}

	// Check all the pod conditions
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodInitialized && condition.Status != "True" {
			return false
		}

		if condition.Type == corev1.PodScheduled && condition.Status != "True" {
			return false
		}

		if condition.Type == corev1.PodReady && condition.Status != "True" {
			return false
		}

		if condition.Type == corev1.ContainersReady && condition.Status != "True" {
			return false
		}
	}

	// Check all the pod container statuses
	for _, status := range pod.Status.ContainerStatuses {
		// The container status is still waiting
		if status.State.Waiting != nil {
			return false
		}

		// The container was terminated
		if status.State.Terminated != nil {
			return false
		}

		// The container isn't running
		if status.State.Running == nil {
			return false
		}

		// This is nil, meaning we haven't started yet
		if status.Started == nil {
			return false
		}

		// We haven't started the container yet
		if *status.Started != true {
			return false
		}

		// We started the container but we're not ready yet
		if status.Ready != true {
			return false
		}
	}

	// If we've made it here, the pod is ready.
	return true
}
