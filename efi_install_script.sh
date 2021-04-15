#!/usr/bin/bash 

echo this is $0

if [ "$1" == "" ] || [ $# -gt 1 ]; then echo "NO DRIVE! EXIT!"; exit 1

fi  


DISK=$1 

RELEASE="buster"
KERNEL="linux-image-amd64"

FS="ext4"


HOSTNAME="live.local"
ROOT_PASSWORD="live"


WORKING_DIR="/mnt/LIVE";



SERVER_ESSENTIALS="bash-completion,lsb-release,ntp,ipmitool,mdadm,openssh-server,hdparm,parted,gdisk,cryptsetup,vim,mdadm"

LIVE_ESSENTIALS="htop,bash-completion,lsb-release,ipmitool,mdadm,hdparm,parted,gdisk,openssh-server,cdebootstrap,cryptsetup,vim"


echo "Drive is: $DISK"
parted $DISK p 

read -p "Is it right? All the DATA ON THIS DRIVE WILL BE LOST [Yy/n]" -n 1 -r

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

umount $WORKING_DIR/root/boot
umount "$DISK"1
umount "$DISK"2

rm -r $WORKING_DIR

EFI_SIZE="512M"

parted $DISK mklabel gpt ; 
parted $DISK mkpart boot 0% $EFI_SIZE; 
parted $DISK mkpart root $EFI_SIZE 100% ; 

echo "Done!"
parted $DISK p


mkfs.fat -F32 "$DISK"1 
mkfs.$FS "$DISK"2

UUID=$(blkid -s UUID -o value "$DISK"2)
EFI_UUID=$(blkid -s UUID -o value "$DISK"1)

KERNEL_IMG='efi/debian/vmlinuz'
INITRD_IMG='efi/debian/initrd.img'


mkdir -p $WORKING_DIR/boot
mkdir -p $WORKING_DIR/root


mount "$DISK"1 $WORKING_DIR/boot
mount "$DISK"2 $WORKING_DIR/root

mkdir -p $WORKING_DIR/root/boot; mount -o bind $WORKING_DIR/boot $WORKING_DIR/root/boot

cdebootstrap --include=grub-efi-amd64,linux-image-amd64,$LIVE_ESSENTIALS $RELEASE $WORKING_DIR/root


mkdir -p $WORKING_DIR/root/boot/EFI/debian
mkdir -p $WORKING_DIR/root/boot/EFI/boot



cp $WORKING_DIR/root/vmlinuz $WORKING_DIR/root/boot/$KERNEL_IMG
cp $WORKING_DIR/root/initrd.img $WORKING_DIR/root/boot/$INITRD_IMG


#FSTAB FILESYSTEMS AND EFI PARTITION
echo "UUID=$UUID /		$FS    		errors=remount-ro 0 1" 											  > $WORKING_DIR/root/etc/fstab
echo "UUID=$EFI_UUID /efi	vfat   		rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 2" >> $WORKING_DIR/root/etc/fstab
echo "/efi			/boot/efi       none   defaults,bind 0 0"										  >> $WORKING_DIR/root/etc/fstab
echo "/efi/EFI/debian		/boot 	   	none   defaults,bind 0 0"										  >> $WORKING_DIR/root/etc/fstab



#INSTALL BOOTLOADER (yes, it's a shame, yet still EFI STUB is not working everywhere)
GRUB_CONF=$WORKING_DIR/boot/grub/grub.cfg

grub-install --boot-directory=$WORKING_DIR/boot --efi-directory=$WORKING_DIR/boot --target=x86_64-efi --removable $DISK


#the minimal grub config
echo "set timeout=5" > $GRUB_CONF
echo "menuentry \"Debian Live $RELEASE\" {" >> $GRUB_CONF
echo "search --no-floppy --set=prefix --fs-uuid --set $EFI_UUID" >> $GRUB_CONF
echo "search --no-floppy --set=root --fs-uuid --set $EFI_UUID" >> $GRUB_CONF
echo "insmod normal" >> $GRUB_CONF
echo "insmod efi_gop" >> $GRUB_CONF
echo "linux (\$root)/$KERNEL_IMG root=UUID=$UUID ro quiet" >> $GRUB_CONF
echo "initrd (\$root)/$INITRD_IMG" >> $GRUB_CONF
echo "}" >> $GRUB_CONF

cat $GRUB_CONF


#NETWORK
echo $HOSTNAME > $WORKING_DIR/root/etc/hostname
echo "127.0.1.1 $HOSTNAME" >> $WORKING_DIR/root/etc/hosts
chroot $WORKING_DIR/root/ /bin/bash -c "echo "root:$ROOT_PASSWORD" | chpasswd"


#SSH TWEAKS
#sed -i 's/without-password/yes/g' $WORKING_DIR/etc/ssh/sshd_config
#mkdir $WORKING_DIR/root/.ssh
#touch $WORKING_DIR/root/.ssh/authorized_keys


#MAKING THE COPY OF THIS SCRIPT TO THE ROOT
cp $0 $WORKING_DIR/root/root/$0


#GOODBYE

umount $WORKING_DIR/root/boot
umount "$DISK"1 $WORKING_DIR/boot
umount "$DISK"2 $WORKING_DIR/root

sync
echo "DONE! Drive is ready!"
