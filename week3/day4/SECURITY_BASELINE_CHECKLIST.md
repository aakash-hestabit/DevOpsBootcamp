# Security Baseline Checklist

## Dockerfile Security Checklist

- **[ ] Uses a minimal base image (alpine, slim, distroless)**
  A smaller base image means fewer installed packages and a much smaller attack surface - fewer binaries for an attacker to exploit if they gain shell access.

- **[ ] Uses specific version tags, not `:latest`**
  Pinning to an exact tag (e.g. `node:20-alpine`, `python:3.11-slim`) makes builds reproducible and prevents an unexpected upstream update from silently introducing new vulnerabilities.

- **[ ] Implements a multi-stage build**
  Build tools, compilers, and dev dependencies never make it into the final image, dramatically reducing its size and the number of packages that can harbour CVEs. *(Implemented in `dockerfile_non_root_users/` and `python_security_hardening/`.)*

- **[ ] Runs as a non-root user (`USER` instruction)**
  If a process inside the container is compromised, a non-root UID limits what the attacker can do - they cannot write to system paths or escalate to host-level permissions. *(Implemented: `nodejs` UID 1001, `appuser` UID 10001.)*

- **[ ] Creates a dedicated user and group with fixed UID/GID**
  Fixed numeric IDs (`-u 1001`, `-g 1001`) keep file ownership consistent between the build environment and runtime, preventing silent permission mismatches in mounted volumes.

- **[ ] Sets file ownership with `--chown` on `COPY`**
  Ensures app files are owned by the non-root user from the moment they land in the image, so the process can read them without needing to run as root at any point.

- **[ ] No hardcoded secrets or credentials in the image**
  Secrets baked into an image layer are visible to anyone who can pull the image (`docker history`). Use environment variables, secrets managers, or mounted secret files at runtime instead.

- **[ ] Uses `COPY` instead of `ADD`**
  `ADD` has implicit behaviours (auto-extracting tarballs, fetching remote URLs) that can introduce unexpected files. `COPY` is explicit and auditable.

- **[ ] Sets `PYTHONDONTWRITEBYTECODE` and `PYTHONUNBUFFERED` (Python images)**
  Prevents `.pyc` cache files from accumulating in the image and ensures log output is flushed immediately, which matters for both security auditing and debugging in production.

- **[ ] Exposes only the necessary port**
  Declaring a single `EXPOSE` port documents the intended network interface and discourages accidentally binding unneeded services.

- **[ ] Implements a `HEALTHCHECK` instruction**
  Docker can automatically mark a container as `unhealthy` and orchestrators can restart or remove it, preventing silent failure from causing a security gap (e.g. a crashed auth proxy). *(Implemented in both Node.js and Python images.)*

- **[ ] Adds a `.dockerignore` file**
  Keeps `node_modules`, `.env`, secrets, and local build artefacts out of the build context so they can never accidentally be copied into the image.

---

## Container Runtime Security Checklist

- **[ ] Runs with `--read-only` root filesystem**
  Prevents any process inside the container from writing to application directories, making it impossible for malware to modify binaries or drop persistence scripts.

- **[ ] Mounts `tmpfs` for writable paths only (`--tmpfs /tmp`)**
  Grants the application a small, in-memory writable area without opening the full filesystem. Data is never persisted to disk and disappears on container stop. *(Implemented with `/tmp/runtime-data` in Python image.)*

- **[ ] Drops all capabilities (`--cap-drop ALL`)**
  Linux capabilities are fine-grained root privileges. Dropping all of them removes the ability to perform dangerous operations (raw sockets, kernel module loading, etc.) even if the process is somehow escalated.

- **[ ] Adds back only required capabilities (`--cap-add NET_BIND_SERVICE`)**
  The principle of least privilege - grant only the single capability the application genuinely needs (binding low ports), nothing more.

- **[ ] Uses `--security-opt no-new-privileges:true`**
  Prevents any child process from gaining more privileges than the parent via `setuid`/`setgid` binaries or capabilities bits, closing a common privilege escalation path.

- **[ ] Applies an AppArmor or seccomp profile**
  Profiles like `docker-default` restrict the set of system calls the container may make, providing kernel-level isolation on top of user-space controls.

- **[ ] Configures resource limits (`--memory`, `--cpus`)**
  Caps the blast radius of a runaway process or a DoS attack - a compromised container cannot exhaust all host memory or CPU and bring down neighbouring workloads.

- **[ ] Uses internal Docker networks where possible**
  Containers that do not need to be reachable from the host or the internet should be on an isolated network, reducing the attack surface exposed to external traffic.

- **[ ] Does not use `--privileged` mode**
  Privileged mode gives the container almost full access to the host kernel and devices. There is virtually no legitimate application workload that requires it.

- **[ ] Verifies runtime configuration with `docker inspect`**
  After starting a container, inspecting `HostConfig` confirms that all security flags (read-only, cap-drop, no-new-privileges, resource limits) are actually in effect and have not been overridden.

---

## Image Scanning Checklist

- **[ ] Scanned with Trivy (or equivalent) before deployment**
  Catching known CVEs before an image reaches production is the cheapest time to fix them - no running workload, no incident, no rollback needed.

- **[ ] Scanned with `--severity HIGH,CRITICAL` filter**
  Focusing on the two highest severities keeps the signal-to-noise ratio high and makes the output actionable without being buried in LOW/MEDIUM noise.

- **[ ] CRITICAL vulnerabilities resolved or formally accepted**
  A CRITICAL CVE with a known exploit path should be treated as a blocker. If a fix is not yet available, the risk must be explicitly accepted and documented.

- **[ ] Fixability documented per vulnerability**
  The scan output should show which CVEs have an available fix (`fix=<version>`) versus `NO FIX`, so engineers know which updates to prioritise immediately. *(Implemented in `scan-images.sh` and `node-trivy-demo/scan_image.sh`.)*

- **[ ] Custom application image scanned separately from base image**
  Application dependencies (npm packages, pip packages) can introduce vulnerabilities independent of the OS layer - both layers must be checked. *(Demonstrated with `express-basic:1.0` and `python-secure:1.0`.)*

- **[ ] Consolidated scan report saved to a versioned file**
  A timestamped report (`scan-report-<timestamp>.txt`) provides an audit trail - you can prove what the vulnerability state was at any point in time. *(Implemented in `scan-images.sh`.)*

- **[ ] All local images scanned in one automated pass**
  Running scans manually per image is error-prone. A single script (`scan-images.sh`) that discovers and scans every local image ensures no image is missed.

- **[ ] Image signed and signature verified before deployment (Cosign)**
  Signing with Cosign and verifying before `docker run` ensures that only images you built and approved are ever started - a tampered or injected image will fail verification and be rejected.

- **[ ] Scan re-run after any base image or dependency update**
  New CVEs are published continuously. Updating `node:20-alpine` or bumping an npm/pip package version can introduce or resolve vulnerabilities, so every change should trigger a fresh scan.

- **[ ] Scan integrated or documented in the deployment workflow**
  Scanning should be a gate, not an afterthought. Even without a CI/CD pipeline, documenting the scan step in the deployment checklist ensures it is never skipped.
