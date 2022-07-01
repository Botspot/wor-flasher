#!/bin/bash

#Written by Botspot
#This script is a GUI front-end for the install-wor.sh script

error() { #Input: error message
  echo -e "\\e[91m$1\\e[39m"
  zenity --error --title "$(basename "$0")" --width 360 --text "$(echo -e "An error has occurred:\n$1\nExiting now." | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*//g' | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")"
  exit 1
}

RUN_MODE=gui #this variable is detected by install-wor.sh to display gui error messages

#Determine the directory that contains this script
[ -z "$DIRECTORY" ] && DIRECTORY="$(readlink -f "$(dirname "$0")")"
[ ! -e "$DIRECTORY" ] && error "install-wor-gui.sh: Failed to determine the directory that contains this script. Try running this script with full paths."
echo "DIRECTORY: $DIRECTORY"

#Determine the directory to download windows component files to
[ -z "$DL_DIR" ] && DL_DIR="$HOME/wor-flasher-files"
echo "DL_DIR: $DL_DIR"

if [ -z "$CONFIG_TXT" ];then
  #if no user-supplied CONFIG_TXT variable, set it to initial value for yad to change later
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

#this script and cli-based install-wor.sh should be in same directory.
cli_script="$DIRECTORY/install-wor.sh"
if [ ! -f "$cli_script" ];then
  error "No script found named install-wor.sh\nBoth scripts must be in the same directory."
fi
#source the script to acquire necessary functions
source "$cli_script" source #by sourcing, this script checks for and applies updates.

#run safety checks and install packages
setup || exit 1

#this array stores flags that are used in all yad windows - saves on the typing and makes it easy to change an attribute on all dialogs from one place.
yadflags=(--center --width=310 --height=250 --window-icon="$DIRECTORY/logo.png" --title="Windows on Raspberry")

{ #choose destination RPi model and windows build ID
if [ -z "$RPI_MODEL" ] || [ -z "$UUID" ];then
  output="$(yad "${yadflags[@]}" --height=0 --form --columns=2 --separator='\n' \
    --image="$DIRECTORY/logo-full.png" \
    --text=$'<big><b>Welcome to Windows on Raspberry!</b></big>\nThis wizard will help you easily install the full desktop version of Windows on your Raspberry Pi computer.' \
    --field="Install":CB "Windows 11!Windows 10!Custom" \
    --field="on a":CB "Pi4/Pi400!Pi3/Pi2_v1.2" \
    --button='<b>Next</b>':0)"
  button=$?
  [ $button != 0 ] && error "User exited when choosing windows version and RPi model"
  
  WINDOWS_VER="$(echo "$output" | sed -n 1p)"
  RPI_MODEL="$(echo "$output" | sed -n 2p | sed 's+Pi4/Pi400+4+g' | sed 's+Pi3/Pi2_v1.2+3+g')"
  
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
  LANG_LIST="$(list_langs "$UUID")" || exit 1
  
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
    for device in $(lsblk -I 8,179,259 -dno PATH | grep -v loop | grep -vx "$ROOT_DEV") ;do
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

window_text="- Target drive: <b>$DEVICE</b> ($(lsblk -dno SIZE "$DEVICE")B $(get_name "$DEVICE"))
- $(echo "$CAN_INSTALL_ON_SAME_DRIVE" | sed 's/1/Drive is larger than 25 GB - can install Windows on itself/g' | sed 's/0/Drive is smaller than 25 GB - can install Windows on other drives/g')
- Hardware type: <b>Raspberry Pi $RPI_MODEL</b>
- Operating system: <b>$(get_os_name "$UUID" | sed "s/ build / ($WIN_LANG) arm64 build /g")</b>"

#by default, if a windows image exists, don't delete it to rebuild it
rm_img=FALSE

while true;do #repeat the Installation Overview window until Flash button clicked
  if [ -f "$DL_DIR/uupdump"/*ARM64*.ISO ];then
    existing_img_chk=(--field="A Windows image already exists. Check this box to rebuild it.":CHK "$rm_img")
  fi
  
  output="$(yad "${yadflags[@]}" --width=500 --height=400 --image="$DIRECTORY/overview.png" --image-on-top \
    --separator='\n' --form \
    --field="$window_text":LBL '' \
    "${existing_img_chk[@]}" \
    --field="<b>Edit config.txt:</b>     <small>Want to overclock? <a href="\""file://${DIRECTORY}/config_txt_tips"\"">Click here</a></small>":TXT "$CONFIG_TXT" \
    --field="<b>Warning!</b> All data on the target drive will be deleted!":LBL '' \
    --button='<b>Advanced...</b>'!!"More settings, intended for the advanced user or for troubleshooting":2 \
    --button='<b>Flash</b>'!!"Warning! All data on the target drive will be deleted! Backup any files before it's too late!":0
  )"
  button=$?
  
  #remove first line from yad output - remove newline from label field
  output="$(echo -e "$output" | tail -n +2)"
  
  #if user had the option to rebuild img file
  if [ ! -z "$existing_img_chk" ];then
    if [ "$(echo "$output" | head -n1)" == TRUE ];then
      rm_img=TRUE
    else
      rm_img=FALSE
    fi
    output="$(echo -e "$output" | tail -n +2)" #remove first line from yad output - remove newline from windows image checkbox field
  fi
  CONFIG_TXT="$output"
  
  if [ $button == 0 ];then
    #button: Flash
    break
  elif [ $button == 2 ];then
    #button: Advanced options
    
    refresh_prompt=() #this variable is populated if the Advanced Options window is repeated, to let the user know why
    
    while true;do #repeat the advanced options window until the DL_DIR is not changed, or until Cancel is clicked
      fields=()
      #make entry for peinstaller
      if [ -d "$DL_DIR/peinstaller" ];then
        fields+=("--field=Check this box to re-download PE Installer":CHK 'FALSE')
      else
        fields+=("--field=Will download PE Installer":LBL '')
      fi
      fields+=("--field=            ($DL_DIR/peinstaller)":LBL '')
      
      #make entry for driverpackage
      if [ -d "$DL_DIR/driverpackage" ];then
        fields+=("--field=Check this box to re-download RPi Drivers":CHK 'FALSE')
      else
        fields+=("--field=Will download RPi Drivers":LBL '')
      fi
      fields+=("--field=            ($DL_DIR/driverpackage)":LBL '')
      
      #make entry for uefipackage
      if [ -d "$DL_DIR/uefipackage" ];then
        fields+=("--field=Check this box to re-download UEFI package":CHK 'FALSE')
      else
        fields+=("--field=Will download UEFI package":LBL '')
      fi
      fields+=("--field=            ($DL_DIR/uefipackage)":LBL '')
      
      #make entry for windows image
      if [ -f "$DL_DIR/uupdump"/*ARM64*.ISO ];then
        fields+=("--field=Check this box to rebuild Windows image":CHK 'FALSE')
        fields+=("--field=(<small>$(echo "$DL_DIR"/uupdump/*ARM64*.ISO)</small>)":LBL '')
      else
        fields+=("--field=Will generate Windows image":LBL '')
        fields+=("--field=(<small>$DL_DIR/uupdump/#####.####_PROFESSIONAL_ARM64_XX-XX.ISO</small>)":LBL '')
      fi
      
      #make entry for dry run
      fields+=("--field=Skip flashing the device (DRY_RUN)":CHK "$(echo "$DRY_RUN" | sed 's/1/TRUE/g' | sed 's/0/FALSE/g')")
      
      output="$(yad "${yadflags[@]}" --width=550 --image-on-top \
        "${refresh_prompt[@]}" \
        --separator='\n' --form \
        --field="Working directory::DIR" "$DL_DIR" \
        "${fields[@]}" \
        --button="<b>Cancel</b>":1 --button="<b>OK</b>":0
      )"
      button=$?
      
      if [ "$button" == 0 ];then #everything in this if statement is skipped if Cancel is clicked
        if [ "$DL_DIR" != "$(echo "$output" | sed -n 1p)" ];then
          #DL_DIR was changed
          DL_DIR="$(echo "$output" | sed -n 1p)"
          echo "In the Advanced Options window, user changed DL_DIR to $DL_DIR"
          
          #explain to user why the Advanced Options window was refreshed when they clicked OK
          refresh_prompt=("--text=<b>Note:</b> As you changed the working directory, this window has refreshed."$'\n'"Any previous checkbox values have been ignored.")
          
          #skipping the 'break' command to repeat the Advanced Options window
          
        else #if DL_DIR was not changed, then review the subsequent check-box values
          #peinstaller
          if [ "$(echo "$output" | sed -n 2p)" == TRUE ];then
            echo "User checked the box to delete $DL_DIR/peinstaller"
            rm -rf "$DL_DIR/peinstaller"
          fi
          #driverpackage
          if [ "$(echo "$output" | sed -n 4p)" == TRUE ];then
            echo "User checked the box to delete $DL_DIR/driverpackage"
            rm -rf "$DL_DIR/driverpackage"
          fi
          #uefipackage
          if [ "$(echo "$output" | sed -n 6p)" == TRUE ];then
            echo "User checked the box to delete $DL_DIR/uefipackage"
            rm -rf "$DL_DIR/uefipackage"
          fi
          #windows image
          if [ "$(echo "$output" | sed -n 8p)" == TRUE ];then
            echo "User checked the box to delete $(echo "$DL_DIR"/uupdump/*ARM64*.ISO)"
            rm -f "$DL_DIR"/uupdump/*ARM64*.ISO
            rm_img=FALSE #This "Advanced..." dialog just deleted the windows image, so no need for the var to remain 'TRUE' - remove unnecessary output when removing twice
          fi
          #DRY_RUN
          if [ "$(echo "$output" | sed -n 10p)" == TRUE ] && [ "$DRY_RUN" == 0 ];then
            echo "User checked the box to set DRY_RUN=1"
            DRY_RUN=1
          elif [ "$(echo "$output" | sed -n 10p)" == FALSE ] && [ "$DRY_RUN" == 1 ];then
            echo "User checked the box to set DRY_RUN=0"
            DRY_RUN=0
          fi
          #end of parsing check-box values for advanced options window
          
          break #as the DL_DIR value was not changed, go back to the Installation Overview window
        fi
        
      else #button != 0
        break #go back to Installation Overview
      fi
    done #end of repeating the advanced options window
    
  else
    error "User exited when reviewing information and customizing config.txt"
  fi
  
done

#if user checked the box to rebuild the image, delete the image now
if [ "$rm_img" == TRUE ];then
  echo "User checked the box to delete the pre-existing windows image."
  rm -f "$DL_DIR/uupdump"/*ARM64*.ISO
fi

#display multi-line CONFIG_TXT variable
echo -e "CONFIG_TXT: ⤵\n$(echo "$CONFIG_TXT" | sed 's/^/  > /g')\nCONFIG_TXT: ⤴\n"

}

echo "Launching install-wor.sh in a separate terminal"

#run the install-wor.sh script in a terminal. If it succeeds, the terminal closes automatically. If it fails, the terminal stays open forever until you close it.
"$DIRECTORY/terminal-run" "set -a
DL_DIR="\""$DL_DIR"\""
UUID="\""$UUID"\""
WIN_LANG="\""$WIN_LANG"\""
RPI_MODEL="\""$RPI_MODEL"\""
DEVICE="\""$DEVICE"\""
CAN_INSTALL_ON_SAME_DRIVE="\""$CAN_INSTALL_ON_SAME_DRIVE"\""
CONFIG_TXT="\""$CONFIG_TXT"\""
RUN_MODE=gui
DRY_RUN="\""$DRY_RUN"\""
$cli_script
if [ "\$"? == 0 ];then
  #display 'next steps' window
  yad --center --window-icon="\""$DIRECTORY/logo.png"\"" --title='Windows on Raspberry' \
    --image="\""${DIRECTORY}/next-steps.png"\"" --button=Close:0
else
  sleep infinity
fi" "Running $(basename "$cli_script")"

echo "The terminal running install-wor.sh has been closed."











