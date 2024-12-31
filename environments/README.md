
## Introduction

This is a preview of the environment provisioning project. Currently, the
instructions and scripts encompass provisioning three shell environments: (1) an
Ubuntu LTS WSL2 host that runs the Docker Engine for Linux that has Qemu
integration installed and that has the Qemu arm64 emulator registered, (2) an
Ubuntu-20.04 docker container that uses a native platform base image and (3) an
Ubuntu-20.04 docker container that uses an arm64 base image.

All environments have the ROS2 Desktop and the ROS development tools installed.
Each environment runs the version of ROS2 that has tier 1 support for its Ubuntu
release. If you want to run the same version of ROS2 as Prod runs, you should
install Ubuntu-20.04 for WSL despite that Ubuntu LTS release being relatively
old.


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

This option only relies on the `wsl` tool. The process looks like this:

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
beginning with an alpha character. If you want a username suggestion, either (a)
use your first name (e.g. joe) or (b) use your first initial followed by
your last name (e.g. jwalp).

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
in `~/.gitconfig`. This will take some time. Midway through its setup, it will
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

#### Option 2. Use the `wsl` tool

```
# PowerShell

wsl -d Ubuntu-20.04
```

### Step 9 [Optional]. Configure Docker Desktop for Windows to use WSL

It's helpful to visualize Docker as having three major distributables: Docker Engine,
Docker CLI and Docker Desktop. The Docker Engine is responsible for hosting
containers and volumes. The Docker CLI is what our scripts use to command the
Docker Engine. The Docker Desktop is a bundle that includes a Docker Engine and
a graphical interface that covers some of the same command functions as Docker
CLI and that also enables browsing online Docker-related resources such as the Docker
images that have been published by other people.

The Docker Engine that is bundled with Docker Desktop for Windows is somewhat
less performant than the Docker Engine that we installed during Step 7.
Thankfully, we can configure Docker Desktop to use the WSL 2 Docker Engine. In
fact, Docker Desktop can use multiple WSL 2 Docker Engines simultaneously, but
we will only configure one.

After installing/updating Docker Desktop for Windows, navigate to the
following checkbox:

`Gear icon` > `General` sidebar tab > `General` Settings pane > `Use the WSL 2
based engine` checkbox

Enable that checkbox. Do not apply changes.

Directly beneath that checkbox, you'll find another checkbox:

`Add the *.docker.internal names to the host's /etc/hosts file (Requires
password)`

Currently, this project doesn't depend on that `/etc/hosts` feature. Either
unchecked or checked is fine.

Next, navigate to the following pane in the Settings:

`Resources` sidebar tab > `WSL integration` sidebar menu item > `Resources WSL
Integration` Settings pane

There, you will see an entry for Ubuntu-20.04. Enable that switch.

Depending on whether Ubuntu-20.04 is also your default WSL distro, the checkbox
above that's labeled `Enable integration with my default WSL distro` may be
equivalent to the aformentioned switch. Using the switch to avoids any
ambiguity about which WSL distributions are being
integrated.

Now, click the `Apply & Restart` button.

### Step 10. Run the Docker container native platform environment build utility

Within the WSL2 environment, run the build utility for the Docker native
platform environment. The run duration of this script depends on the download
speed of your internet connection. It takes roughly 40 minutes on a slow
connection. It does not prompt for passwords, so you don't need to supervise
it.

```zsh
# WSL Ubuntu-20.04

denv build --ssh-keypair-name id_ed25519
```

If you performed Step 9, you will be able to use Docker Desktop to monitor the
ongoing `Active build` that denv has initiated:

`Builds` sidebar tab > `Builds` pane > `Active builds` tab > Click on the
in-progress item > `Logs` tab of the `Builds / environments/ubuntu-docker` pane


### Step 11. Try the Docker container native platform environment

The command in Step 10 will print some information about the container that it
has built. After reading that info, run the following command to enter the
Docker container native platform environment.

```zsh
# WSL Ubuntu-20.04

denv exec
```

You can also connect to that environment via ssh:

```zsh
# WSL Ubuntu-20.04

ssh docker-native-env
```

> Note:
>
> If you're interested in more detail about how that ssh command works, see the
> `docker-native-env` host definition within `~/.ssh/config`.

The localhost ssh port for the container is also visible from Windows.
Consequently, you can also connect VSCode for Windows to this environment via
ssh using the `Remote SSH` and the `Remote SSH: Editing Configuration Files`
extensions. See the following tutorial:

https://code.visualstudio.com/docs/remote/ssh-tutorial

---

### Additional things to try

---

#### Task 1. Drive WSL from VSCode for Windows

The `WSL` extension for VSCode for Windows allows you to drive a WSL environment.
After installing that extension, run the following command from within the WSL
environment:

```zsh
# WSL Ubuntu-20.04

cd ~/Jugglebot && code .
```

That will open a VSCode window that's attached to the WSL environment. You can
save that VSCode workspace locally in Windows to facilitate opening it later.

---

#### Task 2. Run SavvyCAN in WSL

You'll find the `install-savvycan` utility in `~/bin`. That script demonstrates
how to use a dedicated Conda environment to build and to run an app that has
different dependencies from your primary Jugglebot project. Running it will
produce `~/bin/SavvyCAN`, which will launch the app.

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
> midway. The `IFS` initialization avoids the issue where the script behavior
> could change based on a previously exported `IFS` value.

---

#### Task 3. Expose a USB device to WSL

To use your USB ports in WSL, you need to expose them using the `usbipd` tool as
described here:

https://github.com/dorssel/usbipd-win/blob/v4.3.0/README.md

The process on **Windows 11** goes like this:

1. Within PowerShell, use `winget` to install the `usbipd` tool.

2. Attach the physical device that you want to use.

3. Within an Administrator PowerShell, use the `usbipd` tool to identify and to
   bind the device by specifying its busid. This is a one-time operation.

4. Within PowerShell during each Windows session prior to using the device in
   WSL, use the `usbipd` tool to attach the device to WSL. This will make the
   device available to all of the WSL distributions that have a compatible
   kernel.

5. Within the WSL Ubuntu-20.04 environment, use the `lsusb` tool to verify that
   you can see the device.

6. [Optional] Install the `USBIP Connect` extension in VSCode. This will add an
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

#### Task 4. Determine whether WSLg can use accelerated rendering

WSL ships with a component called WSLg that acts as a display server for X11 and
Wayland graphical applications. WSLg supports accelerated rendering only if your
display driver supports WDDM 2.9 or greater.

Windows ships with a tool called DirectX Diagnostic Tool that will display the
WDDM version that your display driver supports. Run it using the following
command:

```
# PowerShell

dxdiag
```

Within the DirectX Diagnostic Tool, navigate to the following field:

> `Display` tab > `Drivers` section > `Driver Model` field

If that field indicates, WDDM 2.9 or greater, you have the option to run
graphical apps (such as VSCode for Linux, the Chromium web browser or the
Arduino IDE) within WSL. If your display driver doesn't indicate WDDM 2.9 or
higher, those graphical applications will still run, but they may exhibit poor
rendering performance and high cpu utilization.

Additionally, we have found that applications that are built using the QT SDK
(such as SavvyCAN or the Falkon web browser) exhibit good rendering performance
regardless whether WSLg is providing accelerated rendering.

---

#### Task 5. Try the arm64-based Docker container environment

The arm64-based Docker container environment is not currently intended to be
used for development. It's primarily a testbed for the development environment
provisioning. However, you can build it if you'd like to take a peek. On machine with
an Intel i7-8550U and 16GB, this takes approximately two hours.

```zsh
# WSL Ubuntu-20.04

denv build --ssh-keypair-name id_ed25519 --arch arm64

denv exec --arch arm64

ssh docker-arm64-env
```

> Note:
>
> We have experienced problems when building the arm64 image that we haven't
> experienced when building the native image.
>
> Issue 1. Occasionally, the ubuntu-ports apt repository times out. This seems
> to occur more often if the internet connection is slow.
>
> Issue 2. We've encountered a 'nosuid' error upon executing the first task that
> requires sudo in `ubuntu-docker/main_playbook.yml`. This error remains
> mysterious. It disappeared upon rebooting Windows 11.

---

#### Task 7. Refresh project dependencies or upgrade the environment

The Python dependencies for the ROS workspace are configured using the jugglebot
Conda environment specification in the following file:

https://github.com/joewalp/Jugglebot/blob/dev-env-provisioning/ros_ws/conda_env.yml.j2

We use that Conda environment specification instead of the pip
`requirements.txt` files because Conda handles dependencies for us. As of this
writing, the `conda_env.yml.j2` doesn't yet constrain the version of every
package. In the near future, we will constrain at least the major version number
of each package that our code calls directly.

Suppose that you want to constrain a package version number or add a dependency.
The prototypical process goes like this:

1. Edit `conda_env.yml.j2`
2. Run `refresh-dependencies`
3. Verify that the new dependencies work
4. Commit the changed `conda_env.yml.j2` to the repo

A lengthy comment at the top of `conda_env.yml.j2`, describes all of the work
that the `refresh-dependencies` utility performs.

The WSL environment setup script that we ran in Step 7 of the Instructions
behaves similarly to the `refresh-dependencies` script in the sense that you can
safely re-run the setup script to automatically upgrade the provisioned
resources to their latest versions that are checked-in to the `environments`
subtree of the repo. Most of these files are in `environments/ubuntu-common`.

A collaborator can keep their WSL environment in sync merely by running either
the `refresh-dependencies` script or the `ubuntu-wsl/setup.sh` script.

If you manually make changes to a provisioned script such as the `~/.zshrc`, the
setup script won't clobber those changes. Instead, it will produce a diff in
`~/.jugglebot/host_setup/diffs`.

---

## Notes

Each of these environments uses Z Shell (zsh) with Oh My Zsh and the `clean`
built-in theme. The Python environment is managed by Conda and pip rather than
virtualenv and pip because the conda-forge dependency management makes life
easier.

The Jugglebot repo is checked out separately in each environment. If anyone ends
up using a Docker container environment in tandem with the WSL2 environment
for interactive coding and testing, we may end up mounting the WSL2 Jugglebot
repo into the container. However, I currently consider the Docker native
platform container environment to be a stepping stone toward building the Ubuntu
for arm64 Docker container. The native platform container environment is
considerably faster than the arm64 platform container environment, so I want to
use it for iterating on features before confirming that the same provisioning
and features work within an arm64 platform environment.

## Noteworthy future milestones

- Build a minimal ROS app that uses the Jugglebot fork of Yasmin to provide a
  testbed for example code that doesn't have robot hardware dependencies.
- Demonstrate how to use VSCode for Windows to connect to a Linux environment
  over ssh and to run a unit test in that remote environment.
- On a Windows 11 machine with an Nvidia GPU, demonstrate passthrough of Cuda
  tasks from a guest Linux development environment host where those tasks are
  driven by a Jetson SDK.
