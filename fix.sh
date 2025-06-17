#!/bin/bash

echo "🔧 Fixing cluster-init role to work with latest versions..."

# Fix the cluster-init role
cat > roles/cluster-init/tasks/main.yml << 'EOF'
---
- name: "Check if Kubernetes cluster is already initialized"
  stat:
    path: /etc/kubernetes/admin.conf
  register: cluster_initialized

- name: "Get installed Kubernetes version"
  shell: kubeadm version --output=short | sed 's/v//'
  register: kube_version
  when: not cluster_initialized.stat.exists

- name: "Generate kubeadm config file"
  template:
    src: kubeadm-config.yaml.j2
    dest: /tmp/kubeadm-config.yaml
    mode: '0644'
  when: not cluster_initialized.stat.exists

- name: "Initialize Kubernetes cluster with kubeadm"
  command: >
    kubeadm init 
    --config=/tmp/kubeadm-config.yaml
    --upload-certs
  register: kubeadm_init_output
  when: not cluster_initialized.stat.exists

- name: "Display kubeadm init output"
  debug:
    msg: "{{ kubeadm_init_output.stdout_lines }}"
  when: not cluster_initialized.stat.exists

- name: "Create .kube directory for root"
  file:
    path: /root/.kube
    state: directory
    mode: '0755'

- name: "Copy admin.conf to root's kubeconfig"
  copy:
    src: /etc/kubernetes/admin.conf
    dest: /root/.kube/config
    remote_src: yes
    mode: '0644'

- name: "Create .kube directory for regular user"
  file:
    path: "/home/{{ ansible_user }}/.kube"
    state: directory
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0755'
  when: ansible_user != "root"

- name: "Copy admin.conf to user's kubeconfig"
  copy:
    src: /etc/kubernetes/admin.conf
    dest: "/home/{{ ansible_user }}/.kube/config"
    remote_src: yes
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0644'
  when: ansible_user != "root"

- name: "Remove master taint to allow pods on control plane (single node cluster)"
  command: kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  ignore_errors: yes
  when: not cluster_initialized.stat.exists

- name: "Wait for kube-apiserver to be ready"
  wait_for:
    port: "{{ kubernetes_api_server_bind_port }}"
    host: "{{ kubernetes_api_server_advertise_address }}"
    delay: 10
    timeout: 300

- name: "Verify cluster status"
  command: kubectl get nodes
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: cluster_nodes
  retries: 5
  delay: 10

- name: "Display cluster nodes"
  debug:
    msg: "{{ cluster_nodes.stdout_lines }}"

- name: "Fetch kubeconfig to local machine"
  fetch:
    src: /etc/kubernetes/admin.conf
    dest: "{{ playbook_dir }}/../files/kubeconfig"
    flat: yes
  when: not cluster_initialized.stat.exists
EOF

# Update the kubeadm config template to use the detected version
cat > roles/cluster-init/templates/kubeadm-config.yaml.j2 << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: {{ kubernetes_api_server_advertise_address }}
  bindPort: {{ kubernetes_api_server_bind_port }}
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cgroup-driver: systemd
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v{{ kube_version.stdout }}
clusterName: {{ k8s_cluster_name }}
controlPlaneEndpoint: {{ kubernetes_api_server_advertise_address }}:{{ kubernetes_api_server_bind_port }}
apiServer:
  advertiseAddress: {{ kubernetes_api_server_advertise_address }}
  bindPort: {{ kubernetes_api_server_bind_port }}
  certSANs:
    - {{ kubernetes_api_server_advertise_address }}
    - {{ inventory_hostname }}
    - localhost
    - 127.0.0.1
networking:
  serviceSubnet: {{ service_subnet }}
  podSubnet: {{ pod_network_cidr }}
controllerManager: {}
scheduler: {}
etcd:
  local:
    dataDir: /var/lib/etcd
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: KubeletConfiguration
cgroupDriver: systemd
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
EOF

echo "✅ Cluster-init role fixed!"
echo ""
echo "🚀 Now it will:"
echo "   - Detect the installed Kubernetes version automatically"
echo "   - Use that version in the kubeadm config"
echo "   - Continue with cluster initialization"
echo ""
echo "Ready to deploy:"
echo "   ansible-playbook playbooks/phase0-bootstrap.yml"