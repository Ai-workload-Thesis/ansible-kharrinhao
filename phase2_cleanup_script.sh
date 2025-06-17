#!/bin/bash

echo "🧹 Complete Phase 2 Cleanup Script"
echo "=================================="

# Set kubeconfig
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "1. 🕵️ Checking current Phase 2 namespaces..."
kubectl get namespaces | grep -E "(keycloak|kubernetes-dashboard|longhorn)" || echo "No Phase 2 namespaces found"

echo ""
echo "2. 🛑 Removing Helm releases..."

# Remove Helm releases first
echo "   📦 Removing Keycloak Helm release..."
helm uninstall keycloak -n keycloak 2>/dev/null || echo "   ✅ Keycloak Helm release not found"

echo "   📦 Removing Dashboard Helm release..."
helm uninstall kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || echo "   ✅ Dashboard Helm release not found"

echo "   📦 Removing Longhorn Helm release..."
helm uninstall longhorn -n longhorn-system 2>/dev/null || echo "   ✅ Longhorn Helm release not found"

echo ""
echo "3. 🗑️ Force cleaning namespace resources..."

# Function to force cleanup a namespace
cleanup_namespace() {
    local ns=$1
    echo "   🧽 Cleaning namespace: $ns"
    
    if kubectl get namespace $ns 2>/dev/null; then
        # Delete all resources in the namespace
        kubectl delete all --all -n $ns --force --grace-period=0 2>/dev/null || true
        kubectl delete pvc --all -n $ns --force --grace-period=0 2>/dev/null || true
        kubectl delete secrets --all -n $ns --force --grace-period=0 2>/dev/null || true
        kubectl delete configmaps --all -n $ns --force --grace-period=0 2>/dev/null || true
        kubectl delete serviceaccounts --all -n $ns --force --grace-period=0 2>/dev/null || true
        kubectl delete ingress --all -n $ns --force --grace-period=0 2>/dev/null || true
        kubectl delete networkpolicies --all -n $ns --force --grace-period=0 2>/dev/null || true
        
        # Remove finalizers from namespace
        kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        
        # Force delete namespace
        kubectl delete namespace $ns --force --grace-period=0 2>/dev/null || true
        
        echo "   ⏳ Waiting for $ns namespace cleanup..."
        sleep 10
    else
        echo "   ✅ Namespace $ns not found"
    fi
}

# Clean up all Phase 2 namespaces
cleanup_namespace "keycloak"
cleanup_namespace "kubernetes-dashboard"
cleanup_namespace "longhorn-system"

echo ""
echo "4. 🧼 Cleaning up cluster-wide resources..."

# Remove cluster-wide resources that might be left behind
echo "   🗑️ Cleaning ClusterRoleBindings..."
kubectl delete clusterrolebinding dashboard-admin 2>/dev/null || true
kubectl delete clusterrolebinding keycloak-admin 2>/dev/null || true

echo "   🗑️ Cleaning ClusterRoles..."
kubectl delete clusterrole kubernetes-dashboard 2>/dev/null || true

echo "   🗑️ Cleaning StorageClasses..."
kubectl delete storageclass longhorn 2>/dev/null || true
kubectl delete storageclass longhorn-static 2>/dev/null || true

echo "   🗑️ Cleaning any remaining ingresses..."
kubectl delete ingress keycloak-ingress 2>/dev/null || true
kubectl delete ingress kubernetes-dashboard-ingress 2>/dev/null || true
kubectl delete ingress longhorn-ingress 2>/dev/null || true

echo ""
echo "5. ⏳ Final wait for complete cleanup..."
sleep 30

echo ""
echo "6. ✅ Cleanup verification..."
echo "   📊 Current namespaces:"
kubectl get namespaces | grep -E "(keycloak|kubernetes-dashboard|longhorn)" || echo "   🎉 All Phase 2 namespaces cleaned!"

echo "   📦 Remaining Helm releases:"
helm list -A | grep -E "(keycloak|kubernetes-dashboard|longhorn)" || echo "   🎉 All Phase 2 Helm releases cleaned!"

echo ""
echo "🎯 Phase 2 cleanup complete!"
echo ""
echo "💡 Now you can run Phase 2 deployment:"
echo "   ansible-playbook playbooks/phase2-platform.yml --vault-password-file .vault_pass"
echo ""
echo "🔧 Or run individual components:"
echo "   ansible-playbook playbooks/phase2-platform.yml --vault-password-file .vault_pass --tags longhorn"
echo "   ansible-playbook playbooks/phase2-platform.yml --vault-password-file .vault_pass --tags keycloak"
echo "   ansible-playbook playbooks/phase2-platform.yml --vault-password-file .vault_pass --tags kubernetes-dashboard"