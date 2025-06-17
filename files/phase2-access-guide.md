# Phase 2 Enterprise Platform - Access Guide

## 🎉 Enterprise Kubernetes Platform Ready!

### 🔌 Port Forward Command (run in separate terminal):
```bash
kubectl --kubeconfig=files/kubeconfig port-forward svc/ingress-nginx-controller 8080:80 8443:443 -n ingress-nginx
```

### 🌍 Add to your WSL /etc/hosts:
```
127.0.0.1 auth.k8s.local dashboard.k8s.local longhorn.k8s.local
```

### 🔗 Access URLs (after port-forward + /etc/hosts):
- **Keycloak Admin**: https://auth.k8s.local:8443
- **Kubernetes Dashboard**: https://dashboard.k8s.local:8443
- **Longhorn Storage**: https://longhorn.k8s.local:8443

### 🔑 Credentials:
- **Keycloak**: admin / admin123!
- **Dashboard**: Use token below or click "Skip"

### 📋 Dashboard Admin Token:
```
eyJhbGciOiJSUzI1NiIsImtpZCI6InNoUEJ0RWFoRzJZajVhU19JWDNPOE9jNFN2V0hUTnNBMU1GSk1GbDYzTFEifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlcm5ldGVzLWRhc2hib2FyZCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJkYXNoYm9hcmQtYWRtaW4tdG9rZW4iLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoiZGFzaGJvYXJkLWFkbWluIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiNzk1NzliODItYzYyMy00YjlhLWIyNGUtNDUxYzk1YjNhNjlhIiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmVybmV0ZXMtZGFzaGJvYXJkOmRhc2hib2FyZC1hZG1pbiJ9.jOHNg5Acw1x8YLZSaejSK5K7mEkPArG0iexH4xwLNiYikGsjUpGOreh8o2mYMeez8zPu_d8NJeVHEV581jBGt-favQcgsUwyE4uT_UHd1BFUSQ7AzcqxsK2Aoaih6Ksp8wPsD-wZYC4nTES6PnAKdlGsCF7RjxL46v6B-Yb-NNiXVNHx0LKg55fYuVfbBMYwXIbDQH2915gSL_4VM6wr3Fwkd1wDCt7a1TehPfXEhuAwqSSsOH4krrNiYaVbHLsp8A6ESK-Ur0u2kY6LS2SQ3INsv8g54ke0sIfcjqobQIYnoJybRtZcj44EXqwaC2CA9rraX6NIxTkjOMB8fBWnhg
```

### 🎯 Enterprise Features Available:
- ✅ Authentication server (Keycloak)
- ✅ Web-based cluster management (Dashboard)
- ✅ Persistent storage (Longhorn)
- ✅ Role-based access control
- ✅ TLS certificates for all services
- ✅ Ready for ML workload deployment

### 📊 Platform Status:
- Longhorn pods running: 19
- Storage classes available: Yes
- Ingresses configured: 4
- Certificates issued: 5

### 🛠️ Troubleshooting:
- If Dashboard shows CrashLoopBackOff, wait a few minutes and check again
- All services should be accessible via the ingress after port-forward
- Use `kubectl logs -n kubernetes-dashboard deployment/kubernetes-dashboard` for Dashboard logs

🎓 Perfect for thesis demonstration!
