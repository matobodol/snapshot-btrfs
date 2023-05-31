#!/bin/bash
clear

# Variabel global
global_variabel(){

	if [ "$TARGET_SNAPSHOT" == 'root' ]; then
		MOUNTPOINT='/'
		DEFAULT_ACTIVE_NAME='@active_root'
	
	elif [ "$TARGET_SNAPSHOT" == 'home' ]; then
		MOUNTPOINT='/home'
		DEFAULT_ACTIVE_NAME='@active_home'
	fi
	
}

umount_disk() {
	
	global_variabel
	
	# mendapatkan path drive yg terpasang pada /mnt
	MNT=$(
		lsblk -o path,mountpoint | awk '$2=="/mnt" {print $1}'
	)
		
	[ -n "$MNT" ] && sudo umount /mnt && echo "Umount $PATH_TARGET_SNAPSHOT from /mnt"

}

mount_disk(){
	
	global_variabel
	
	# mendapatkan path drive TARGET_SNAPSHOT
	PATH_TARGET_SNAPSHOT=$(
		lsblk -o path,mountpoint | grep -w "$MOUNTPOINT" | awk '{print $1}'
	)
	
	if [ -n "$PATH_TARGET_SNAPSHOT" ]; then
		echo "Mount $PATH_TARGET_SNAPSHOT into /mnt"
		sudo mount -t btrfs -o subvolid=5 $PATH_TARGET_SNAPSHOT /mnt
		exit_code
	else
		echo "Tidak ada Partisi $MOUNTPOINT"
		exit
	fi
}

input_box(){
	
	local menu msg=$1 name=$2
	menu=$(
		whiptail --title "BUAT SNAPSHOT" --inputbox "$msg" 8 50 $name 2>&1 >/dev/tty
	)
	
	printf "%s" "$menu"
}

exit_code(){
	
	local EXITCODE=$?
	[[ $EXITCODE -ne 0 ]] && exit $EXITCODE 
}

menu_box(){
	
	local menu msg=$1 title=$2 button=$3
	shift 3
	
	local options=("$@")
	
	menu=$(
		whiptail --menu "$msg" --title "$title" --cancel-button "$button" 0 50 0 "${options[@]}" 3>&1 1>&2 2>&3
	)
	exit_code
	
	printf "%s" "$menu"
}

#########################################################
#########################################################


# Memilih target untuk mengatur snapshot root/home
target_snapshot(){
	
	local options
	
	# loop membuat daftar pilihan
	while true; do
		options=(
			'home' ' : Atur snapshot home direktory'
			'root' ' : Atur snapshot system root)'
		)
		
	# menampilkan daftar menu (home/root)
	TARGET_SNAPSHOT=$(
		menu_box 'Pilih target:' 'SNAPSHOT' 'Exit' "${options[@]}"
	)
	exit_code
	
	main_menu
	
	done
}

# Membuat snapshot
creat_snapshot(){
	
	local SNAPSHOT_NAME msgs="Nama snapshot:\nNOTE: simbol '@' akan otomatis ditambahkan diawal nama."
	
	# menyimpan input user sebagai nama untuk snapshot baru
	SNAPSHOT_NAME=$(
		input_box "$msgs" "${TARGET_SNAPSHOT}_$(date +"%Y-%m-%d_%H%M%S")"
	)
	
	[ -n "$SNAPSHOT_NAME" ] && SNAPSHOT_NAME="@${SNAPSHOT_NAME}"
	
	# membuat snapshot
	if [ "$TARGET_SNAPSHOT" == 'root' ] && [ -n "$SNAPSHOT_NAME" ]; then
	
		sudo btrfs subvolume snapshot /mnt/$DEFAULT_ACTIVE_NAME /mnt/$SNAPSHOT_NAME >/dev/null 2>&1 &
		msg="Snapshot berhasil dibuat.\nNama: $SNAPSHOT_NAME\nPath: $MOUNTPOINT"
	
	elif [ "$TARGET_SNAPSHOT" == 'home' ] && [ -n "$SNAPSHOT_NAME" ]; then
		sudo chmod 777 /mnt
	
		btrfs subvolume snapshot /mnt/$DEFAULT_ACTIVE_NAME /mnt/$SNAPSHOT_NAME >/dev/null 2>&1 &
		msg="Snapshot berhasil dibuat.\nNama: $SNAPSHOT_NAME\nPath: $MOUNTPOINT"
	fi
	
}

# Restore/hapus snapshot
restore_delete(){
	
	local SELECTED
	SELECTED=$1	title=$2
	
	# Restore snapshot
	restore_snapshot(){
		
		local tanggal_dibuat current_date before_restore SET_FSTAB
		
		if [ "$?" -eq 0 ] && [ -n "$SELECTED_FILE" ]; then
			
			whiptail --title 'RESTORING SNAPSHOT' --yesno \
				"sebelum melanjutkan, mohon simpan semua tugas anda terlebih dahulu,\
				\nkarena setelah proses ini selesai system akan otomatis restart." 0 0
			
			if [ "$?" -eq 0 ]; then
			
				# cek snapshot yg sedang aktif
				GEN_ACTIVE_SNAPSHOT=$(
					sudo btrfs subvolume list ${MOUNTPOINT} | awk '{if ($4 > max) max = $4} END {print max}'
				)
	
				# mendapatkan nama snapshot yg sedang aktif
				CHECKED_ACTIVE_SNAPSHOT=$(
					sudo btrfs subvolume list ${MOUNTPOINT} | awk "/$GEN_ACTIVE_SNAPSHOT/" | awk '{print $9}'
				)
				
				# mendapatkan tanggal dibuat sebuah file
				tanggal_dibuat=$(
					stat -c %y "/mnt/${CHECKED_ACTIVE_SNAPSHOT}" | awk '{print $1}'
				)
				
				# get tangal dan jam saat ini
				current_date=$(date +"%Y-%m-%d_%H%M%S")
				
				# rename snapshot saat ini sebelum merestore snapshot lain
				before_restore="@${TARGET_SNAPSHOT}_before_restore_data_${tanggal_dibuat}_sampai_${current_date}"
				
				
				if [ -z "$GEN_ACTIVE_SNAPSHOT" ]; then
		
					if [ "$TARGET_SNAPSHOT" == 'root' ]; then
						sudo btrfs subvolume snapshot $MOUNTPOINT /mnt/${DEFAULT_ACTIVE_NAME} >/dev/null 2>&1 &
					elif [ "$TARGET_SNAPSHOT" == 'home' ]; then
						sudo chmod 777 /mnt

						[ -d "/mnt/$DEFAULT_ACTIVE_NAME" ] && mv /mnt/$DEFAULT_ACTIVE_NAME /mnt/${before_restore}
						btrfs subvolume snapshot $MOUNTPOINT /mnt/${DEFAULT_ACTIVE_NAME} >/dev/null 2>&1 &
					fi
					
				elif [ -n "$GEN_ACTIVE_SNAPSHOT" ]; then
				
					[ "$TARGET_SNAPSHOT" == 'home' ] && sudo chmod 777 /mnt
					
					mv /mnt/${DEFAULT_ACTIVE_NAME} /mnt/${before_restore}
					sudo btrfs subvolume delete /mnt/${DEFAULT_ACTIVE_NAME}
					mv /mnt/${SELECTED_FILE} /mnt/${DEFAULT_ACTIVE_NAME}
					
				fi
				
				
			fi
			
			SET_FSTAB="$?"
			
			configure_fstab
			
			# restart sistem dalam waktu 6 detik jika $SET_FSTAB bernilai 0
			if [ "$SET_FSTAB" -eq 0 ]; then
				
				configure_fstab
				
				msg="berhasil Restore snapshot.\nSystem akan restart dalam 5 detik..."
				nohup bash -c "sleep 5 && kill $PPID" >/dev/null 2>&1 &
				nohup bash -c "sleep 6 && systemctl reboot" >/dev/null 2>&1 &
			fi
			
		else
			msg='Pilih menu :'
		fi
		
	}
	
	# Hapus snapshot
	delete_snapshot(){
		
		if [ "$?" -eq 0 ] && [ -n "$SELECTED_FILE" ]; then
			
			# pesan konfirmasi untuk menghapus atau batalkan
			whiptail --title 'DELETE SNAPSHOT' --yesno \
				"Apakah yakin ingin menghapus snapshot ini?\nSelected: $SELECTED_FILE" 0 0
			
			if [ "$?" -eq 0 ]; then
				
				# menghapus snapshot yg dipilih
				sudo btrfs subvolume delete /mnt/$SELECTED_FILE
				
				msg="Selected: '${SELECTED_FILE}'\nSnapshot berhasil dihapus."
			fi
			
		else
		
			msg='Pilih menu :'
		fi
	}
	
	# Menyimpan daftar file dalam variabel array
	file_list=($(
		sudo btrfs subvolume list $MOUNTPOINT | grep -v "$DEFAULT_ACTIVE_NAME" | awk '{print $9}'
	))
	
	if [ -z "$file_list" ]; then
		# menampilkan pesan jika file_list kosong
		whiptail --title "SNAPSHOT" --msgbox "Tidak ada snapshot." 0 0
		return
		
	else
		# Looping untuk membuat opsi menu
		options=()
		for file in "${file_list[@]}"; do
			# Mengambil nama file tanpa awalan
			options+=("$file" "")
		done

		# Menampilkan menu menggunakan Whiptail
		SELECTED_FILE=$(
			menu_box 'Pilih File:' "$title" 'Back' "${options[@]}"
		)
	
		$SELECTED
	fi
}	

configure_fstab(){
	
	# generate variabel global
	global_variabel
	
	set_fstab(){
		
		local add_config root_config home_config set_config=true
		
		# Mendapatkan uuid $PATH_TARGET_SNAPSHOT
		UUID=$(sudo blkid -s UUID -o value $PATH_TARGET_SNAPSHOT)

		#root_config="UUID=$UUID $MOUNTPOINT defaults,subvol=${DEFAULT_ACTIVE_NAME},compress=zstd,space_cache 0 0"
		home_config="UUID=$UUID $MOUNTPOINT btrfs defaults,subvol=${DEFAULT_ACTIVE_NAME} 0 1"
	
		[ "$TARGET_SNAPSHOT" == 'home' ] && add_config="$home_config" #|| add_config="$root_config"
		
		if [  "$TARGET_SNAPSHOT" == 'home' ]; then
			if [[ "$SET_FSTAB" -eq 0 ]] && ! [ "$(grep "$add_config" /etc/fstab)" ] && [ "$(grep "/home" /etc/fstab)" ]; then
			
				! [ -f "/etc/backup.fstab" ] sudo cp /etc/fstab /etc/backup.fstab
				
				[ "$(sed -n '/\/home/p' /etc/fstab)" ] && sudo sed -i '/\/home/d' /etc/fstab
				echo "$add_config" | sudo tee -a /etc/fstab
			fi
		fi
	}
	
	# cek snapshot yg sedang aktif
	GEN_ACTIVE_SNAPSHOT=$(
		sudo btrfs subvolume list ${MOUNTPOINT} | awk '{if ($4 > max) max = $4} END {print max}'
	)
	
	if [ -n "$GEN_ACTIVE_SNAPSHOT" ]; then
		# mendapatkan nama snapshot yg sedang aktif
		CHECKED_ACTIVE_SNAPSHOT=$(
			sudo btrfs subvolume list ${MOUNTPOINT} | awk "/$GEN_ACTIVE_SNAPSHOT/" | awk '{print $9}'
		)
	fi
	
	[ "$SET_FSTAB" -eq 0 ] && [ -n "$CHECKED_ACTIVE_SNAPSHOT" ] && set_fstab
	
 }

main_menu(){
	
	local options MENU msg
	# umount jika terdeteksi ada mountpint /mnt
	umount_disk
	# mount target_path ke /mnt
	mount_disk
	
	msg='Pilih menu:'
	
	#loop daftar menu
	while true; do
		
		options=(
			'Create' ' : Buat snapshot baru' 
			'Restore' ' : Pilih snapshot dari daftar lalu restore'
			'Delete' ' : Pilih snapshot dari daftar lalu hapus'
			'SET_FSTAB' ' : configure'
		)
		
		# menampilkan pilihan menu
		MENU=$(
			menu_box "$msg" 'MAIN MENU' 'Back' "${options[@]}"
		)
		
		[ "$?" -ne 0 ] && break
	
		case $MENU in
			'SET_FSTAB' )
				configure_fstab
			;;
			'Create' )
				creat_snapshot
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
