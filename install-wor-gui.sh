#!/bin/bash

#Written by Botspot
#This script is an automation for the tutorial that can be found here: https://worproject.ml/guides/how-to-install/from-other-os

error() { #Input: error message
  echo -e "\\e[91m$1\\e[39m"
  zenity --error --title "$(basename "$0")" --width 360 --text "$(echo -e "An error has occurred:\n$1\nExiting now." | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*//g' | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")"
  exit 1
}

RUN_MODE=gui #this variable is detected by install-wor.sh to display gui error messages

#set variable for directory to download component files to
[ -z "$DL_DIR" ] && DL_DIR="$HOME/wor-flasher-files"
echo "DL_DIR: $DL_DIR"

#this script and cli-based install-wor.sh should be in same directory.
cli_script="$(dirname "$0")/install-wor.sh"
if [ ! -f "$cli_script" ];then
  error "No script found named install-wor.sh\nBoth scripts must be in the same directory."
else #install-wor.sh exists
  source "$cli_script" source
fi

yadflags=(--center --width=310 --height=250 --window-icon="$(dirname "$0")/logo.png" --title="Windows on Raspberry")

{ #choose destination RPi model and windows build ID
if [ -z "$RPI_MODEL" ] || [ -z "$UUID" ];then
  output="$(yad "${yadflags[@]}" --height=0 --form --columns=2 --separator='\n' \
    --image="$(dirname "$0")/logo-full.png" \
    --text=$'<big><b>Welcome to Windows on Raspberry!</b></big>\nThis wizard will help you easily install the full desktop version of Windows on your Raspberry Pi computer.' \
    --field="Install":CB "Windows 11!Windows 10!Custom" \
    --field="on a":CB "Pi4/Pi400!Pi3/Pi2_v1.2/CM3" \
    --button='<b>Next</b>':0)"
  button=$?
  [ $button != 0 ] && error "User exited when choosing windows version and RPi model"
  
  WINDOWS_VER="$(echo "$output" | sed -n 1p)"
  RPI_MODEL="$(echo "$output" | sed -n 2p | sed 's+Pi4/Pi400+4+g' | sed 's+Pi3/Pi2_v1.2/CM3+3+g')"
  
  if [ "$WINDOWS_VER" == 'Windows 11' ];then
    UUID="$(get_uuid 11)"
  elif [ "$WINDOWS_VER" == 'Windows 10' ];then
    UUID="$(get_uuid 10)"
  elif [ "$WINDOWS_VER" == 'Custom' ];then
    while true;do
      UUID="$(yad "${yadflags[@]}" --entry --width=400 \
        --text=$'<big><b>Custom Windows version</b></big>\nEnter a Windows build ID.\nGo to <a href="https://uupdump.net">https://uupdump.net</a> to browse windows versions.\nExample ID: db8ec987-d136-4421-afb8-2ef109396b00' \
        --button='<b>Next</b>':0)"
      button=$?
      [ $button != 0 ] && error "User exited when choosing custom windows build ID"
      
      if check_uuid "$UUID" ;then
        break
      fi
    done
  else
    error "Unrecognized user-selected WINDOWS_VER '$WINDOWS_VER'"
  fi
  
fi
echo "UUID: $UUID
RPI_MODEL: $RPI_MODEL"
}

{ #choose language
if [ -z "$WIN_LANG" ];then
  LANG_LIST="$(list_langs "$UUID")"
  
  #move 'en-*' languages to top of list
  LANG_LIST="$(echo "$LANG_LIST" | grep '^en-')
$(echo "$LANG_LIST" | grep -v '^en-')"
  
  while true; do
    WIN_LANG="$(echo "$LANG_LIST" | sed 's/^/FALSE:/g' | tr ':' '\n' | yad "${yadflags[@]}" \
      --list --radiolist --separator='\n' --column=chk:CHK --column=short --column=long --no-headers --print-column=2 --no-selection \
      --text=$'<big><b>Language</b></big>\nChoose language for Windows:' \
      --button='<b>Next</b>')"
    button=$?
    [ $button != 0 ] && error "User exited when choosing Windows language"
    
    if echo "$LANG_LIST" | grep -q "$WIN_LANG": ;then
      #if selected language matches line in language list
      break
    fi
  done
  
fi
echo "WIN_LANG: $WIN_LANG"
}

{ #choose device to flash
if [ -z "$DEVICE" ];then
  while [ -z "$DEVICE" ] || [ ! -b "$DEVICE" ];do
    IFS=$'\n'
    DEV_LIST=''
    for device in $(lsblk -I 8,179 -dno PATH | grep -v loop | grep -vx "$ROOT_DEV") ;do
      DEV_LIST="$DEV_LIST
FALSE
${device}
<b>${device}</b>
$(lsblk -dno SIZE "$device")B
$(get_name "$device")"
    done
    DEV_LIST="${DEV_LIST:1}" #remove first empty newline
    
    DEVICE="$(echo "$DEV_LIST" | yad "${yadflags[@]}" --text='Choose device to flash:' --width=420 \
      --list --radiolist --no-selection --no-headers --column=chk:CHK --column=echoname:HD --column=name --column=size --column=pretty-name \
      --print-column=2 --tooltip-column=3 --separator='\n' \
      --button="<b>Refresh</b>!!Reload the list of connected drives to detect new ones":2 --button='<b>Next</b>':0)"
    button=$?
    if [ $button == 0 ];then
      #OK
      true #do nothing and while loop will exit if $DEVICE is valid
    elif [ $button == 2 ];then
      #Refresh
      DEVICE=''
    else
      #Cancel, or unknown button
      error "User exited when selecting a device"
    fi
  done
elif [ -z "$(lsblk -no PATH "$DEVICE")" ];then
  error "Invalid value for DEVICE: $DEVICE is not a valid drive!"
fi
echo "DEVICE: $DEVICE"
}

{ #choose if device is large enough to install windows on itself
if [ "$(get_size_raw "$DEVICE")" -lt $((7*1024*1024*1024)) ];then
  #if less than 7gb
  error "Drive $DEVICE is smaller than 7GB and cannot be used."
elif [ "$(get_size_raw "$DEVICE")" -lt $((25*1024*1024*1024)) ];then
  #if less than 25gb
  echo "Drive $device is too small to install windows on itself. Using recovery-disk mode to install Windows on other larger devices."
  CAN_INSTALL_ON_SAME_DRIVE=0
else
  #larger than 25gb
  CAN_INSTALL_ON_SAME_DRIVE=1
fi
echo "CAN_INSTALL_ON_SAME_DRIVE: $CAN_INSTALL_ON_SAME_DRIVE"
}

{ #confirmation dialog and edit config.txt

window_text="<big><b>Installation Overview</b></big>

• Target drive: <b>$DEVICE</b> ($(lsblk -dno SIZE "$DEVICE")B $(get_name "$DEVICE"))
• $(echo "$CAN_INSTALL_ON_SAME_DRIVE" | sed 's/1/Drive is larger than 25 GB - can install Windows on itself/g' | sed 's/0/Drive is smaller than 25 GB - can install Windows on other drives/g')
• Hardware type: <b>Raspberry Pi $RPI_MODEL</b>
• Operating system: <b>$(get_os_name "$UUID" | sed "s/ build / ($WIN_LANG) arm64 build /g")</b>"

if [ -f "$DL_DIR/uupdump"/*ARM64*.ISO ];then
  existing_img_chk=(--field="A Windows image already exists. Check this box to rebuild it.":CHK FALSE)
fi

if [ -z "$CONFIG_TXT" ];then
  #if no user-supplied CONFIG_TXT variable, set it to initial value for yad to change below
  CONFIG_TXT="

# don't change anything below this point #
arm_64bit=1
enable_uart=1
uart_2ndstage=1
enable_gic=1
armstub=RPI_EFI.fd
disable_commandline_tags=1
disable_overscan=1
device_tree_address=0x1f0000
device_tree_end=0x200000
dtoverlay=miniuart-bt"
  
fi

CONFIG_TXT="$(yad "${yadflags[@]}" --width=530 --height=420 --image="$(dirname "$0")/logo-full.png" \
  --text="$window_text" --separator='\n' --form \
  "${existing_img_chk[@]}" \
  --field='Edit <b>config.txt</b> (for overclocking):':TXT "$CONFIG_TXT" \
  --field="<b>Warning!</b> All data on the target drive will be deleted!":LBL '' \
  --button='<b>Flash</b>'!!"Warning! All data on the target drive will be deleted! Backup any files before it's too late!":0
)"
button=$?

if [ ! -z "$existing_img_chk" ];then #if user had the option to delete/retain pre-existing img file
  
  #if user checked the box, delete the image
  if [ "$(echo "$CONFIG_TXT" | head -n1)" == TRUE ];then
    echo "User checked the box to delete the pre-existing windows image."
    rm -f "$DL_DIR/uupdump"/*ARM64*.ISO
  fi
  
  #remove first line from yad output for CONFIG_TXT
  CONFIG_TXT="$(echo -e "$CONFIG_TXT" | tail -n +2)"
fi

[ $button != 0 ] && error "User exited when choosing custom windows build ID"

#expand '\n' in yad output
CONFIG_TXT="$(echo -e "$CONFIG_TXT")"

#display multi-line CONFIG_TXT variable
echo -e "CONFIG_TXT: ⤵\n$(echo "$CONFIG_TXT" | sed 's/^/  > /g')\nCONFIG_TXT: ⤴"

}
echo "Launching install-wor.sh in a separate terminal"

"$(dirname "$0")/terminal-run" "trap 'sleep infinity' EXIT
set -a
DL_DIR="\""$DL_DIR"\""
UUID="\""$UUID"\""
WIN_LANG="\""$WIN_LANG"\""
RPI_MODEL="\""$RPI_MODEL"\""
DEVICE="\""$DEVICE"\""
CAN_INSTALL_ON_SAME_DRIVE="\""$CAN_INSTALL_ON_SAME_DRIVE"\""
CONFIG_TXT="\""$CONFIG_TXT"\""
RUN_MODE=gui
$cli_script
echo 'Close this terminal to exit.'" "Running $(basename "$cli_script")"

echo "The terminal running install-wor.sh has been closed."
