## Pod with Resource Limits

**YAML:** - **[pod-with-resources.yaml](../manifests/day2/pod-with-resources.yaml)**

**Key Points:**  
- `requests` (100m CPU, 64Mi memory) ensure scheduler reserves guaranteed capacity  
- `limits` (200m CPU, 128Mi memory) cap usage to prevent noisy-neighbor issues  
- Memory limit breach --> OOMKill; CPU limit --> throttling  
- Improves bin-packing and cluster resource efficiency  
- Essential for production stability and multi-tenant clusters  

Pod creation & resource config:

![created the pod and checked resource allocation](screenshots/image-1.png)

Live resource usage:

![actual in use resources](screenshots/image-2.png)

---
---


##  Pod with Health Checks (Probes)

**YAML:** - **[pod-with-resources.yaml](../manifests/day2/pod-with-probes.yaml)**

- Probes are defiend as follows 
![probes](screenshots/image.png)

![probes in kubernetes](screenshots/image-4.png)

- verified it works properly 
![cli output](screenshots/image-3.png)

---
---

## Multi-Container Pod (Sidecar Pattern)

**YAML:** - **[multi-container-pod.yaml](../manifests/day2/multi-container-pod.yaml)**

![sidecar container diagram](screenshots/image-7.png)

- Test multi-container pod:

![started the Pod](screenshots/image-5.png)

- Log entries printed after some traffic 

![logs of the sidecar container](screenshots/image-6.png)

---
---

## Pod with Init Container

**YAML:** - **[pod-with-init.yaml](../manifests/day2/pod-with-init.yaml)**

- created and watched the status of the pod 
![terminal output for init container](screenshots/image-8.png)

- Verified thw init container ran properly 
![terminal output for exec command](screenshots/image-9.png)

---
---

## Debugging Pods - Common Issues

- Debugged Failed pod 

![terminal output for failed pod](screenshots/image-10.png)

- Debugged Crashed Pod

![terminal output for crashed pod](screenshots/image-11.png)

---
---

## script: pod_debug.sh

**SCRIPT:** - **[pod_debug.sh](./pod_debug.sh)**

- Fetch pod status, node placement, and IP details
- List all containers with their image
- Show pod conditions (Ready, Initialized, etc.)
- Display recent pod-related events
- Retrieve logs from all containers (configurable tail)
- Support fetching logs from previous (crashed) containers
- Show real-time resource usage (CPU/Memory) if metrics available
- Validate pod existence before execution
- Support custom namespace and kube-context
- Provide helpful debug commands (`describe`, `logs -f`, `exec`)
- Color-coded output for better readability
- Built-in CLI help via `--help`

- created and tested the script for debugging
![script output](screenshots/image-12.png)