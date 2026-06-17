# Kubernetes Learning Repo

> **Author:** Sachin Gate — DevOps Engineer

A hands-on Kubernetes learning repo — YAML examples organized by topic, from Pods to GitOps.

---

## Roadmap

| Status | Topic |
|--------|-------|
| ✅ | Architecture |
| ✅ | Pods |
| ✅ | Deployments |
| ✅ | Services |
| ✅ | Ingress |
| ✅ | ConfigMaps / Secrets |
| ⬜ | Persistent Volumes |
| ⬜ | RBAC |
| ⬜ | Helm |
| ⬜ | GitOps / ArgoCD |

---

## Installation

```bash
sudo bash install_kubernetes.sh
# Choose: 1 = Master node, 2 = Worker node
# Supports: Ubuntu, Debian, Amazon Linux 2023, CentOS, RHEL
```

Installs: `containerd` → `kubeadm` → `kubelet` → `kubectl` → Calico CNI (master only)

---

## 1. Pods

A Pod is the smallest unit in Kubernetes — one or more containers that share the same network and storage.

| File | What it shows |
|------|---------------|
| `Pod/pod1.yaml` | Basic pod with a sidecar container |
| `Pod/pod2.yaml` | Init container — waits for a dependency before starting the main app |
| `Pod/pod3.yaml` | Environment variables pulled from a ConfigMap and a Secret |
| `Pod/pod3-configmap.yaml` | ConfigMap definition (`APP_ENV: production`) |
| `Pod/pod4.yaml` | CPU and memory resource requests and limits |
| `Pod/pod5.yaml` | Liveness and readiness health probes |
| `Pod/pod6.yaml` | Node selector — schedule the pod on a specific node by label |
| `Pod/pod7.yaml` | Pull an image from a private AWS ECR registry |

**Common commands**
```bash
kubectl apply -f Pod/pod1.yaml
kubectl get pods
kubectl describe pod <name>
kubectl logs <name>
kubectl delete pod <name>
```

---

## 2. Deployments

A Deployment wraps your Pods and keeps them healthy automatically — self-healing, scaling, rolling updates, and rollbacks.

```
Deployment → ReplicaSet → Pods
```

| File | What it shows |
|------|---------------|
| `Deployments/deployment.yaml` | Basic deployment — 3 replicas running nginx |
| `Deployments/deployment1.yaml` | RollingUpdate strategy with health probes and a change annotation |

**Common commands**
```bash
# Apply / update
kubectl apply -f Deployments/deployment.yaml

# Scale up or down
kubectl scale deployment my-app --replicas=5

# Watch self-healing (delete a pod and it comes back automatically)
kubectl delete pod <pod-name>
kubectl get pods -w

# Update the container image
kubectl set image deployment/my-app my-app=nginx:1.25
kubectl rollout status deployment/my-app

# Roll back to the previous version
kubectl rollout undo deployment/my-app

# View rollout history
kubectl rollout history deployment/my-app
```

**Key concepts**

| Concept | What it does |
|---------|--------------|
| `replicas` | Number of pods to keep running at all times |
| `selector` | Labels that tell the Deployment which pods belong to it |
| `template` | Blueprint used to create new pods |
| `ReplicaSet` | Auto-created by the Deployment to maintain the pod count |
| `RollingUpdate` | Replace pods one by one — no downtime |
| `Recreate` | Kill all pods then create new ones — has downtime |
| `HPA` | Auto-scale pods based on CPU or memory usage |
| `livenessProbe` | Restart the container if it becomes unhealthy |
| `readinessProbe` | Stop sending traffic to the pod if it's not ready |
| `requests` | Guaranteed minimum resources for the pod |
| `limits` | Maximum resources the pod is allowed to use |

**RollingUpdate strategy**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # how many extra pods can exist during the update
    maxUnavailable: 0  # zero downtime — no pod is removed before a new one is ready
```

---

## 3. Services

A Service gives your pods a stable network address. Pods can die and get new IPs, but the Service IP never changes.

| File | What it shows |
|------|---------------|
| `Services/service1.yaml` | ClusterIP — accessible only inside the cluster |
| `Services/service2.yaml` | NodePort — accessible from outside on a fixed port |
| `Services/service3.yaml` | LoadBalancer — uses a cloud provider load balancer (AWS/GCP/Azure) |

**Service types**

| Type | Who can reach it | Use case |
|------|-----------------|----------|
| `ClusterIP` | Only pods inside the cluster | Internal microservice communication |
| `NodePort` | Anyone who can reach a node IP + port (30000–32767) | Dev / testing access |
| `LoadBalancer` | Public internet via cloud LB | Production workloads on cloud |

**Traffic flow**
```
Internet → AWS ALB/NLB → EC2 Node → NodePort → Pod
```

**Common commands**
```bash
kubectl apply -f Services/service1.yaml
kubectl get services
kubectl describe service <name>
kubectl delete service <name>
```

---

## 4. Ingress

Ingress routes external HTTP/HTTPS traffic to the correct Service inside the cluster — one entry point, many services.

```
Internet → Ingress Controller → Service → Pods
```

**Why use Ingress instead of LoadBalancer?**
- One cloud load balancer for all services (cost saving)
- Domain-based routing (`api.example.com` → api-service, `app.example.com` → app-service)
- TLS/HTTPS termination in one place

---

## 5. RBAC — Role Based Access Control

RBAC controls who can do what on which resources in your Kubernetes cluster.

```
Developer  → can deploy apps in dev namespace
DevOps     → can manage all namespaces
Readonly   → can only view pods/services
Admin      → full cluster access
```

**Key components**

| Component | Scope | What it does |
|-----------|-------|--------------|
| `Role` | Namespace | Defines allowed actions within one namespace |
| `ClusterRole` | Cluster-wide | Defines allowed actions across all namespaces |
| `RoleBinding` | Namespace | Assigns a Role to a user or group |
| `ClusterRoleBinding` | Cluster-wide | Assigns a ClusterRole to a user or group |

**Verbs — what actions can be done**

| Verb | What it allows |
|------|---------------|
| `get` | Read a single resource |
| `list` | Read multiple resources |
| `watch` | Stream changes in real time |
| `create` | Create a new resource |
| `update` | Modify an existing resource |
| `patch` | Partial update of a resource |
| `delete` | Remove a resource |
| `*` | All actions |

**RBAC flow**
```
User / ServiceAccount
        │
        ▼
   API Server  (checks RBAC)
        │
        ▼
   RoleBinding / ClusterRoleBinding
        │
        ▼
   Role / ClusterRole
        │
        ▼
   ✅ Allowed   or   ❌ Forbidden
```

> **Golden Rule** — Always follow Least Privilege. Give users and pods only the minimum permissions they need. Never use `*` verbs in production.

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `CreateContainerConfigError` | Missing ConfigMap or Secret, wrong key name, bad volume mount | Check that the referenced ConfigMap/Secret exists and the key names match |
| `CrashLoopBackOff` | Container starts and immediately crashes | Check `kubectl logs <pod>` for the error |
| `ImagePullBackOff` | Kubernetes can't pull the container image | Verify image name, tag, and registry credentials |
| `Pending` | Pod can't be scheduled onto any node | Check node resources, taints, or node selectors |
