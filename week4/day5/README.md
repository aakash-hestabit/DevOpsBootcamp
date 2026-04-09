##  Enable Ingress Controller in Minikube

- #### nable nginx ingress controller
![ingress added](screenshots/image.png)

- #### Verified Ingress

![terminal output](screenshots/image-1.png)

---
---

## Create Applications for Ingress Demo

#### **YAML:** - **[ingress-apps.yaml](../manifests/day5/ingress-apps.yaml)**

- #### applied and verified the deployments and services

![terminal output](screenshots/image-2.png)

---
---

## Path-Based Ingress

#### **YAML:** - **[ingress-path-based.yaml](../manifests/day5/ingress-path-based.yaml)**

- #### Apply and Check ingress

![terminal output](screenshots/image-3.png)

- #### Test each path
![each path is resolved correctly](screenshots/image-4.png)

---
---

## Host-Based Ingress

#### **YAML:** - **[ingress-host-based.yaml](../manifests/day5/ingress-host-based.yaml)**

- #### Apply and Verify

![terminal output](screenshots/image-5.png)

- #### Added the hosts
![added to hosts](screenshots/image-6.png)

- #### Test each host

- - ##### www.bootcamp.local 

![browser response](screenshots/image-7.png)

![terminal response](screenshots/image-8.png)

<hr/>

- - ##### api.bootcamp.local

![browser response](screenshots/image-9.png)

![terminal response](screenshots/image-10.png)

<hr/>

- - ##### admin.bootcamp.local 

![browser response](screenshots/image-11.png)

![terminal response](screenshots/image-12.png)

---
---


## ingress_test.sh 

#### **SCRIPT:** - **[ingress_test.sh](ingress_test.sh)**


- Validates ingress controller availability  
- Lists all ingress resources in the namespace  
- Detects cluster/node IP for testing  
- Tests host-based and path-based routing rules  
- Performs HTTP connectivity checks with retries and timeout  
- Supports custom namespace, context, and ingress controller namespace  
- Handles missing ingress/resources gracefully  
- Fetches recent ingress controller logs for debugging  
- Provides CLI help with usage and examples (`--help`)

  - #### Script Output
![script output](screenshots/image-13.png)