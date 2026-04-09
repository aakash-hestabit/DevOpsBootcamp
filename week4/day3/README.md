## Creating Deployment 

**YAML:** - **[nginx-deployment.yaml](../manifests/day3/nginx-deployment.yaml)**


- created and verified the deployment
![created and verified the deployment](screenshots/image.png)

- details of the deployment
![details of the deployment](screenshots/image-1.png)

---
---


## Scaling Applications

- Scaled deployment up
![scaled up](screenshots/image-2.png)

- Scaled deployment down 
![scaled down](screenshots/image-3.png)

---
---


## Rolling Updates

**YAML:** - **[nginx-deployment-v2.yaml](../manifests/day3/nginx-deployment-v2.yaml)**

- Practiced rolling update
![practiced rolling update](screenshots/image-4.png)

---
---

## Rollbacks

- Practiced rollbacks 
![rollback terminal output](screenshots/image-5.png)

---
---

## Update Using kubectl set image

- Practiced Update Using kubectl set image

![practiced rollout using kubectl set image command](screenshots/image-6.png)

---
---

## Deployment with Custom HTML

**YAML:** - **[webapp-deployment.yaml](../manifests/day3/webapp-deployment.yaml)**

- Applied the deployment and then checked the port forewarding in the browser

![screenshot for browser output](screenshots/image-7.png)

---
---

## Script: deployment_manager.sh

**SCRIPT:** - **[deployment_manager.sh](deployment_manager.sh)**

- **list** --> Lists all deployments and their pods in the namespace  
- **status** --> Shows deployment details, ReplicaSets, pods, and rollout status  
- **scale** --> Scales a deployment to the desired number of replicas  
- **update** --> Updates the container image of a deployment  
- **rollback** --> Reverts deployment to previous or specified revision  
- **history** --> Displays rollout history of the deployment  
- **restart** --> Restarts all pods in the deployment (rolling restart)