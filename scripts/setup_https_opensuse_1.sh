#!/bin/bash -e

# Add repo for snapd package
sudo zypper addrepo --refresh https://download.opensuse.org/repositories/system:/snappy/openSUSE_Leap_15.3 snappy
sudo zypper --gpg-auto-import-keys refresh
sudo zypper dup --from snappy

# Install and enable snapd
sudo zypper install snapd
source /etc/profile
sudo systemctl enable --now snapd
sudo systemctl enable --now snapd.apparmor