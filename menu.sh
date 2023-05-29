#!/bin/bash
clear

# Variabel global:
# TARGET : value (root/home)
# TARGET_PATH : value (/dev/sdxY)

target_path(){
	if [ "$TARGET" == 'root' ]; then
		TARGET_PATH=$(lsblk -o path,mountpoint | awk '$2=="/" {print $1}')
		MOUNTPOINT='/'
	elif [ "$TARGET" == 'home' ]; then
		TARGET_PATH=$(lsblk -o path,mountpoint | awk '$2=="/home" {print $1}')
		MOUNTPOINT='/home'
	fi	
}

umount_target_path() {
	local MNT=$(lsblk -o path,mountpoint | awk '$2=="/mnt" {print $1}')
	[ -n "$MNT" ] && sudo umount /mnt && echo "umount $MNT from /mnt sukses"
}

mount_target_path(){
	target_path	
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
		mkdir $NAMESNAPSHOT
		[ "$?" -eq 0 ] && msg="Snapshot berhasil dibuat.\nNama: $NAMESNAPSHOT\nPath: $TARGET"
	elif [ "$TARGET" == 'home' ]; then
		# [ -n "$NAMESNAPSHOT" ] && btrfs subvolume snapshot $NAMESNAPSHOT
		mkdir $NAMESNAPSHOT
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
			rmdir $selected_file
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

configure_snapshot(){
	local DEFAULT_NAME UUID_TARGET_PATH ACTIVE_SNAPSHOT GEN_MAX PATH_FSTAB
	DEFAULT_NAME=@active_home
	PATH_FSTAB=$(dirname $(realpath $0))/tes.txt
	
	target_path
	
	# Mendapatkan nilai gen tertinggi pada daftar snapshot yg ada
	GEN_MAX=$(sudo btrfs subvolume list $MOUNTPOINT | awk '/gen/ { if ($4 > max) max = $4 } END { print max }')
	
	if [ -n "GEN_MAX" ]; then
		
		# mendapatkan nama snapshot yg sedang aktif berdasarkan nilai gen tertinggi
		ACTIVE_SNAPSHOT=$(sudo btrfs subvolume list $MOUNTPOINT | grep "$GEN_MAX" | awk '{print $9}')
		
		# Setup default snapshot
		if [ -n "$ACTIVE_SNAPSHOT" ]; then
		
			#~ mv /mnt/$ACTIVE_SNAPSHOT /mnt/$DEFAULT_NAME
			if [ -d "$(dirname $(realpath $0))/$ACTIVE_SNAPSHOT" ]; then
				mv $ACTIVE_SNAPSHOT $DEFAULT_NAME
			else
		
				if [ "$TARGET" == 'root' ]; then
					#~ [ -n "$NAMESNAPSHOT" ] && sudo btrfs subvolume creat $DEFAULT_NAME
					#~ sudo btrfs subvolume snapshot $MOUNTPOINT $DEFAULT_NAME
					mkdir $(dirname $(realpath $0))/$DEFAULT_NAME
					[ "$?" -eq 0 ] && msg="Membuat default subvolume."
				elif [ "$TARGET" == 'home' ]; then
					#~ [ -n "$NAMESNAPSHOT" ] && btrfs subvolume creat $DEFAULT_NAME
					#~ btrfs subvolume snapshot $MOUNTPOINT $DEFAULT_NAME
					mkdir $(dirname $(realpath $0))/$DEFAULT_NAME
					[ "$?" -eq 0 ] && msg="Membuat default subvolume."
				fi
			
			fi
			
		fi
		
		# Setup /etc/fstab
		if [[ $(sed -n '/\/home/p' $PATH_FSTAB) ]]; then
		
			# Menambahkan komentar pada baris dengan kata kunci "/home" jika belum ada komentar
			sed -i '/^\/home/ { /^[^#]/ s/^/#/ }' $PATH_FSTAB
			[ "$?" -ne 0 ] && echo 'sed -i '/^\/home/ { /^[^#]/ s/^/#/ }' error'
			
			# Mendapatkan uuid $TARGET_PATH
			UUID_TARGET_PATH=$(sudo blkid -s UUID -o value $TARGET_PATH)

			# Menentukan variabel dynamic_content
			ADD_FSTAB="UUID=$UUID_TARGET_PATH /home btrfs defaults,subvol=$DEFAULT_NAME 0 2"

			# Menambahkan baris dengan konten dinamis pada file "fstab"
			if [[ -z $(sed -n "/$DEFAULT_NAME/p" $PATH_FSTAB) ]]; then
				sed -i "\$a$ADD_FSTAB" $PATH_FSTAB
				[ "$?" -ne 0 ] && echo 'sed -i "\$a$ADD_FSTAB" error'
			fi
			# Mengganti nama snapshot pada fstab
			sed -i "s/$ACTIVE_SNAPSHOT/$DEFAULT_NAME/g" $PATH_FSTAB
			[ "$?" -ne 0 ] && echo 'sed -i "s/$ACTIVE_SNAPSHOT/$DEFAULT_NAME/g" error'
		fi
		
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
			'active_snapshot' 'cek active snapshot'
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
			'active_snapshot' )
				configure_snapshot
			;;
		esac
		ls /mnt
	done
	#umount_target_path
}

target_snapshot
