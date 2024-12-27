
## Introduction

This is a preview of the environment provisioning project. Currently, the
instructions and scripts encompass provisioning two shell environments: (1) an
Ubuntu LTS WSL2 host that runs the Docker Engine for Linux that has Qemu
integration installed and that has the Qemu arm64 emulator registered and (2) an
Ubuntu-20.04 docker container that uses a native platform base image. Ansible
tasks and a Dockerfile perform the bulk of the provisioning.

Both environments have the ROS2 Desktop and the ROS development tools installed. 
The Ubuntu 20.04 Docker environment runs ROS2 foxy, and the Ubuntu WSL2 
environment runs the version of ROS2 that has tier 1 support for that Ubuntu 
release. If you want to run the same version of ROS2 as Prod runs, you should 
install Ubuntu-20.04 for WSL despite that Ubuntu LTS release being relatively old.



## Instructions


### Step 1. Ensure that WSL2 is installed and updated

```
# PowerShell

wsl --install --no-distribution
wsl --update
```

### Step 2. Verify that an Ubuntu-20.04 distribution is not registered.

```
# PowerShell

wsl --list
```

If the output includes `Ubuntu` or `Ubuntu (Default)`, then run the following
command to determine its version:

```
# PowerShell

wsl -d Ubuntu -e lsb_release --description
```

If neither of the commands above indicates that some version of Ubuntu 20.04 (such
as `Ubuntu-20.04` or `Ubuntu 20.04.1 LTS`) is registered, then you can proceed
to step 2. 

If either of the commands above indicates that you have a prexisting Ubuntu
20.04 distribution, then you have a few options for how to proceed. If you just
want to take a peek at the environment, you can specify Ubuntu-22.04 or
Ubuntu-24.04 in step 3. However, these will install a different version of ROS2
than is currently used in Prod.

If you want to match Prod more closely, you have three fixup options to
provision a vanilla Ubuntu 20.04. As of this writing, it seems that Microsoft
and Canonical have not made it easy to acquire a tarball of a vanilla rootfs for
Ubuntu for WSL.

#### Fixup Option 1 [RECOMMENDED]. Move your Ubuntu 20.04 instance

This option only relies on the wsl tool. The process looks like this:

1. Shutdown the preexisting distribution
2. Export the preexising distribution to a vhdx or a tarball
3. Import the preexsting distribution from the vxdx or the tarball and give it a
   different distribution name
4. After verifying that the newly imported distribution is healthy, unregister
   the preexisting distribution

Below are some example commands. These assume that the preexisting distribution
is using WSL version 2 and that its virtual disk uses the default ext4 filesystem.

```
# PowerShell

wsl --terminate <Distribution Name>
wsl --export <Distribution Name> <Vhdx FileName> --vhd
wsl --import-in-place <Alternative Distribution Name> <Vhdx FileName>
wsl --unregister <Distribution Name>
```

#### Fixup Option 2. Use the `download-rootfs` GitHub Action

This option is probably only approachable if you have prior experience with
GitHub CI. The `download-rootfs` GitHub Action
(`Ubuntu/WSL/.github/actions/download-rootfs@main`) can download a vanilla WSL
tarball to a GitHub CI instance. Then, you can scp the tarball to localhost.

#### Fixup Option 3. Build the `release-info` tool from the Ubuntu WSL repo

This option is probably only approachable if you have prior experience with
building a Golang application using PowerShell. The `release-info` tool
(`https://github.com/ubuntu/WSL/tree/main/wsl-builder/release-info`) can
download a manifest that includes a download URL for a vanilla WSL tarball. Note
that the aformentioned `download-rootfs` GitHub Action uses this `release-info`
tool under the hood. The source code for that Action is in the same repo.

### Step 3. Install Ubuntu-20.04

Assuming that you didn't have a preexisting Ubuntu 20.04 instance or that you
used Fixup Option 1, you can now create a fresh Ubuntu 20.04 instance. Run the
following command:

```
# PowerShell

wsl --install Ubuntu-20.04
```

Eventually, it will prompt you to supply a username and a password. This
username and password don't need to match your Windows username and password.
Typically, a linux username will be all lowercase alphanumeric characters
beginning with an alpha character. If you want a username suggestion, use your
first name in lowercase.

These credentials will not be used to sign-in. Rather, they will be used to
grant access to run privileged system administration commands using sudo.

### Step 4. Provision an ssh keypair

To enable convenient access to GitHub and other remote hosts, we want to use
key-based authentication as described here:

https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent?platform=linux

#### Option 1. Create a new keypair on the WSL2 host

Run the following command on the new Ubuntu-20.04 host. Substitute your email
address, omitting the brackets.

```bash
# WSL Ubuntu-20.04

ssh-keygen -t ed25519 -C '[your email address]'
```

That will prompt you to specify a passphrase to secure the key that is being
created. Note that the setup script that you'll run in Step 7 will configure
this host such that you only have to unlock your key once per bootup of the
distribution, so it's okay to choose a lengthy passphrase.

That command will create a private key file and a public key file with the
appropriate permissions in your `~/.ssh` directory.

#### Option 2. Copy a preexisting keypair

You may already have a keypair registered with GitHub that you've been using for
local development. Here are some commands that you could use to copy it into
place if those files are stored in the mounted filesystem:

```bash
# WSL Ubuntu-20.04

install -m 700 -d ~/.ssh
install -m 600 /mnt/c/[path to private key] -t ~/.ssh
install -m 644 /mnt/c/[path to public key] -t ~/.ssh
```

### Step 5. Add your public key to GitHub

You have two options for how to add your public key to your GitHub account.

#### Option 1 [RECOMMENDED]. Use the GitHub website

See the following instructions:

https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account?platform=windows&tool=webui

#### Option 2 [UNTESTED]. Install the GitHub command line tool and then use it

Add the GitHub CLI package repository and then install the `gh` package as
described here:

https://github.com/cli/cli/blob/trunk/docs/install_linux.md

```bash
# WSL Ubuntu-20.04

(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y
```

Then use `gh` to add your public key to your GitHub account as described here:

https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account?platform=linux&tool=cli

```bash
# WSL Ubuntu-20.04

gh ssh-key add ~/.ssh/id_ed25519.pub --type authentication --title 'Jugglebot dev env'
```

### Step 6. Clone the Jugglebot repo

```bash
# WSL Ubuntu-20.04

sudo apt install git

cd ~ && GIT_SSH_COMMAND="ssh -i ${HOME}/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" git clone git@github.com:joewalp/Jugglebot.git
```

### Step 7. Run the WSL2 environment setup script

Within the WSL2 environment, run the setup script for the WSL2 development
environment while specifying your name and email address that will be configured
in ~/.gitconfig. This will take some time. Midway through its setup, it will
prompt you to enter your Linux account password so that it can install
applications.

```bash
# WSL Ubuntu-20.04

~/Jugglebot/environments/ubuntu-wsl2/setup.sh --ssh-keypair-name id_ed25519 --git-name '[Your full name]' --git-email '[Your email address]'
```

### Step 8. Exit and then start a new terminal session to enable all changes

```bash
# WSL Ubuntu-20.04

exit
```

To start a new terminal session, you have a couple options

#### Option 1 [RECOMMENDED]. Use the Windows Terminal profile

In the dropdown menu of the Windows Terminal tab bar, you'll find an entry for
the newly created distribution.

#### Option 2. Use the wsl tool

```
# PowerShell

wsl -d Ubuntu-20.04
```

### Step 9. Run the Docker container native platform environment build utility

Within the WSL2 environment, run the build utility for the Docker native
platform environment. The run duration of this script depends on the download
speed of your internet connection. It takes roughly 40 minutes on a slow
connection. It does not prompt for passwords, so you don't need to supervise
it.

```zsh
# WSL Ubuntu-20.04

denv build --ssh-keypair-name id_ed25519
```

### Step 10. Try the Docker container native platform environment

The command in Step 9 will print some information about the container that it
has built. After reading that info, run the following command to enter the
Docker container native platform environment.

```zsh
# WSL Ubuntu-20.04

denv exec
```

### Additional things to try

---

#### Task 1. Drive WSL from VSCode for Windows

The WSL extension for VSCode for Windows allows you to drive a WSL environment.
After installing that extension, run the following command from within the WSL
environment:

```zsh
# WSL Ubuntu-20.04

cd ~/Jugglebot && code .
```

That will open a VSCode window that's attached to the WSL environment. You can
save that VSCode workspace locally in Windows to facilitate opening it later.

It's possible also for VSCode for Windows to drive a Ubuntu 20.04 Docker
environment using the Remote SSH extension for VSCode. That already works.
However, providing instructions for how to set up the ssh key management by
Windows to make that workflow convenient is still in progress.

---

#### Task 2. Run SavvyCAN in WSL

You'll find the `install-savvycan` utility in `~/bin`. That script demonstrates
how to use a dedicated Conda environment to build and to run an app that has
different dependencies from your primary Jugglebot project. Running it will
produce ~/bin/SavvyCAN, which will launch the app.

```zsh
# WSL Ubuntu-20.04

install-savvycan
SavvyCAN
```

To see how this works, you can peek at those two Bash scripts.


```zsh
# WSL Ubuntu-20.04

pygmentize -O style=native -g ~/bin/install-savvycan | less -R
pygmentize -O style=native -g ~/bin/SavvyCAN | less -R
```

> Note:
> 
> The second and third lines of each of those scripts aren't essential. They
> make the Bash interpreter more fail-fast and more predictable. The fail-fast
> characteristic tends to make it easier to recover manually when a script fails
> midway. The IFS initialization avoids the issue where the script behavior
> could change based on a previously exported IFS value.

---

#### Task 3. Expose a USB device to WSL

To use your USB ports in WSL, you need to expose them using the usbipd tool as
described here:

https://github.com/dorssel/usbipd-win/blob/v4.3.0/README.md

The process on Windows 11 goes like this:

1. Within PowerShell, use winget to install the usbipd tool.

2. Attach the physical device that you want to use.

3. Within an Administrator PowerShell, use the usbipd tool to identify and to
   bind the device by specifying its busid. This is a one-time operation.

4. Within PowerShell during each Windows session prior to using the device in
   WSL, use the usbipd tool to attach the device to WSL. This will make the
   device available to all of the WSL distributions that have a compatible
   kernel.

5. Within the WSL Ubuntu-20.04 environment, use the lsusb tool to verify that
   you can see the device.

6. [Optional] Install the USBIP Connect extension in VSCode. This will add an
   `Attach` button to the status bar that will enable you to attach any device
   that you had previously exposed via `usbipd bind`.

Here are some example commands:

```
# PowerShell

winget install --interactive --exact dorssel.usbipd-win
```

```
# Administrator PowerShell

usbipd list
usbipd bind --busid <BUSID>
```

```
# PowerShell

usbipd attach --wsl --busid <BUSID>
```

```zsh
# WSL Ubuntu-20.04

lsusb
```

---

## Notes

Each of these environments uses Z Shell (zsh) with Oh My Zsh and the 'clean'
built-in theme. The Python environment is managed by Conda and pip rather than
virtualenv and pip because the conda-forge dependency management makes life
easier.

The Jugglebot repo is checked out separately in each environment. If anyone ends
up using the Docker container environment in tandem with the WSL2 environment
for interactive coding and testing, we may end up mounting the WSL2 Jugglebot
repo into the container. However, I currently consider the Docker native
platform container environment to be a stepping stone toward building the Ubuntu
for arm64 Docker container. The native platform container environment is
considerably faster than the arm64 platform container environment, so I want to
use it for iterating on features before confirming that the same provisioning
and features work within an arm64 platform environment.

## Noteworthy future milestones

- Demonstrate dev environment provisioning on an Ubuntu for arm64 Docker image
  emulated by Qemu. This environment won't be used within a development
  workflow; it's only intended to verify that all of the environment dependences
  are available for arm64.
- Demonstrate ROS2 Foxy startup in Ubuntu for arm64.
- Build a minimal ROS app that uses the Jugglebot fork of Yasmin to provide a
  testbed for example code that doesn't have robot hardware dependencies.
- Demonstrate how to use VSCode for Windows to connect to a Linux environment
  over ssh and to run a unit test in that remote environment.
- On a Windows 11 machine with an Nvidia GPU, demonstrate passthrough of Cuda
  tasks from a guest Linux development environment host where those tasks are
  driven by a Jetson SDK.
