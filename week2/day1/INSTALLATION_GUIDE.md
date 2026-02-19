# Runtime Installation Guide

A step-by-step guide for setting up Node.js, Python, and PHP environments on Ubuntu.

---

## 1. Node.js Setup (via NVM)
* Uses Node Version Manager (NVM) to avoid `sudo` for npm and manage version switching.

* **Step 1: Install NVM**
    Downloads the installation script and executes it.
    ```bash
    curl -o- [https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh](https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh) | bash
    ```
* **Step 2: Load Environment**
    Sources the bash configuration to make `nvm` available in the current session.
    ```bash
    source ~/.bashrc
    ```
* **Step 3: Install Versions**
    Installs the specified project runtimes.
    ```bash
    nvm install 18.19.0
    nvm install 20.11.0
    nvm install 22.0.0
    ```
* **Step 4: Set Default**
    Sets `v20.11.0` as the version used in every new terminal.
    ```bash
    nvm alias default 20.11.0
    ```

* Creating an `.nvmrc` file in your project root allows you to run `nvm use` to auto-switch to the correct version.

---

## 2. Python Setup (via Pyenv)
* Compiles and manages isolated Python versions to keep the system Python clean.

* **Step 1: Install Build Dependencies**
    Required system packages to compile Python from source.
    ```bash
    sudo apt update && sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libffi-dev liblzma-dev
    ```
* **Step 2: Install Pyenv**
    Installs the tool to `$HOME/.pyenv`.
    ```bash
    curl [https://pyenv.run](https://pyenv.run) | bash
    ```
* **Step 3: Configure Shell**
    Appends initialization logic to your `.bashrc` or `.profile` so Pyenv shims load automatically.
* **Step 4: Install Python Versions**
    ```bash
    pyenv install 3.9.18
    pyenv install 3.10.13
    pyenv install 3.11.7
    pyenv install 3.12.1
    ```
* **Step 5: Set Global & Tools**
    Sets the global default and upgrades package managers.
    ```bash
    pyenv global 3.11.7
    pip install --upgrade pip virtualenv pipenv
    ```

* we should always use `virtualenv` or `venv` for projects to prevent dependency conflicts across different Python apps.

---

## 3. PHP Setup (via Ondrej Sury PPA)
* Installs multiple PHP versions side-by-side using the industry-standard repository.

* **Step 1: Add PPA Repository**
    Adds the repository containing all major PHP versions.
    ```bash
    sudo add-apt-repository ppa:ondrej/php -y && sudo apt update
    ```
* **Step 2: Install Versions & Modules**
    Installs PHP, the FPM service (for Nginx), and essential extensions (curl, mysql, mbstring).
    ```bash
    sudo apt install -y php{7.4,8.1,8.2,8.3}-{fpm,cli,common,curl,mbstring,xml,mysql}
    ```
* **Step 3: Set Default CLI**
    Points the `php` command to the 8.2 binary.
    ```bash
    sudo update-alternatives --set php /usr/bin/php8.2
    ```
* **Step 4: Install Composer**
    Installs the dependency manager globally.
    ```bash
    curl -sS [https://getcomposer.org/installer](https://getcomposer.org/installer) | php
    sudo mv composer.phar /usr/local/bin/composer
    ```
    
* PHP-FPM runs as a background service. If we modify settings in `/etc/php/templates`, we must restart the service: `sudo systemctl restart php8.2-fpm`.

---

## Final Verification
to verify the installation we can run the following commands -
```bash
node -v      # check node
python -V    # check python
php -v       # check php
composer -V  # check composer
```