# Version Compatibility Matrix

This document tracks the supported versions and compatibility for the runtimes installed on this system.

## 1. Runtime Overview & Support Status
| Runtime | Installed Versions | Default | Status | 
| :--- | :--- | :--- | :--- | :--- |
| **Node.js** | 18.19, 20.11, 22.0 | 20.11 | LTS | 
| **Python** | 3.9, 3.10, 3.11, 3.12 | 3.11 | Stable |
| **PHP** | 7.4, 8.1, 8.2, 8.3 | 8.2 | Active |

---

## 2. Dependency Compatibility
These tools rely on the runtimes above. Ensure the version matches the project requirement.

### PHP & Composer
| PHP Version | Composer Version | Compatibility Note |
| :--- | :--- | :--- |
| **7.4** | 2.2 LTS | Legacy projects only. |
| **8.1+** | 2.7+ | Modern Laravel/Symfony apps. |

### Node.js & Build Tools
| Node Version | NPM Version | Common Pairing |
| :--- | :--- | :--- |
| **18.x** | 9.x | Older React/Angular apps. |
| **20.x** | 10.x | Current industry standard (LTS). |
| **22.x** | 10.x+ | Newer features. |

---

## 3. OS Compatibility (Ubuntu 22.04/24.04)
* **OpenSSL:** PHP 7.4 requires older OpenSSL headers; the Ondrej PPA handles this automatically.
* **System Python:** Do **not** modify `/usr/bin/python3`. Always use the `pyenv` versions (3.9 - 3.12) to avoid breaking system tools like `apt`.

---

## 4. Environment Manager Links
To switch versions based on this matrix, use the following commands:
* **Node:** `nvm use <version>`
* **Python:** `pyenv global <version>`
* **PHP:** `sudo update-alternatives --set php /usr/bin/php<version>`