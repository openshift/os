# Enable SWAP on ZRAM

Kubernetes 1.30 will introduce support for swap on nodes, here are the steps required to enable it on OCP. 
Currently (4.16) this requires enabling Techpreview.

## 0 - Requirements

The cluster os image must be at least `416.94.202404120955-0`

## 1 - Enable tech preview

edit the featuregate cluster settings: 

`oc edit featuregate cluster`:

```
apiVersion: config.openshift.io/v1
kind: FeatureGate
metadata:
  name: cluster
spec:
  featureSet: TechPreviewNoUpgrade
```

For more details see [enabling tech preview](https://docs.openshift.com/container-platform/4.15/nodes/clusters/nodes-cluster-enabling-features.html).

Wait for the config to propagate and all the nodes to become ready again.

## 3 Allow kubelet to start with swap

Create the following file: `99-kubelet-swap-config.yaml`
```
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: 99-kubelet-swap-config 
spec:
  machineConfigPoolSelector:
    matchLabels:
      pools.operator.machineconfiguration.openshift.io/worker: ''
  kubeletConfig:
    failSwapOn: false
    memorySwap:
      swapBehavior: LimitedSwap
```

Apply with: `oc apply -f 99-kubelet-swap-config.yaml`

Wait for the config to propagate and all the nodes to become ready again.

## 3 Enable swap on Zram on the worker nodes

Create the following butane config:
```
variant: openshift
version: 4.15.0
metadata:
  name: 99-worker-swap
  labels:
    machineconfiguration.openshift.io/role: worker
storage:
  files:
    - path: /etc/systemd/zram-generator.conf
      mode: 0644
      contents:
        inline: |
          # This config file enables a /dev/zram0 device with the default settings
          [zram0]
```

Convert 99-swap.bu to machineConfig: 
`butane --pretty --strict 99-swap.bu  > 99-swap.yaml`

Then apply: `oc apply -f 99-swap.yaml`

Once again, wait for all the nodes to update. 

## 4 Verify swap is enabled

From a debug terminal : 
```
# zramctl 
NAME       ALGORITHM DISKSIZE DATA COMPR TOTAL STREAMS MOUNTPOINT
/dev/zram0 lzo-rle         4G   4K   80B   12K       4 [SWAP]
```


