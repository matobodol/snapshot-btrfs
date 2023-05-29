#!/bin/bash
clear

# Variabel global:
# TARGET : value (root/home)
# TARGET_PATH : value (/dev/sdxY)

umount_target_path() {
	local MNT=$(lsblk -o path,mountpoint | awk '$2=="/mnt" {print $1}')
	[ -n "$MNT" ] && sudo umount /mnt && echo "umount $MNT from /mnt sukses"
}

mount_target_path(){
	if [ "$TARGET" == 'root' ]; then
		TARGET_PATH=$(lsblk -o path,mountpoint | awk '$2=="/" {print $1}')
	elif [ "$TARGET" == 'home' ]; then
		TARGET_PATH=$(lsblk -o path,mountpoint | awk '$2=="/home" {print $1}')
	fi
	
	[ -n "$TARGET_PATH" ] && sudo mount -t btrfs -o subvolid=5 $TARGET_PATH /mnt && echo "mount $TARGET_PATH to /mnt sukses"
}

input_box(){
	local msg=$1
	local name=$2
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
		'root' ' : Atur snapshot system / (root)'
		'home' ' : Atur snapshot /home'
	)
	
	TARGET=$(menu_box 'Pilih target:' 'SNAPSHOT' 'Exit' "${options[@]}")
	exit_code
	main_menu
	done
}

# Membuat snapshot
creat_snapshot(){
	msg="Nama snapshot:\nNOTE: jangan hapus symbol '@' pada nama."
	NAMESNAPSHOT=$(input_box "$msg" "@${TARGET}_$(date +"Date_%Y-%m-%d_Time_%H-%M-%S")")
	
	if [ "$TARGET" == 'root' ]; then
		# [ -n "$NAMESNAPSHOT" ] && sudo btrfs subvolume snapshot $NAMESNAPSHOT
		touch $NAMESNAPSHOT
		[ "$?" -eq 0 ] && msg="Snapshot berhasil dibuat.\nNama: $NAMESNAPSHOT\nPath: $TARGET"
	elif [ "$TARGET" == 'home' ]; then
		# [ -n "$NAMESNAPSHOT" ] && btrfs subvolume snapshot $NAMESNAPSHOT
		touch $NAMESNAPSHOT
		[ "$?" -eq 0 ] && msg="Snapshot berhasil dibuat.\nNama: $NAMESNAPSHOT\nPath: $TARGET"
	fi
}

# Restore/hapus snapshot
restore_delete(){
	selected=$1
	
	# Restore snapshot
	restore_snapshot(){
		if [ "$?" -eq 0 ] && [ "$selected_file" ]; then
			msg="Selected: '$selected_file'\nRestore snapshot berhasil."
			# mv @active_$TARGET @tmp
			# mv $selected_file @active_$TARGET
			# mv @tmp $selected_file
		
			# systemctl reboot
		else
			msg='Pilih menu: '
		fi
	}
	
	# Hapus snapshot
	delete_snapshot(){
		if [ "$?" -eq 0 ] && [ "$selected_file" ]; then
			sudo rm $selected_file
			msg="Selected: '$selected_file'\nSnapshot berhasil dihapus."
		else
			msg='Pilih menu: '
		fi
	}
	
	# Menyimpan daftar file dalam variabel array
	file_list=($(ls -1t $(dirname `realpath $0`) | grep "@$TARGET"))
	if [ -z "$file_list" ]; then
		msg="tidak ada snapshot."
		whiptail --title "SNAPSHOT" --msgbox "$msg" 0 0
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
		selected_file=$(menu_box 'Pilih File:' 'DELETE SNAPSHOT' 'Back' "${options[@]}")
	
		$selected
	fi
}	


main_menu(){
	local options MENU msg
	msg='Pilih menu: '
	#umount_target_path
	#mount_target_path
	
	while true; do
		options=(
			'create' ' : buat snapshot baru' 
			'restore' ' : Pilih snapshot dari daftar lalu restore'
			'delete' ' : Pilih snapshot dari daftar lalu hapus'
		)
		MENU=$(menu_box "$msg" 'MAIN MENU' 'Back' "${options[@]}")
		[ "$?" -ne 0 ] && break
	
		case $MENU in
			'create' )
				creat_snapshot
			;;
			'restore' )
				restore_delete 'restore_snapshot'
			;;
			'delete' )
				restore_delete 'delete_snapshot'
			;;
		esac
		ls /mnt
	done
	#umount_target_path
}

target_snapshot
