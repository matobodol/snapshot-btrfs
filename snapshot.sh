#!/bin/bash
# Membuat snapshot
clear

home_snapshot(){
	local target=$1
	
	# menampilkan daftar snapshot
	run_list(){
		echo -e "\nDaftar snapshot pada /home:"
		sudo btrfs subvolume list -a /home
	}
	
	# membuat snapshot baru
	run_snapshot(){
		local MNT PATHHOME YN SRC NEW OLD TMP
		
		# umount /mnt jika ada disk yg terpasang pada /mnt
		MNT=$(lsblk -o path,mountpoint | awk '$2=="/mnt" {print $2}')
		[ -n "$MNT" ] && sudo umount /mnt && echo "Umount /mnt..."
		# mount partisi /home ke /mnt
		PATHHOME=$(lsblk -o path,mountpoint | awk '$2=="/home" {print $1}')
		[ -n "$PATHHOME" ] && sudo mount -t btrfs -o subvolid=5 $PATHHOME /mnt && echo "[Mount $PATHHOME to /mnt]"
		echo ''
		
		SRC=/mnt/@home
		NEW=/mnt/@home_new
		OLD=/mnt/@home_old
		TMP=/mnt/@tmp
		
		if [ -d "$NEW" ]; then
			[ -d "$TMP" ] && sudo btrfs subvolume delete $TMP
			! [ -d "$TMP" ] && [ -d "$OLD" ] && mv $OLD $TMP && echo -e "$OLD\t  rename to\t$TMP"
			! [ -d "$OLD" ] && [ -d "$NEW" ] && mv $NEW $OLD && echo -e "$NEW\t  rename to\t$OLD"
			
			if ! [ -d "$NEW" ] && [ -d "$SRC" ]; then
				echo -e "$SRC\t  snapshot to\t$NEW\n"
				btrfs subvolume snapshot $SRC $NEW 
				[ "$?" -eq 0 ] && YN=$?
			fi
			
			[ -d "$TMP" ] && sudo btrfs subvolume delete $TMP
		else
			[ -d "$TMP" ] && sudo btrfs subvolume delete $TMP
			if [ -d "$SRC" ]; then
				echo -e "$SRC    snapshot to    $NEW\n"
				btrfs subvolume snapshot $SRC $NEW
				[ "$?" -eq 0 ] && YN=$?
			fi
			
			[ -d "$TMP" ] && sudo btrfs subvolume delete $TMP
		fi
		
		[ "$YN" -eq 0 ] && echo -e "\n\tSnapshot berhasil dibuat."
		
		run_list
		
		MNT=$(lsblk -o path,mountpoint | awk '$2=="/mnt" {print $2}')
		[ -n "$MNT" ] && sudo umount /mnt && echo -e "\n[Umount $PATHHOME from /mnt]"		
	}
	
	
	
	$target
}

case $1 in
	--home-c )
		home_snapshot run_snapshot
	;;
	--home-r )
		home_snapshot run_restore
	;;
	--home-l )
		home_snapshot run_list
	;;
	--home-del )
		home_snapshot run_delete
	;;

esac
