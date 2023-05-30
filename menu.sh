#!/bin/bash
clear

# Variabel global:
# TARGET_SNAPSHOT : value (root/home)
# TARGET_PATH : value (/dev/sdxY)


switch_path(){
	if [ "$TARGET_SNAPSHOT" == 'root' ]; then
		TARGET_PATH=$(lsblk -o path,mountpoint | awk '$2=="/" {print $1}')
		MOUNTPOINT='/'
		DEFAULT_ACTIVE_NAME='@active_root'
	elif [ "$TARGET_SNAPSHOT" == 'home' ]; then
		TARGET_PATH=$(lsblk -o path,mountpoint | awk '$2=="/home" {print $1}')
		MOUNTPOINT='/home'
		DEFAULT_ACTIVE_NAME='@active_home'
	fi
	
	MNT=$(lsblk -o path,mountpoint | awk '$2=="/mnt" {print $1}')
	PATH_FSTAB='/etc/fstab'
}

umount_disk() {
	
	switch_path
	[ -n "$MNT" ] && sudo umount /mnt && echo "Umount $MNT from /mnt sukses"
}

mount_disk(){
	
	switch_path	
	[ -n "$TARGET_PATH" ] && sudo mount -t btrfs -o subvolid=5 $TARGET_PATH /mnt && echo "Mount $TARGET_PATH to /mnt sukses"
}

input_box(){
	
	local msg=$1 name=$2
	echo $(whiptail --title "BUAT SNAPSHOT" --inputbox "$msg" 8 50 $name 2>&1 >/dev/tty)
}

exit_code(){
	
	local EXITCODE=$?
	[[ $EXITCODE -eq 1 ]] && exit $EXITCODE 
}

menu_box(){
	
	local msg=$1 title=$2 button=$3
	shift 3
	local options=("$@")
	
	menu=$(whiptail --menu "$msg" --title "$title" --cancel-button "$button" 0 50 0 "${options[@]}" 3>&1 1>&2 2>&3)
	exit_code
	
	printf "%s" "$menu"
}

#########################################################
#########################################################


# Memilih target untuk mengatur snapshot root/home
target_snapshot(){
	
	while true; do
	local options=(
		'home' ' : Atur snapshot home direktory'
		'root' ' : Atur snapshot system root)'
	)
	
	TARGET_SNAPSHOT=$(menu_box 'Pilih target:' 'SNAPSHOT' 'Exit' "${options[@]}")
	exit_code
	main_menu
	done
}

# Membuat snapshot
creat_snapshot(){
	
	configure_snapshot
	
	msg="Nama snapshot:\nNOTE: jangan hapus symbol '@' pada nama."
	SNAPSHOT_NAME=$(input_box "$msg" "@${TARGET_SNAPSHOT}_$(date +"Date_%Y-%m-%d_Time_%H-%M-%S")")
	
	if [ "$TARGET_SNAPSHOT" == 'root' ]; then
		[ -n "$SNAPSHOT_NAME" ] && sudo btrfs subvolume snapshot /mnt/$DEFAULT_ACTIVE_NAME /mnt/$SNAPSHOT_NAME
		[ "$?" -eq 0 ] && msg="Snapshot berhasil dibuat.\nNama: $SNAPSHOT_NAME\nPath: $TARGET_SNAPSHOT"
	elif [ "$TARGET_SNAPSHOT" == 'home' ]; then
		sudo chmod 777 /mnt
		[ -n "$SNAPSHOT_NAME" ] && btrfs subvolume snapshot /mnt/$DEFAULT_ACTIVE_NAME /mnt/$SNAPSHOT_NAME
		[ "$?" -eq 0 ] && msg="Snapshot berhasil dibuat.\nNama: $SNAPSHOT_NAME\nPath: $TARGET_SNAPSHOT"
	fi
	
	[ "$configured" -eq 0 ] && msg="berhasil mengkonfigurasi.\nSystem akan restart dalam 10 detik..."
}

# Restore/hapus snapshot
restore_delete(){
	local selected SELECTED_FILE file_list options title
	selected=$1
	title=$2
	
	# Restore snapshot
	restore_snapshot(){
		
		if [ "$?" -eq 0 ] && [ "$SELECTED_FILE" ]; then
			msg="Selected: '${SELECTED_FILE}'\nRestore snapshot berhasil."
			# mv @active_$TARGET_SNAPSHOT @tmp
			# mv $SELECTED_FILE @active_$TARGET_SNAPSHOT
			# mv @tmp $SELECTED_FILE
		
			# systemctl reboot
		else
			msg='Pilih menu :'
		fi
	}
	
	# Hapus snapshot
	delete_snapshot(){
		
		if [ "$?" -eq 0 ] && [ "$SELECTED_FILE" ]; then
			rmdir $SELECTED_FILE
			msg="Selected: '${SELECTED_FILE}'\nSnapshot berhasil dihapus."
		else
			msg='Pilih menu :'
		fi
	}
	
	
	# Menyimpan daftar file dalam variabel array
	file_list=($(ls -1t $(dirname `realpath $0`) | grep "@" | grep -v "@active"))
	
	if [ -z "$file_list" ]; then
		
		whiptail --title "SNAPSHOT" --msgbox "Tidak ada snapshot." 0 0
		return
	else
		# Looping untuk membuat opsi menu
		options=()
		for file in "${file_list[@]}"; do
			# Mengambil nama file tanpa awalan
			file_name="${file}"
			options+=("$file_name" "")
		done

		# Menampilkan menu menggunakan Whiptail
		SELECTED_FILE=$(menu_box 'Pilih File:' "$title" 'Back' "${options[@]}")
	
		$selected
	fi
}	

configure_snapshot(){
	local UUID_TARGET_PATH CHECKED_ACTIVE_SNAPSHOT GEN_ACTIVE_SNAPSHOT
	
	switch_path
	
	# Mendapatkan nilai gen tertinggi pada daftar snapshot yg ada
	GEN_ACTIVE_SNAPSHOT=$(sudo btrfs subvolume list $MOUNTPOINT | awk '/gen/ { if ($4 > max) max = $4 } END { print max }')
	
	if [ -n "GEN_ACTIVE_SNAPSHOT" ]; then
		
		# mendapatkan nama snapshot yg sedang aktif berdasarkan nilai gen tertinggi
		CHECKED_ACTIVE_SNAPSHOT=$(sudo btrfs subvolume list $MOUNTPOINT | grep "$GEN_ACTIVE_SNAPSHOT" | awk '{print $9}')
	fi	
	
	# Setup default snapshot
	if [ -n "GEN_ACTIVE_SNAPSHOT" ] && [ -n "$CHECKED_ACTIVE_SNAPSHOT" ]; then
	
		#~ mv /mnt/$CHECKED_ACTIVE_SNAPSHOT /mnt/$DEFAULT_ACTIVE_NAME
		if [ -d "$/mnt/$CHECKED_ACTIVE_SNAPSHOT" ]; then
			if [ "$TARGET_SNAPSHOT" == 'root' ]; then
				sudo mv /mnt/$CHECKED_ACTIVE_SNAPSHOT /mnt/$DEFAULT_ACTIVE_NAME
			elif [ "$TARGET_SNAPSHOT" == 'home' ]; then
				mv /mnt/$CHECKED_ACTIVE_SNAPSHOT /mnt/$DEFAULT_ACTIVE_NAME
			fi
			configured=$?
			
		elif ! [[ -d "/mnt/$DEFAULT_ACTIVE_NAME" ]]; then
			
			if [ "$TARGET_SNAPSHOT" == 'root' ]; then
				#[ -n "$SNAPSHOT_NAME" ] && sudo btrfs subvolume creat $DEFAULT_ACTIVE_NAME
				sudo btrfs subvolume snapshot $MOUNTPOINT /mnt/$DEFAULT_ACTIVE_NAME
				configured=$?
				[ "$configured" -eq 0 ] && msg="Membuat default subvolume."
			elif [ "$TARGET_SNAPSHOT" == 'home' ]; then
				#~ [ -n "$SNAPSHOT_NAME" ] && btrfs subvolume creat $DEFAULT_ACTIVE_NAME
				sudo chmod 777 /mnt
				btrfs subvolume snapshot $MOUNTPOINT /mnt/$DEFAULT_ACTIVE_NAME
				configured=$?
				[ "$configured" -eq 0 ] && msg="Membuat default subvolume."
			fi
			
		fi
	fi
	
	# Setup /etc/fstab
	if [[ -n "GEN_ACTIVE_SNAPSHOT" ]] && [[ -n $(sed -n "/$CHECKED_ACTIVE_SNAPSHOT/p" $PATH_FSTAB) ]]; then
	
		# Mengganti nama snapshot pada fstab
		sudo sed -i "s/$CHECKED_ACTIVE_SNAPSHOT/$DEFAULT_ACTIVE_NAME/g" $PATH_FSTAB
		[ "$?" -ne 0 ] && echo 'sed -i "s/$CHECKED_ACTIVE_SNAPSHOT/$DEFAULT_ACTIVE_NAME/g" error'
		
	else
		
		# Menambahkan komentar pada baris dengan kata kunci "/home" jika belum ada komentar
		sudo sed -i '/\/home/ { /^[^#]/ s/^/#/ }' $PATH_FSTAB
		[ "$?" -ne 0 ] && echo 'sed -i '/\/home/ { /^[^#]/ s/^/#/ }' error'
		
		# Mendapatkan uuid $TARGET_PATH
		UUID_TARGET_PATH=$(sudo blkid -s UUID -o value $TARGET_PATH)

		# Menentukan variabel dynamic_content
		ADD_FSTAB="UUID=$UUID_TARGET_PATH /home btrfs defaults,subvol=$DEFAULT_ACTIVE_NAME 0 2"

		# Menambahkan baris dengan konten dinamis pada file "/etc/fstab"
		if [[ -z $(sed -n "/$DEFAULT_ACTIVE_NAME/p" $PATH_FSTAB) ]]; then
			sudo sed -i '$ a\'"$ADD_FSTAB" /etc/fstab

			[ "$?" -ne 0 ] && echo 'sed -i "\$a$ADD_FSTAB" error'
		fi
	fi
}

main_menu(){
	local options MENU msg
	msg='Pilih menu: '
	configured=1
	umount_disk
	mount_disk
	
	while true; do
		options=(
			'Create' ' : Buat snapshot baru' 
			'Restore' ' : Pilih snapshot dari daftar lalu restore'
			'Delete' ' : Pilih snapshot dari daftar lalu hapus'
		)
		MENU=$(menu_box "$msg" 'MAIN MENU' 'Back' "${options[@]}")
		local exit_code=$?
		[ "$exit_code" -ne 0 ] && return
	
		case $MENU in
			'Create' )
				creat_snapshot
				
				whiptail --title 'CONFIGURING SNAPSHOT' --yesno \
				"sebelum melanjutkan, mohon simpan semua pekerjaan anda,\
				\nkarena setelah proses ini selesai system akan otomatis restart." 0 0

				if [ "$?" -eq 0 ]; then
					if [ -n "$configured" ] && [ "$configured" -eq 0 ]; then
						nohup bash -c "sleep 30 && kill $PPID" >/dev/null 2>&1 &
						nohup bash -c "sleep 33 && systemctl reboot" >/dev/null 2>&1 &
					fi
				fi
			;;
			'Restore' )
				restore_delete 'restore_snapshot' 'RESTORE'
			;;
			'Delete' )
				restore_delete 'delete_snapshot' 'DELETE'
			;;
		esac
		
	done
	umount_disk
}

if [ "$(whoami)" != 'root' ]; then
	target_snapshot
else
	echo -e "jangan jalankan skrip ini menggunakan sudo atau akun root\n"
fi
