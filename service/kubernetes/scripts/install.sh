#!/bin/sh
set -e

# Target Kubernetes Version (example: 1.33.0, replace with specific patch if known)
K8S_VERSION_MAJOR_MINOR="1.33"
K8S_FULL_VERSION="1.33.0-1.1" # Assuming standard packaging format, adjust if needed

# Setup Kubernetes apt repository
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management
# Note: The URL structure might change for newer versions. Assuming it follows the pattern.
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION_MAJOR_MINOR}/deb/Release.key" | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION_MAJOR_MINOR}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

apt-get update

# Install containerd
# Using version 1.7.19-1 as it was in the original script. Verify compatibility with K8s 1.33 if possible.
# For K8s 1.33, a newer version like 1.7.x (latest) or even 1.8.x might be preferable if available and validated.
# Let's stick to 1.7.19-1 for now as per original script, assuming it's compatible.
DEBIAN_FRONTEND=noninteractive apt-get install -y containerd.io=1.7.19-1

# Configure containerd
# Ensure /etc/containerd directory exists
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Set SystemdCgroup = true for runc
sed -i 's/\[plugins."io.containerd.grpc.v1.cri".containerd_runtime_runtimes.runc.options\]/\[plugins."io.containerd.grpc.v1.cri".containerd_runtime_runtimes.runc.options\]\n            SystemdCgroup = true/' /etc/containerd/config.toml
# If the above sed fails because SystemdCgroup is already there but false:
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable containerd
systemctl restart containerd

# Install Kubernetes components
apt-get install -y kubelet=${K8S_FULL_VERSION} kubeadm=${K8S_FULL_VERSION} kubectl=${K8S_FULL_VERSION}
apt-mark hold kubelet kubeadm kubectl kubernetes-cni # kubernetes-cni is usually a dependency

echo "Installation of packages done"
