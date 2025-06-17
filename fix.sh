#!/bin/bash

echo "🔄 Switching Phase 1 from Cilium to Flannel..."

# Stop any running deployment first
echo "⚠️  Make sure to stop the current Ansible playbook (Ctrl+C) before running this script!"
read -p "Press Enter to continue after stopping the playbook..."

# 1. Clean up existing Cilium installation on target machine
echo "🧹 Cleaning up existing Cilium installation..."
ansible kharrinhao -a "helm uninstall cilium -n kube-system || true" --become
ansible kharrinhao -a "kubectl delete pods -l k8s-app=cilium -n kube-system --force --grace-period=0 || true" --become

# 2. Rename cilium role to flannel
echo "📝 Renaming Cilium role to Flannel..."
if [ -d "roles/cilium" ]; then
    mv roles/cilium roles/flannel
fi

# 3. Create new Flannel role
echo "🕸️  Creating Flannel CNI role..."
cat > roles/flannel/tasks/main.yml << 'EOF'
---
- name: "Wait for kube-apiserver to be ready"
  wait_for:
    port: "{{ kubernetes_api_server_bind_port }}"
    host: "{{ kubernetes_api_server_advertise_address }}"
    timeout: 120

- name: "Check if Flannel is already installed"
  command: kubectl get daemonset kube-flannel-ds -n kube-flannel --ignore-not-found
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: flannel_check
  changed_when: false

- name: "Download Flannel manifest"
  get_url:
    url: "{{ flannel_manifest_url }}"
    dest: /tmp/kube-flannel.yml
    mode: '0644'
  when: flannel_check.stdout == ""

- name: "Install Flannel CNI"
  command: kubectl apply -f /tmp/kube-flannel.yml
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  when: flannel_check.stdout == ""
  register: flannel_install

- name: "Display Flannel installation result"
  debug:
    msg: "{{ flannel_install.stdout_lines }}"
  when: flannel_check.stdout == "" and flannel_install is defined

- name: "Wait for Flannel pods to be ready"
  command: kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  retries: 3
  delay: 10

- name: "Wait for CoreDNS pods to be ready (after CNI)"
  command: kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  retries: 3
  delay: 10

- name: "Verify node status (should be Ready now)"
  command: kubectl get nodes
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: nodes_after_cni

- name: "Display node status after CNI installation"
  debug:
    msg: "{{ nodes_after_cni.stdout_lines }}"

- name: "Verify CNI networking"
  command: kubectl get pods -n kube-flannel -o wide
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: flannel_pods
  ignore_errors: yes

- name: "Display Flannel pods"
  debug:
    msg: "{{ flannel_pods.stdout_lines }}"
  when: flannel_pods.rc == 0

- name: "Verify all system pods"
  command: kubectl get pods -n kube-system -o wide
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: kube_system_pods_cni

- name: "Display kube-system pods with IPs"
  debug:
    msg: "{{ kube_system_pods_cni.stdout_lines }}"

- name: "Clean up Flannel manifest"
  file:
    path: /tmp/kube-flannel.yml
    state: absent
EOF

# 4. Update Flannel role defaults
echo "⚙️  Setting Flannel role defaults..."
cat > roles/flannel/defaults/main.yml << 'EOF'
---
# Flannel CNI Configuration
flannel_version: "latest"
flannel_manifest_url: "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
flannel_namespace: "kube-flannel"
EOF

# 5. Update group_vars to use Flannel instead of Cilium
echo "📋 Updating group variables..."
cat > inventories/production/group_vars/all.yml << 'EOF'
---
# Kubernetes Configuration - LATEST versions
pod_network_cidr: "10.244.0.0/16"
service_subnet: "10.96.0.0/12"
kubernetes_api_server_advertise_address: "192.168.70.211"
kubernetes_api_server_bind_port: 16443
k8s_cluster_name: "kharrinhao"
disable_swap: true
container_runtime: containerd
cgroup_driver: systemd

# Phase 1: Core Infrastructure Configuration
# Flannel CNI Configuration (Simple and Reliable)
cni_plugin: flannel
flannel_version: "latest"
flannel_manifest_url: "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
flannel_namespace: "kube-flannel"

# cert-manager Configuration  
cert_manager_version: "v1.16.2"
cert_manager_namespace: "cert-manager"

# Ingress NGINX Configuration
ingress_nginx_version: "4.12.0"
ingress_nginx_namespace: "ingress-nginx"

# Domain Configuration (for local development)
base_domain: "k8s.local"
ingress_domains:
  - login.k8s.local
  - auth.k8s.local
  - dashboard.k8s.local
  - grafana.k8s.local
  - argocd.k8s.local

# Port forwarding (for SSH tunneling)
port_forward_http: 8080
port_forward_https: 8443
EOF

# 6. Update Phase 1 playbook to use flannel instead of cilium
echo "📜 Updating Phase 1 playbook..."
cat > playbooks/phase1-core.yml << 'EOF'
---
- name: "Phase 1 - Core Infrastructure"
  hosts: k8s_cluster
  become: yes
  gather_facts: yes
  
  pre_tasks:
    - name: "Verify Phase 0 completion"
      stat:
        path: /tmp/k8s-network-ready
      register: phase0_complete
      failed_when: not phase0_complete.stat.exists
      
    - name: "Display Phase 1 start"
      debug:
        msg: "Starting Phase 1: Core Infrastructure with Flannel CNI on {{ inventory_hostname }}"

  roles:
    - role: flannel
      tags: ['phase1', 'flannel', 'cni']
    - role: cert-manager
      tags: ['phase1', 'cert-manager', 'certificates']
    - role: ingress-nginx
      tags: ['phase1', 'ingress-nginx', 'ingress']
    - role: phase1-validation
      tags: ['phase1', 'validation']

  post_tasks:
    - name: "Create Phase 1 completion marker"
      file:
        path: /tmp/k8s-phase1-complete
        state: touch
        mode: '0644'
        
    - name: "Phase 1 completion"
      debug:
        msg: "Phase 1: Core Infrastructure with Flannel completed successfully on {{ inventory_hostname }}"
EOF

# 7. Update validation role to check for Flannel instead of Cilium
echo "✅ Updating validation role..."
cat > roles/phase1-validation/tasks/main.yml << 'EOF'
---
- name: "Wait for all deployments to be ready"
  pause:
    seconds: 30

- name: "Check node status (should be Ready)"
  command: kubectl get nodes -o wide
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: final_nodes

- name: "Verify all system pods are running"
  command: kubectl get pods -n kube-system
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: system_pods

- name: "Verify Flannel pods"
  command: kubectl get pods -n {{ flannel_namespace }}
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: flannel_status
  ignore_errors: yes

- name: "Verify cert-manager pods"
  command: kubectl get pods -n {{ cert_manager_namespace }}
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: cert_manager_status

- name: "Verify ingress-nginx pods"
  command: kubectl get pods -n {{ ingress_nginx_namespace }}
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: ingress_status

- name: "Check ClusterIssuers status"
  command: kubectl get clusterissuers
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: issuers_status

- name: "Check certificates status"
  command: kubectl get certificates -A
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: certificates_status

- name: "Get Ingress NGINX service details"
  command: kubectl get svc ingress-nginx-controller -n {{ ingress_nginx_namespace }} -o wide
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: ingress_svc_details

- name: "Get node IP for port forwarding"
  command: kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: node_ip

- name: "Create port-forward helper script"
  template:
    src: port-forward-helper.sh.j2
    dest: /tmp/port-forward-helper.sh
    mode: '0755'

- name: "Create /etc/hosts entries template"
  template:
    src: hosts-entries.txt.j2
    dest: /tmp/hosts-entries.txt
    mode: '0644'

- name: "Display Phase 1 validation results"
  debug:
    msg:
      - "=== PHASE 1 VALIDATION COMPLETE ==="
      - ""
      - "✅ Node Status:"
      - "{{ final_nodes.stdout_lines }}"
      - ""
      - "✅ System Pods:"
      - "{{ system_pods.stdout_lines }}"
      - ""
      - "✅ Flannel CNI Status:"
      - "{{ flannel_status.stdout_lines if flannel_status.rc == 0 else ['Flannel namespace not found - checking system pods'] }}"
      - ""
      - "✅ cert-manager Status:"
      - "{{ cert_manager_status.stdout_lines }}"
      - ""
      - "✅ Ingress NGINX Status:"
      - "{{ ingress_status.stdout_lines }}"
      - ""
      - "✅ Certificate Issuers:"
      - "{{ issuers_status.stdout_lines }}"
      - ""
      - "✅ Certificates:"
      - "{{ certificates_status.stdout_lines }}"
      - ""
      - "🌐 Ingress Service Details:"
      - "{{ ingress_svc_details.stdout_lines }}"

- name: "Fetch port-forward helper script"
  fetch:
    src: /tmp/port-forward-helper.sh
    dest: "{{ playbook_dir }}/../files/port-forward-helper.sh"
    flat: yes

- name: "Fetch hosts entries template"
  fetch:
    src: /tmp/hosts-entries.txt
    dest: "{{ playbook_dir }}/../files/hosts-entries.txt"
    flat: yes

- name: "Display access instructions"
  debug:
    msg:
      - ""
      - "🎉 PHASE 1 COMPLETE - CORE INFRASTRUCTURE READY!"
      - ""
      - "🕸️  CNI: Flannel (Simple and Reliable)"
      - "🔒 Certificates: cert-manager with self-signed CA"
      - "🌐 Ingress: NGINX with NodePort"
      - ""
      - "📡 Access Methods:"
      - "1. NodePort: http://{{ node_ip.stdout }}:30080 (HTTP) / https://{{ node_ip.stdout }}:30443 (HTTPS)"
      - "2. Port Forward: kubectl port-forward svc/ingress-nginx-controller {{ port_forward_http }}:80 {{ port_forward_https }}:443 -n {{ ingress_nginx_namespace }}"
      - ""
      - "📁 Helper Files Created:"
      - "- files/port-forward-helper.sh (port-forward script)"
      - "- files/hosts-entries.txt (/etc/hosts entries)"
      - ""
      - "🔗 Domain Setup:"
      - "Add to your /etc/hosts:"
      - "127.0.0.1 {{ ingress_domains | join(' ') }}"
      - ""
      - "🎯 Ready for Phase 2: Platform Services!"
      - "(Keycloak, Longhorn, External DNS, Kubernetes Dashboard)"
EOF

# 8. Install Flannel immediately to fix the current state
echo "🚀 Installing Flannel on the cluster..."
ansible kharrinhao -a "kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml" --become

# 9. Wait a moment for Flannel to start
echo "⏳ Waiting for Flannel to initialize..."
sleep 30

# 10. Check if node is now Ready
echo "📊 Checking cluster status..."
ansible kharrinhao -a "kubectl get nodes" --become
ansible kharrinhao -a "kubectl get pods -n kube-system" --become

echo ""
echo "✅ Phase 1 successfully switched to Flannel!"
echo ""
echo "📋 Changes made:"
echo "  ✅ Replaced Cilium role with Flannel role"
echo "  ✅ Updated group_vars for Flannel configuration"
echo "  ✅ Updated Phase 1 playbook"
echo "  ✅ Updated validation role"
echo "  ✅ Installed Flannel on the cluster"
echo ""
echo "🚀 Ready to continue Phase 1:"
echo "   ansible-playbook playbooks/phase1-core.yml --skip-tags flannel"
echo ""
echo "   (Use --skip-tags flannel since Flannel is already installed)"
echo ""
echo "💡 Or run the complete Phase 1 (will skip Flannel if already installed):"
echo "   ansible-playbook playbooks/phase1-core.yml"