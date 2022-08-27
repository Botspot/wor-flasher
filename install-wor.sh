#!/bin/bash

#Written by Botspot
#This script is an automation for the tutorial that can be found here: https://worproject.com/guides/how-to-install/from-other-os

error() { #Input: error message
  echo -e "\\e[91m$1\\e[39m" 1>&2
  [ "$RUN_MODE" == gui ] && zenity --error --title "$(basename "$0")" --width 360 --text "$(echo -e "An error has occurred:\n$1\nExiting now." | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*//g' | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")"
  exit 1
}

echo_white() {
  echo -e "\e[40m\e[97m${1}\e[39m\e[49m"
}

#Determine the directory to download windows component files to
[ -z "$DL_DIR" ] && DL_DIR="$HOME/wor-flasher-files"

#Determine the directory that contains this script
[ -z "$DIRECTORY" ] && DIRECTORY="$(readlink -f "$(dirname "$0")")"

#clear the variable storing path to this script, if the folder does not contain a file named 'install-wor.sh'
[ ! -f "${DIRECTORY}/install-wor.sh" ] && DIRECTORY=''

#Determine what /dev/ block-device is the system's rootfs device. This drive is exempted from the list of available flashing options.
ROOT_DEV="/dev/$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")"

{ #check for updates and auto-update if the no-update files does not exist
if [ -e "$DIRECTORY" ] && [ ! -f "${DIRECTORY}/no-update" ];then
  prepwd="$(pwd)"
  cd "$DIRECTORY"
  localhash="$(git rev-parse HEAD)"
  latesthash="$(git ls-remote https://github.com/Botspot/wor-flasher HEAD | awk '{print $1}')"
  
  if [ "$localhash" != "$latesthash" ] && [ ! -z "$latesthash" ] && [ ! -z "$localhash" ];then
    echo_white "Auto-updating wor-flasher for the latest features and improvements..."
    echo_white "To disable this next time, create a file at ${DIRECTORY}/no-update"
    sleep 1
    git pull | cat
    
    echo_white "git pull finished. Reloading script..."
    set -a #export all variables so the script can see them
    #run updated script in background
    "$0" "$@"
    exit $?
  fi
  cd "$prepwd"
fi
}

wget() { #wrapper function for the wget command for better reliability
  command wget --no-check-certificate -4 "$@"
}

package_available() { #determine if the specified package-name exists in a repository
  local package="$1"
  [ -z "$package" ] && error "package_available(): no package name specified!"
  #using grep to do this is nearly instantaneous, rather than apt-cache which takes several seconds
  grep -rqx "Package: $package" /var/lib/apt/lists --exclude="lock" --exclude-dir="partial" 2>/dev/null
}

package_installed() { #exit 0 if $1 package is installed, otherwise exit 1
  local package="$1"
  [ -z "$package" ] && error "package_installed(): no package specified!"
  #find the package listed in /var/lib/dpkg/status
  #package_info "$package"
  
  #directly search /var/lib/dpkg/status
  grep "^Package: $package$" /var/lib/dpkg/status -A 1 | tail -n 1 | grep -q 'Status: install ok installed'
}

install_packages() { #input: space-separated list of apt packages to install
  [ -z "$1" ] && error "install_packages(): requires a list of apt packages to install"
  local dependencies="$1"
  local install_list=''
  local package
  
  local IFS=' '
  for package in $dependencies ;do
    if ! package_installed "$package" ;then
      #if the currently-checked package is not installed, add it to the list of packages to install
      if [ -z "$install_list" ];then
        install_list="$package"
      else
        install_list="$install_list $package"
      fi
    fi
  done
  
  if [ ! -z "$install_list" ];then
    echo_white "Installing packages: $install_list"
    sudo apt update || error "Failed to run 'sudo apt update'! This is not an error in WoR-flasher."
    sudo apt install -yf $install_list --no-install-recommends || error "Failed to install dependency packages! This is not an error in WoR-flasher."
  fi
}

download_from_gdrive() { #Input: file UUID and filename
  [ -z "$1" ] && error "download_from_gdrive(): requires a Google Drive file UUID!\nFile UUID is the end of a sharable link: https://drive.google.com/uc?export=download&id=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  [ -z "$2" ] && error "download_from_gdrive(): requires specifying a filename to save to."
  
  local FILEUUID="$1"
  local FILENAME="$2"
  
  wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies 'https://docs.google.com/uc?export=download&id='"$FILEUUID" -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=$FILEUUID" -O "$2" && rm -rf /tmp/cookies.txt
  
}

get_partition() { #Input: device & partition number. Output: partition /dev entry
  [ -z "$1" ] && error "get_partition(): no /dev device specified as"' $1'
  [ -z "$2" ] && error "get_partition(): no partition number specified as"' $2'
  [ ! -b "$1" ] && error "get_partition(): $1 is not a valid block device!"
  
  if [ "$2" == 'all' ];then
    #special mode: return every partition if $2 is 'all'
    lsblk -nro NAME "$1" | sort -n | sed 's+^+/dev/+g' | grep -vx "$1"
  else #provided with partition number
    #list drive and partitions in $1, filter out the drive, then get the Nth line
    lsblk -nro NAME "$1" | sort -n | sed 's+^+/dev/+g' | grep -vx "$1" | sed -n "$2"p
  fi
}

get_name() { #get human-readable name of device: manufacturer and model name
  #Botspot made this by reverse-engineering the usb-devices command and udevadm commands.
  #input: /dev device
  [ -z "$1" ] && error "get_name(): requires an argument"
  [ ! -b "$1" ] && error "get_name(): Specified block device '$1' does not exist!"
  
  sys_path="$(find /sys/devices/platform -type d -name "$(basename "$1")")"
  #sys_path may be: /sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-2/2-2:1.0/host0/target0:0:0/0:0:0:0/block/sda
  
  if [ -z "$sys_path" ];then
    echo "get_name(): Failed to find a /sys/devices/platform entry for '$1'. Continuing." 1>&2
    return 1
  fi
  
  #Go up 6 directories:
  sys_path="$(echo "$sys_path" | tr '/' '\n' | head -n -6 | tr '\n' '/')"
  #sys_path may be: /sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-2/
  
  product="$(cat "${sys_path}product" 2>/dev/null)"
  manufacturer="$(cat "${sys_path}manufacturer" 2>/dev/null)"
  #serial="$(cat "$sys_path"/serial)"
  
  if [ -z "$product$manufacturer" ] && [[ "$1" == /dev/mmcblk* ]];then
    manufacturer="SD card"
  fi
  
  if [ "$manufacturer" != "$product" ];then
    echo "$manufacturer $product" | sed 's/ $//g' | sed 's/^ //g'
  else
    echo "$manufacturer"
  fi
}

get_size_raw() { #Input: device. Output: total size of device in bytes
  lsblk -b --output SIZE -n -d "$1"
}

get_space_free() { #Input: folder to check. Output: show many bytes can fit before the disk is full
  df -B 1 "$1" --output=avail | tail -1 | tr -d ' '
}

list_devs() { #Output: human-readable, colorized list of valid block devices to write to. Omits /dev/loop* and the root device
  local IFS=$'\n'
  for device in $(lsblk -I 8,179,259 -dno NAME | sed 's+^+/dev/+g' | grep -v loop | grep -vx "$ROOT_DEV") ;do
    echo -e "\e[1m\e[97m${device}\e[0m - \e[92m$(lsblk -dno SIZE "$device")B\e[0m - \e[36m$(get_name "$device")\e[0m"
  done
}

get_uuid() { #input: '11', '10' Output: build ID like 'db8ec987-d136-4421-afb8-2ef109396b00'
  local WIN_VER="$1"
  if [ -z "$WIN_VER" ];then
    error "get_uuid(): requires an argument for windows version to fetch: '10', '11'"
  elif [ "$WIN_VER" != 11 ] && [ "$WIN_VER" != 10 ];then
    error "get_uuid(): unrecognized argument '$WIN_VER'. Allowed values: '10', '11'"
  fi
  
  local search
  if [ "$WIN_VER" == 11 ];then
    search="$(wget -qO- 'https://api.uupdump.net/listid.php' | tr '}' '\n' | sed 's/,{//' | grep . | grep ',"arch":"arm64"' | grep 'Windows 11' | grep -v "Insider Preview" | grep -o '"uuid":".*"' | awk -F'"' '{print $4}')"
    if [ ${PIPESTATUS[0]} != 0 ] || [ -z "$search" ];then
      error "get_uuid(): Failed to get list of Windows 11 versions.\nPlease check if <a href="\""https://uupdump.net"\"">uupdump.net</a> can be reached from your web browser."
    fi
  elif [ "$WIN_VER" == 10 ];then
    search="$(wget -qO- 'https://api.uupdump.net/listid.php' | tr '}' '\n' | sed 's/,{//' | grep . | grep ',"arch":"arm64"' | grep 'Windows 10' | grep -v "Insider Preview" | grep -o '"uuid":".*"' | awk -F'"' '{print $4}')"
    if [ ${PIPESTATUS[0]} != 0 ] || [ -z "$search" ];then
      error "get_uuid(): Failed to get list of Windows 10 versions.\nPlease check if <a href="\""https://uupdump.net"\"">uupdump.net</a> can be reached from your web browser."
    fi
  fi
  
  #Sometimes the newest UUP is incomplete for a while, resulting in ERROR 500. This flag allows an older uup to be chosen with 2, 3, 4, etc.
  local i=1
  local UUID
  while true;do
    UUID="$(echo "$search" | sed -n ${i}p)"
    
    #Check if UUID exists
    if [ -z "$UUID" ];then
      error "get_uuid(): Failed to find a working Update ID for Windows $WIN_VER. Please report this issue to Botspot."
      
    elif validate_uuid "$UUID" ;then
      #Successfully found a valid Update ID that will download okay
      break
    else
      echo "get_uuid(): Update ID $UUID is incomplete; using older one..." 1>&2
      i=$((i+1)) #Now get the next available option in the list
    fi
    
  done
  
  #Return the UUID
  echo "$UUID"
}

check_uuid() { #return 0 if input is in a valid uuid format, return 1 otherwise
  if [[ $1 =~ ^\{?[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}\}?$ ]];then
    return 0
  else
    return 1
  fi
}

validate_uuid() { #Check if the uupdump website can successfully download scripts for the specified Windows Update ID
  if [ -z "$1" ];then
    error "validate_uuid(): no UUID specified!"
  fi
  
  while true;do
    output="$(wget --spider --server-response "https://uupdump.net/get.php?id=${1}&pack=en-us&edition=professional&autodl=2" 2>&1)"
    
    if [ $? == 0 ];then
      #wget succeeded, so link is good
      return 0
    elif grep -q '429 Too Many Requests' <<<"$output" ;then
      #encountered rate-limit; wait and try again. Failed attempts don't reset the server's timeout, so keep polling every second
      sleep 1
    else
      #wget failed and it did not encounter the rate-limit
      return 1
    fi
  done
  
}

list_langs() { #input: build id, Output: colon-separated list of langs and their labels
  [ -z "$1" ] && error "list_langs(): requires an argument for windows update ID. Example ID: db8ec987-d136-4421-afb8-2ef109396b00"
  local langs="$(wget -qO- "https://api.uupdump.net/listlangs.php?id=$1" | sed 's/.*langFancyNames":{//g' | sed 's/},"updateInfo":.*//g' | tr '{,[' '\n' | tr -d '"' | sort)"
  
  if [ -z "$langs" ];then
    error "Failed to get a list of languages from uupdump.net. Please check your Internet connection. Error was:\n$(wget -O /dev/null "https://api.uupdump.net/listlangs.php?id=$1" 2>&1)"
  fi
  echo "$langs"
}

get_os_name() { #input: build id Output: human-readable name of operating system
  [ -z "$1" ] && error "get_os_name(): requires an argument for windows update ID. Example ID: db8ec987-d136-4421-afb8-2ef109396b00"
  local wget_out="$(wget -qO- "https://api.uupdump.net/listlangs.php?id=${1}" | sed 's/.*"updateInfo"://g' | tr '{,[' '\n' | tr -d '"}]')"
  [ -z "$wget_out" ] && error "get_os_name(): failed to retrieve data for $1"
  
  #example value: 'Windows 11'
  local version="Windows $(echo "$wget_out" | grep '^title:' | tr ' ' '\n' | grep 'Windows' --after 1 | tail -1)"
  #example value: 'build 22000.160'
  local build="$(echo "$wget_out" | grep '^build:' | awk -F: '{print $2}')"
  
  echo -e "$version build $build"
}

uupdump() { #Download Windows image for the $1 uuid and the $2 language
  local UUID="$1"
  [ -z "$UUID" ] && error "uupdump(): must specify windows update ID. Example ID: db8ec987-d136-4421-afb8-2ef109396b00"
  
  local WIN_LANG="$2"
  [ -z "$WIN_LANG" ] && error "uupdump(): must specify language for Windows ISO! Run the list_langs function to see available options."
  
  echo_white "Downloading uupdump script to legally generate Windows ISO"
  
  rm -rf "$(pwd)/uupdump"
  wget -O "$(pwd)/uupdump.zip" "https://uupdump.net/get.php?id=${UUID}&pack=${WIN_LANG}&edition=professional&autodl=2" || error "uupdump(): Failed to download uupdump.zip"
  unzip -q "$(pwd)/uupdump.zip" -d "$(pwd)/uupdump" || error "Failed to extract $(pwd)/uupdump.zip"
  rm -f "$(pwd)/uupdump.zip"
  chmod +x "$(pwd)/uupdump/uup_download_linux.sh" || error "Failed to mark $(pwd)/uupdump/uup_download_linux.sh script as executable!"
  
  #add /usr/sbin to PATH variable so the chntpw command can be found
  export PATH="$(echo "${PATH}:/usr/sbin" | tr ':' '\n' | sort | uniq | tr '\n' ':')"
  
  #run uup_download_linux.sh
  echo_white "Generating Windows image with uupdump"
  cd "$(pwd)/uupdump"
  #Allow uupdump to fail 4 times before giving up
  for i in {1..4}; do
    nice "$(pwd)/uup_download_linux.sh"
    if [ $? == 0 ];then
      echo_white "\nuup_download_linux.sh successfully generated a complete Windows image."
      uup_failed=0
      break
    else
      echo_white "\nuup_download_linux.sh failed, most likely due to unreliable Internet.\nTrying again in 1 minute. (Attempt $i of 4)"
      uup_failed=1
      rm -rf "$(pwd)/uupdump"
      sleep 60
    fi
  done
  cd ..
  
  #check that the ISO file really does exist and filename includes 'ARM64'
  if [ "$uup_failed" == 1 ];then
    error "Failed to generate a Windows ISO! uup_download_linux.sh exited with an error so please see the errors above."
  elif [ ! -f "$(pwd)/uupdump"/*ARM64*.ISO ];then
    error "Failed to generate a Windows ISO! uup_download_linux.sh did not exit with an error, but there is no file matching "\""$(pwd)/uupdump/*ARM64*.ISO"\"""
  fi
}

setup() { #run safety checks and install packages
  #check for internet connection
  echo -n "Checking for internet connection... "
  local wget_errors="$(command wget --spider github.com 2>&1)"
  if [ $? != 0 ];then
    error "No internet connection!\ngithub.com failed to respond.\nErrors: $wget_errors"
  fi
  echo Done
  
  if [ "$(id -u)" == 0 ];then
    echo_white "WoR-flasher is not designed to be run as root.\nDoing so is known to cause problems."
    echo -n "Are you sure you want to continue? [y/N]"
    read answer
    echo "$answer"
    if [ -z "$answer" ] || [ "$answer" != y ];then
      exit 1
    fi
    for i in {60..0}; do
      echo -ne "You have $i seconds to reconsider your decision.\033[0K\r"
      sleep 1
    done
  fi
  
  #Make sure that DL_DIR is not set to a drive with a FAT-type partition
  if df -T "$DL_DIR" 2>/dev/null | grep -q 'fat' ;then
    error "The $DL_DIR directory is on a FAT32/FAT16/vfat partition. This type of partition cannot contain files larger than 4GB, however the Windows image will be 4.3GB.\nPlease format $DL_DIR to use an Ext4 partition."
  fi
  
  #Make sure modules exist for the running kernel - otherwise a kernel upgrade occurred and the user needs to reboot. See https://github.com/Botspot/wor-flasher/issues/35
  if [ ! -d /lib/modules/$(uname -r) ];then
    error "The running kernel ($(uname -r)) does not match any directory in /lib/modules.
Usually this means you have not yet rebooted since upgrading the kernel.
Try rebooting.
If this error persists, contact Botspot - the WoR-flasher developer."
  fi
  
  #install dependencies
  install_packages 'yad aria2 cabextract wimtools chntpw genisoimage exfat-fuse wget udftools' || exit 1
  
  #install exfat partition manipulation utility. exfatprogs replaces exfat-utils, but they cannot both be installed at once.
  if package_available exfatprogs && ! package_installed exfat-utils ;then
    install_packages exfatprogs || exit 1
  else
    install_packages exfat-utils || exit 1
  fi
}

[ "$1" == 'source' ] && return 0 #If being sourced, exit here at this point in the script
#past this point, this script is being run, not sourced.

#Ensure this script's parent directory is valid
[ ! -e "$DIRECTORY" ] && error "install-wor.sh: Failed to determine the directory that contains this script. Try running this script with full paths."

LANG=C
LC_ALL=C
LANGUAGE=C

setup || exit 1

#Create folder to download everything to
mkdir -p "$DL_DIR"
cd "$DL_DIR"

#unless specified otherwise, run this script in cli mode
[ -z "$RUN_MODE" ] && RUN_MODE=cli #RUN_MODE=gui

{ #choose windows version
if [ -z "$UUID" ];then
  while true; do
    echo -ne "\nChoose Windows version:
\e[97m\e[1m1\e[0m) Windows 11
\e[97m\e[1m2\e[0m) Windows 10
\e[97m\e[1m3\e[0m) Custom...
Enter \e[97m\e[1m1\e[0m, \e[97m\e[1m2\e[0m or \e[97m\e[1m3\e[0m: "
    read REPLY
    
    case $REPLY in
      1)
        #Windows 11
        echo "Finding build ID..."
        UUID="$(get_uuid 11)"
        break
        ;;
      2)
        #Windows 10
        echo "Finding build ID..."
        UUID="$(get_uuid 10)"
        break
        ;;
      3)
        #custom
        read -p $'\nEnter a Windows build ID below.\nGo to https://uupdump.net to browse windows versions.\nExample ID: db8ec987-d136-4421-afb8-2ef109396b00\nID: ' UUID
        check_uuid "$UUID" && break || echo "Invalid UUID."
        ;;
      *) echo "Invalid option ${REPLY}. Expected '1', '2' or '3'.";;
    esac
  done
  
  echo "Selected build ID: $UUID"
  echo "Selected Windows version: $(get_os_name "$UUID")"
  echo
fi
}

{ #choose language
if [ -z "$WIN_LANG" ];then
  echo "Finding languages..."
  LANG_LIST="$(list_langs "$UUID" | awk -F: '{print $1}')"
  echo "$LANG_LIST" | tr '\n' ' ' | fold -s -w $COLUMNS
  echo
  echo -n "Choose language: "
  while true; do
    read WIN_LANG
    
    if echo "$LANG_LIST" | grep -qx "$WIN_LANG" ;then
      #if selected language matches line in language list
      break
    else
      echo -ne "Invalid choice "\""$WIN_LANG"\"". Please try again.\nChoose language: "
    fi
    
  done
  echo
else
  LANG_LIST="$(list_langs "$UUID" | awk -F: '{print $1}')"
  if ! echo "$LANG_LIST" | grep -qx "$WIN_LANG" ;then
    error "Invalid WIN_LANG value "\""$WIN_LANG"\"".\nAvailable languages for this Windows build:\n$LANG_LIST"
  fi
fi
}

{ #choose destination RPi model
if [ -z "$RPI_MODEL" ];then
  while true; do
    echo -ne "Choose Raspberry Pi model to deploy Windows on:
\e[97m\e[1m1\e[0m) Raspberry Pi 4 / 400
\e[97m\e[1m2\e[0m) Raspberry Pi 3 or Pi2 v1.2
Enter \e[97m\e[1m1\e[0m or \e[97m\e[1m2\e[0m: "
    read REPLY
    case $REPLY in
      1)
        RPI_MODEL=4
        break
        ;;
      2)
        RPI_MODEL=3
        break
        ;;
      *) echo "Invalid option ${REPLY}. Expected '1' or '2'.";;
    esac
  done
  echo
elif [ "$RPI_MODEL" != 3 ] && [ "$RPI_MODEL" != 4 ];then
  error "Unknown value for RPI_MODEL. Expected '3' or '4'."
fi
}

{ #choose output device
if [ -z "$DEVICE" ];then
  while true;do
    echo "Available devices:"
    list_devs
    read -p "Choose a device to flash the Windows setup files to: " DEVICE
    if [ -b "$DEVICE" ];then
      break #exit loop
    else
      echo -e "Device $DEVICE is not a valid block device! Available devices:\n$(list_devs)"
    fi
  done
  echo
elif [ ! -b "$DEVICE" ];then
  error "Invalid value for DEVICE: block device $DEVICE does not exist. Available devices:\n$(list_devs)"
fi
}

{ #CAN_INSTALL_ON_SAME_DRIVE
if [ -z "$CAN_INSTALL_ON_SAME_DRIVE" ];then
  while true; do
    echo -ne "\e[97m\e[1m1\e[0m) Create an installation drive (minimum 25 GB) capable of installing Windows to itself
\e[97m\e[1m2\e[0m) Create a recovery drive (minimum 7 GB) to install Windows on other >16 GB drives
Choose the installation mode (\e[97m\e[1m1\e[0m or \e[97m\e[1m2\e[0m): "
    read REPLY
    case $REPLY in
      1)
        CAN_INSTALL_ON_SAME_DRIVE=1
        break
        ;;
      2)
        CAN_INSTALL_ON_SAME_DRIVE=0
        break
        ;;
      *) echo "Invalid option ${REPLY}. Expected '1' or '2'.";;
    esac
  done
  echo
elif [ "$CAN_INSTALL_ON_SAME_DRIVE" != 0 ] && [ "$CAN_INSTALL_ON_SAME_DRIVE" != 1 ];then
  error "Unknown value for CAN_INSTALL_ON_SAME_DRIVE. Expected '0' or '1'."
fi

if [ "$CAN_INSTALL_ON_SAME_DRIVE" == 1 ];then
  #drive must be 25gb
  if [ "$(get_size_raw "$DEVICE")" -lt $((25*1024*1024*1024)) ];then
    error "Drive $DEVICE is smaller than 25GB and cannot be used for self-installation."
  fi
elif [ "$CAN_INSTALL_ON_SAME_DRIVE" == 0 ];then
  #drive must be 7gb
  if [ "$(get_size_raw "$DEVICE")" -lt $((7*1024*1024*1024)) ];then
    error "Drive $DEVICE is smaller than 7GB and cannot be used."
  fi
fi
}

echo "Input configuration:
DL_DIR: $DL_DIR
RUN_MODE: $RUN_MODE
RPI_MODEL: $RPI_MODEL
DEVICE: $DEVICE
CAN_INSTALL_ON_SAME_DRIVE: $CAN_INSTALL_ON_SAME_DRIVE
UUID: $UUID
WIN_LANG: $WIN_LANG"
[ ! -z "$CONFIG_TXT" ] && echo "CONFIG_TXT: ⤵
$(echo "$CONFIG_TXT" | grep . | sed 's/^/  > /g')
CONFIG_TXT: ⤴"
[ ! -z "$DRY_RUN" ] && echo "DRY_RUN: $DRY_RUN"
echo

if [ ! -d "$(pwd)/peinstaller" ];then
  echo_white "Downloading WoR PE-based installer from Google Drive"
  
  PE_INSTALLER_SHA256=$(wget -qO- http://worproject.com/dldserv/worpe/gethashlatest.php | cut -d ':' -f2)
  [ -z "$PE_INSTALLER_SHA256" ] && error "Failed to determine a hashsum for WoR PE-based installer.\nURL: http://worproject.com/dldserv/worpe/gethashlatest.php"
  
  #from: https://worproject.com/downloads#windows-on-raspberry-pe-based-installer
  URL='http://worproject.com/dldserv/worpe/downloadlatest.php'
  #determine Google Drive FILEUUID from given redirect URL
  FILEUUID="$(wget --spider --content-disposition --trust-server-names -O /dev/null "$URL" 2>&1 | grep Location | sed 's/^Location: //g' | sed 's/ \[following\]$//g' | grep 'drive\.google\.com' | sed 's+.*/++g' | sed 's/.*&id=//g')"
  download_from_gdrive "$FILEUUID" "$(pwd)/WoR-PE_Package.zip" || error "Failed to download Windows on Raspberry PE-based installer"
  
  if [ "$PE_INSTALLER_SHA256" != "$(sha256sum "$(pwd)/WoR-PE_Package.zip" | awk '{print $1}' | tr '[a-z]' '[A-Z]')" ];then
    error "PE-based installer integrity check failed"
  fi
  
  rm -rf "$(pwd)/peinstaller"
  unzip -q "$(pwd)/WoR-PE_Package.zip" -d "$(pwd)/peinstaller"
  if [ $? != 0 ];then
    rm -rf "$(pwd)/peinstaller"
    error "The unzip command failed to extract $(pwd)/WoR-PE_Package.zip"
  fi
  rm -f "$(pwd)/WoR-PE_Package.zip"
  echo
else
  echo "Not downloading $(pwd)/peinstaller - folder exists"
fi

if [ ! -d "$(pwd)/driverpackage" ];then
  echo_white "Downloading driver package"
  #from: https://github.com/worproject/RPi-Windows-Drivers/releases
  #example download URL (will be outdated) https://github.com/worproject/RPi-Windows-Drivers/releases/download/v0.11/RPi4_Windows_ARM64_Drivers_v0.11.zip
  #determine latest release download URL:
  URL="$(wget -qO- https://api.github.com/repos/worproject/RPi-Windows-Drivers/releases/latest | grep '"browser_download_url":'".*RPi${RPI_MODEL}_Windows_ARM64_Drivers_.*\.zip" | sed 's/^.*browser_download_url": "//g' | sed 's/"$//g')"
  wget -O "$(pwd)/RPi${RPI_MODEL}_Windows_ARM64_Drivers.zip" "$URL" || error "Failed to download driver package"
  
  rm -rf "$(pwd)/driverpackage"
  unzip -q "$(pwd)/RPi${RPI_MODEL}_Windows_ARM64_Drivers.zip" -d "$(pwd)/driverpackage"
  if [ $? != 0 ];then
    rm -rf "$(pwd)/driverpackage"
    error "The unzip command failed to extract $(pwd)/RPi${RPI_MODEL}_Windows_ARM64_Drivers.zip"
  fi
  
  rm -f "$(pwd)/RPi${RPI_MODEL}_Windows_ARM64_Drivers.zip"
  echo
else
  echo "Not downloading $(pwd)/driverpackage - folder exists"
fi

if [ ! -d "$(pwd)/uefipackage" ];then
  echo_white "Downloading UEFI package"
  rm -rf "$(pwd)/uefipackage" "$(pwd)/RPi${RPI_MODEL}_UEFI_Firmware.zip"
  #from: https://github.com/pftf/RPi4/releases
  #example download URL (will be outdated) https://github.com/pftf/RPi4/releases/download/v1.29/RPi4_UEFI_Firmware_v1.29.zip
  
  #determine latest release download URL:
  URL="$(wget -qO- https://api.github.com/repos/pftf/RPi${RPI_MODEL}/releases/latest | grep '"browser_download_url":'".*RPi${RPI_MODEL}_UEFI_Firmware_.*\.zip" | sed 's/^.*browser_download_url": "//g' | sed 's/"$//g')"
  #URL='https://github.com/pftf/RPi4/releases/download/v1.28/RPi4_UEFI_Firmware_v1.28.zip'
  
  wget -O "$(pwd)/RPi${RPI_MODEL}_UEFI_Firmware.zip" "$URL" || error "Failed to download UEFI package"
  
  rm -rf "$(pwd)/uefipackage"
  unzip -q "$(pwd)/RPi${RPI_MODEL}_UEFI_Firmware.zip" -d "$(pwd)/uefipackage"
  if [ $? != 0 ];then
    rm -rf "$(pwd)/uefipackage"
    error "The unzip command failed to extract $(pwd)/RPi${RPI_MODEL}_UEFI_Firmware.zip"
  fi
  
  rm -f "$(pwd)/RPi${RPI_MODEL}_UEFI_Firmware.zip"
  echo
else
  echo "Not downloading $(pwd)/uefipackage - folder exists"
fi

#get UUPDump package
#get other versions from: https://uupdump.net/
if [ ! -f "$(pwd)/uupdump"/*ARM64*.ISO ];then
  sync
  if [ "$(get_space_free "$DL_DIR")" -lt 11863226125 ];then
    error "Your system needs 11.8GB of free space to download the Windows components to.
If your sd card is too small to do this, you can set the DL_DIR variable
to a mounted drive with sufficient space. (Must be an Ext4 partition)"
  fi
  
  uupdump "$UUID" "$WIN_LANG" || exit 1
else
  echo_white "Reusing same Windows image that was generated in the past"
fi

if [ "$DRY_RUN" == 1 ];then
  echo_white "Exiting install-wor.sh script now because the DRY_RUN variable was set to '1'."
  exit 0
fi

if [ ! -b "$DEVICE" ];then
  error "Device $DEVICE is not a valid block device! Available devices:\n$(list_devs)"
fi

echo_white "Formatting ${DEVICE}"
sync
sudo umount -ql $(get_partition "$DEVICE" all)
sync
echo_white "Creating partition table"
sudo parted -s "$DEVICE" mklabel gpt || error "Failed to make GPT partition table on ${DEVICE}!"
sync
echo_white "Generating partitions"
sudo parted -s "$DEVICE" mkpart primary 1MB 1000MB || error "Failed to make 1GB primary partition 1 on ${DEVICE}!"
sudo parted -s "$DEVICE" set 1 msftdata on || error "Failed to enable msftdata flag on $DEVICE partition 1"
sync
if [ $CAN_INSTALL_ON_SAME_DRIVE == 1 ];then
  sudo parted -s "$DEVICE" mkpart primary 1000MB 19000MB || error "Failed to make 19GB primary partition 2 on ${DEVICE}!"
else
  sudo parted -s "$DEVICE" mkpart primary 1000MB 6000MB || error "Failed to make 6GB primary partition 2 on ${DEVICE}!"
fi
sudo parted -s "$DEVICE" set 2 msftdata on || error "Failed to enable msftdata flag on $DEVICE partition 2"
sync

echo_white "Generating filesystems"
PART1="$(get_partition "$DEVICE" 1)"
PART2="$(get_partition "$DEVICE" 2)"
echo "Partition 1: $PART1, Partition 2: $PART2"

sudo mkfs.fat -F 32 "$PART1" || error "Failed to create FAT partition on $PART1 (partition 1 of ${DEVICE})"
sudo mkfs.exfat "$PART2" || error "Failed to create EXFAT partition on $PART2 (partition 2 of ${DEVICE})"

mntpnt="/media/$USER/WOR-installer"
echo_white "Mounting ${DEVICE} device to $mntpnt"
sudo mkdir -p "$mntpnt"/bootpart || error "Failed to create mountpoint: $mntpnt/bootpart"
sudo mkdir -p "$mntpnt"/winpart || error "Failed to create mountpoint: $mntpnt/winpart"
sudo mount "$PART1" "$mntpnt"/bootpart || error "Failed to mount $PART1 to $mntpnt/bootpart"
sudo mount.exfat-fuse "$PART2" "$mntpnt"/winpart
if [ $? != 0 ];then
  echo_white "Failed to mount $PART2. Trying again after loading the 'fuse' kernel module."
  sudo modprobe fuse
  
  if [ $? != 0 ];then
    modprobe_failed=1
  else
    modprobe_failed=0
  fi
  
  sudo mount.exfat-fuse "$PART2" "$mntpnt"/winpart
  if [ $? != 0 ];then
    if [ "$modprobe_failed" == 1 ] && [ ! -d "/lib/modules/$(uname -r)" ];then
      error "The 'fuse' kernel module is required to mount $PART2 to $mntpnt/winpart, but all kernel modules are missing! Most likely, you upgraded kernel packages and have not rebooted yet. Try rebooting."
      
    else
      error "Failed to mount $PART2 to $mntpnt/winpart"
    fi
  fi
fi
#unmount on exit
trap "sudo umount -q '$PART2'" EXIT
trap "sudo umount -q '$PART1'" EXIT

echo_white "Mounting image"
mkdir -p "$(pwd)/isomount" || error "Failed to make $(pwd)/isomount folder"
sudo umount "$(pwd)/isomount" 2>/dev/null
sudo mount "$(pwd)/uupdump"/*.ISO "$(pwd)/isomount" 2>/dev/null
if [ $? != 0 ];then
  echo_white "Failed to mount the image. Trying again after loading the 'udf' kernel module."
  sudo modprobe udf
  
  if [ $? != 0 ];then
    modprobe_failed=1
  else
    modprobe_failed=0
  fi
  
  sudo mount "$(pwd)/uupdump"/*.ISO "$(pwd)/isomount"
  if [ $? != 0 ];then
    if [ "$modprobe_failed" == 1 ] && [ ! -d "/lib/modules/$(uname -r)" ];then
      error "The 'udf' kernel module is required to mount the ISO file (uupdump/$(basename $(echo "$(pwd)/uupdump"/*.ISO))), but all kernel modules are missing! Most likely, you upgraded kernel packages and have not rebooted yet. Try rebooting."
      
    else
      error "Failed to mount ISO file ($(echo "$(pwd)/uupdump"/*.ISO)) to $(pwd)/isomount"
    fi
  fi
fi
#unmount on exit
trap "sudo umount -q '$(pwd)/isomount'" EXIT

echo_white "Copying files from image to device:"
echo "  - Boot files"
sudo cp -r "$(pwd)/isomount/boot" "$mntpnt"/bootpart || error "Failed to copy $(pwd)/isomount/boot to $mntpnt/bootpart"
echo "  - EFI files"
sudo cp -r "$(pwd)/isomount/efi" "$mntpnt"/bootpart || error "Failed to copy $(pwd)/isomount/efi to $mntpnt/bootpart"
sudo mkdir -p "$mntpnt"/bootpart/sources || error "Failed to make folder: $mntpnt/bootpart/sources"
echo "  - boot.wim"
sudo cp "$(pwd)/isomount/sources/boot.wim" "$mntpnt"/bootpart/sources || error "Failed to copy $(pwd)/isomount/sources/boot.wim to $mntpnt/bootpart/sources"
echo "  - install.wim"
sudo cp "$(pwd)/isomount/sources/install.wim" "$mntpnt"/winpart || error "Failed to copy $(pwd)/isomount/sources/install.wim to $mntpnt/winpart"

echo_white "Unmounting image"
sudo umount "$(pwd)/isomount" || echo_white "Warning: failed to unmount $(pwd)/isomount" #failure is non-fatal

echo_white "Copying PE package to image"
sudo cp -r peinstaller/efi "$mntpnt"/bootpart
sudo wimupdate "$mntpnt"/bootpart/sources/boot.wim 2 --command="add peinstaller/winpe/2 /" || error "The wimupdate command failed to add peinstaller to boot.wim"

echo_white "Copying driver package to image"
sudo wimupdate "$mntpnt"/bootpart/sources/boot.wim 2 --command="add driverpackage /drivers" || error "The wimupdate command failed to add driverpackage to boot.wim"

echo_white "Copying UEFI package to image"
sudo cp uefipackage/* "$mntpnt"/bootpart 2>/dev/null # the -r flag ommitted on purpose

if [ ! -z "$CONFIG_TXT" ];then
  echo_white "Customizing the drive's config.txt according to the CONFIG_TXT variable"
  echo "$CONFIG_TXT" | sudo tee "$mntpnt"/bootpart/config.txt >/dev/null
fi

if [ $RPI_MODEL == 3 ];then
  echo_white "Applying GPT partition-table fix for the Pi3"
  sudo dd if=$(pwd)/peinstaller/pi3/gptpatch.img of="$DEVICE" conv=fsync || error "The 'dd' command failed to flash $(pwd)/peinstaller/pi3/gptpatch.img to $DEVICE"
fi

echo_white "Ejecting drive ${drive}"
sync
sudo umount "$PART1" "$PART2" || echo_white "Warning: the umount command failed to unmount all partitions within $DEVICE"
sudo eject "$DEVICE" &>/dev/null
sudo rmdir "$mntpnt"/bootpart "$mntpnt"/winpart || echo_white "Warning: Failed to remove the mountpoint folder: $mntpnt"
echo_white "$(basename "$0") script has completed."
