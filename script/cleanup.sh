#!/bin/bash -eu

SSH_USER=${SSH_USERNAME:-vagrant}

echo "==> Remove linux-headers"
dpkg --list \
  | awk '{ print $2 }' \
  | grep 'linux-headers' \
  | xargs apt-get -y purge;

echo "==> Remove specific Linux kernels, such as linux-image-3.11.0-15-generic but keeps the current kernel and does not touch the virtual packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep 'linux-image-.*-generic' \
    | grep -v `uname -r` \
    | xargs apt-get -y purge;

echo "==> Remove old kernel modules packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep 'linux-modules-.*-generic' \
    | grep -v `uname -r` \
    | xargs apt-get -y purge;

echo "==> Remove linux-source package"
dpkg --list \
    | awk '{ print $2 }' \
    | grep linux-source \
    | xargs apt-get -y purge;

echo "==> Remove all development packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep -- '-dev\(:[a-z0-9]\+\)\?$' \
    | xargs apt-get -y purge;

echo "==> Remove docs packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep -- '-doc$' \
    | xargs apt-get -y purge;

echo "==> Removing X11 libraries"
apt-get -y purge libx11-data xauth libxmuu1 libxcb1 libx11-6 libxext6 libxau6 libxdmcp6


echo "==> Remove obsolete networking packages"
apt-get -y purge ppp pppconfig pppoeconf;

echo "==> Removing other oddities"
apt-get -y purge accountsservice bind9-host busybox-static command-not-found command-not-found-data \
    dmidecode dosfstools friendly-recovery geoip-database hdparm info install-info installation-report \
    iso-codes krb5-locales language-selector-common laptop-detect lshw mlocate mtr-tiny nano \
    ncurses-term nplan ntfs-3g os-prober parted pciutils plymouth popularity-contest powermgmt-base \
    publicsuffix python-apt-common shared-mime-info ssh-import-id \
    tasksel tcpdump ufw ureadahead usbutils uuid-runtime xdg-user-dirs \
    fonts-ubuntu-font-family-console grub-legacy-ec2
apt-get -y autoremove --purge

echo "==> Remove the console font"
apt-get -y purge fonts-ubuntu-console || true;

# Exclude the files we don't need w/o uninstalling linux-firmware
echo "==> Setup dpkg excludes for linux-firmware"
cat <<_EOF_ | cat >> /etc/dpkg/dpkg.cfg.d/excludes
#BENTO-BEGIN
path-exclude=/lib/firmware/*
path-exclude=/usr/share/doc/linux-firmware/*
#BENTO-END
_EOF_

echo "==> Delete the massive firmware files"
rm -rf /lib/firmware/*
rm -rf /usr/share/doc/linux-firmware/*

# Cleanup apt cache
apt-get -y autoremove --purge
apt-get -y clean

# Clean up orphaned packages with deborphan
apt-get -y install --no-install-recommends deborphan
deborphan --find-config | xargs apt-get -y purge
while [ -n "$(deborphan --guess-all)" ]; do
    deborphan --guess-all | xargs apt-get -y purge
done
apt-get -y purge deborphan

echo "==> Installed packages"
dpkg --get-selections | grep -v deinstall

# Remove Bash history
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/${SSH_USER}/.bash_history

echo '==> Clear out swap and disable until reboot'
set +e
swapuuid=$(/sbin/blkid -o value -l -s UUID -t TYPE=swap)
case "$?" in
    2|0) ;;
    *) exit 1 ;;
esac
set -e
if [ "x${swapuuid}" != "x" ]; then
    # Whiteout the swap partition to reduce box size
    # Swap is disabled till reboot
    swappart=$(readlink -f /dev/disk/by-uuid/$swapuuid)
    /sbin/swapoff "${swappart}"
    dd if=/dev/zero of="${swappart}" bs=1M || echo "dd exit code $? is suppressed"
    /sbin/mkswap -U "${swapuuid}" "${swappart}"
fi

# Zero out the free space to save space in the final image
if [ -d /boot/efi ]; then
    dd if=/dev/zero of=/boot/efi/EMPTY bs=1M || echo "dd exit code $? is suppressed"
    rm -f /boot/efi/EMPTY
fi
dd if=/dev/zero of=/EMPTY bs=1M || echo "dd exit code $? is suppressed"
rm -f /EMPTY
sync

echo "==> Removing the release upgrader"
apt-get -y purge ubuntu-release-upgrader-core
rm -rf /var/lib/ubuntu-release-upgrader
rm -rf /var/lib/update-manager

echo "==> Remove the unattended-upgrades"
apt-get -y purge unattended-upgrades;
rm -rf /var/log/unattended-upgrades;

echo "==> Removing APT files"
find /var/lib/apt -type f -exec rm -rf {} \;

echo "==> Removing caches"
find /var/cache -type f -exec rm -rf {} \;

echo "==> Removing docs"
rm -rf /usr/share/doc/*

echo "==> Clearing machine-id"
truncate --size=0 /etc/machine-id

echo "==> Clearing log files"
find /var/log -type f -exec truncate --size=0 {} \;

echo "==> Cleaning up tmp"
rm -rf /tmp/*

echo "force a new random seed to be generated"
rm -f /var/lib/systemd/random-seed

echo "==> Disk usage after cleanup"
df -h

echo "clear the history so our install isn't there"
rm -f /root/.wget-hsts
export HISTSIZE=0
