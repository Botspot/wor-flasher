#!/bin/bash

#Written by Botspot
#This script is a GUI front-end for the install-wor.sh script

error() { #Input: error message
  echo -e "\\e[91m$1\\e[39m"
  zenity --error --title "$(basename "$0")" --width 360 --text "$(echo -e "An error has occurred:\n$1\nExiting now." | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*//g' | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")"
  exit 1
}

loading_dialog() { #display a dialog to say something is loading
  (echo '# ' ; sleep infinity) | yad "${yadflags[@]}" --height=0 \
    --progress --pulsate --title="$1" --text="$1" --no-buttons &
  trap "kill $! 2>/dev/null" EXIT
  
  sleep infinity
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
dtoverlay=miniuart-bt
dtoverlay=upstream-pi4"
  
fi

if [ -z "$DRY_RUN" ];then
  DRY_RUN=0
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
yadflags=(--center --width=400 --height=250 --window-icon="$DIRECTORY/logo.png" --title="Windows on Raspberry" --separator='\n')

{ #choose destination RPi model and windows build ID
if [ -z "$RPI_MODEL" ] || [ -z "$BID" ];then
  output="$(yad "${yadflags[@]}" --height=0 --form --columns=2 \
    --image="$DIRECTORY/logo-full.png" \
    --text=$'<big><b>Welcome to Windows on Raspberry!</b></big>\nThis wizard will help you easily install the full desktop version of Windows on your Raspberry Pi computer.' \
    --field="Install":CB "Windows 11!Windows 10!More options" \
    --field="on a":CB "Pi4/Pi400!Pi3/Pi2_v1.2" \
    --button='<b>Next</b>':0)"
  button=$?
  [ $button != 0 ] && exit 0
  
  WINDOWS_VER="$(echo "$output" | sed -n 1p)"
  RPI_MODEL="$(echo "$output" | sed -n 2p | sed 's+Pi4/Pi400+4+g' | sed 's+Pi3/Pi2_v1.2+3+g')"
  
  case "$WINDOWS_VER" in
    'Windows 11' | 'Windows 10')
      loading_dialog "Finding best $WINDOWS_VER image version..." &
      loader_pid=$!
      trap "kill $loader_pid 2>/dev/null" EXIT
      
      list_bids 10 >/dev/null #set $versions globally so it is not downloaded twice
      if [ "$WINDOWS_VER" == 'Windows 11' ];then
        BID="$(get_bid 11)" || exit 1
      elif [ "$WINDOWS_VER" == 'Windows 10' ];then
        BID="$(get_bid 10)" || exit 1
      fi
      
      kill $loader_pid 2>/dev/null
      ;;
      
    'More options')
      #display more options for OS choice to user: enter exact version, use ISO, use pre-extracted ISO
      
      BID=''
      while [ -z "$BID" ];do
        reply="$(echo -e "FALSE\nChoose an exact Windows version to download\nenter exact
FALSE\nUse a Windows ISO file\nuse iso
FALSE\nUse a cached version of Windows from a previous run\nuse cached" | yad "${yadflags[@]}" --width=420 \
          --list --radiolist --column=chk:CHK --column=human --column=script:HD --no-headers --print-column=3 --no-selection \
          --text=$'<big><b>More options</b></big>' \
          --button='<b>Next</b>':0)"
        button=$?
        [ $button != 0 ] && exit 0
        
        case "$reply" in
          'enter exact')
            list_bids 10 >/dev/null #set $versions globally so it is not downloaded twice
            while [ -z "$BID" ];do
              BID="$(echo -n "$(list_bids 11 | sed 's/^/Windows 11 /g'
              list_bids 10 | sed 's/^/Windows 10 /g')" | sed 's/^/FALSE\n/g' | yad "${yadflags[@]}" --width=420 \
                --list --radiolist --column=chk:CHK --column=human --no-headers --print-column=2 --no-selection \
                --text=$'Choose version of Windows:' \
                --button='<b>Next</b>':0)"
              button=$?
              [ $button != 0 ] && exit 0
              
              #Isolate build number from selection
              BID="$(echo "$BID" | awk '{print $3}')"
            done
            break
            ;;
          'use iso')
            SOURCE_FILE="$(yad "${yadflags[@]}" --width=420 \
              --file --file-filter "ISO disk images | *.ISO *.iso" \
              --text=$'<big><b>Import ISO file</b></big>\nMust be an ARM64 version of Windows from <a href="https://uupdump.net">uupdump.net</a>' \
              --button="<b>Cancel</b>":1 --button="<b>OK</b>":0)"
            
            #verify ISO file
            if [ -z "$SOURCE_FILE" ];then
              break #exit ISO file menu 
            elif [ ! -f "$SOURCE_FILE" ];then
              yad "${yadflags[@]}" --text="This file does not exist. Check spelling and try again."
              SOURCE_FILE=''
            elif [[ "$SOURCE_FILE" != *'.ISO' ]] && [[ "$SOURCE_FILE" != *'.iso' ]];then
              yad "${yadflags[@]}" --text="This file does not have a .ISO file extension."
              SOURCE_FILE=''
            elif [ "$(du -b "$SOURCE_FILE" | awk '{print $1}')" -lt $((3*1024*1024*1024)) ];then
              yad "${yadflags[@]}" --text="This file is smaller than 3GB and is probably incomplete."
              SOURCE_FILE=''
            else #ISO file looks good
              #Infer Build ID based on filename of ISO
              BID="$(basename "$SOURCE_FILE" | tr '_ -' '\n' | grep -E -m 1 '^[0-9]{5}')"
              if [ -z "$BID" ];then
                BID="$(yad --form --field= '' "${yadflags[@]}" \
                  --text='To store files from this ISO, this script needs to know the Windows build number of this ISO.\nPlease enter it now: (example: 22621.525)' \
                  --button="<b>OK</b>":0)"
                [ -z "$BID" ] && error "Cannot proceed without a build number for your ISO file."
              fi
              #Infer language based on filename of ISO
              WIN_LANG="$(basename "$SOURCE_FILE" | tr '_ ' '\n' | grep -io -m 1 "$(list_langs | awk -F: '{print $1}' | tr '\n' ';' | sed 's/;/\\|/g' | sed 's/\\|$/\n/g')" | tr '[A-Z]' '[a-z]')"
              if [ -z "$WIN_LANG" ];then
                WIN_LANG="$(yad --form --field= '' "${yadflags[@]}" \
                  --text='To store files from this ISO, this script needs to know the language of this Windows ISO.\nPlease enter it now: (example: en-us)' \
                  --button="<b>OK</b>":0)"
                if [ -z "$WIN_LANG" ];then
                  error "Cannot proceed without a language for your ISO file."
                elif ! list_langs | awk -F: '{print $1}' | grep -q "$WIN_LANG" ;then
                  error "Language code was not found in the list!\n$(list_langs | awk '{print $1}' | tr '\n' ' ')"
                fi
              fi
              break
            fi
            ;;
          'use cached')
            #Discover past extracted ISO files in this DL_DIR so user does not need to keep ISO
            #folders in DL_DIR named winfiles_from_iso_<BID>_<WIN_LANG>
            while true;do 
              list=''
              existing_winfiles="$(find "$DL_DIR" -maxdepth 2 -type f -name 'alldone' | grep -o "/winfiles_from_iso.*/\|/winfiles.*/" | tr -d / | sort -r -n)"
              
              echo "$existing_winfiles"
              
              for folder in $existing_winfiles ;do
                BID="$(echo "$folder" | sed 's/^winfiles_from_iso_//g' | sed 's/^winfiles_//g' | awk -F_ '{print $1}')"
                WIN_LANG="$(echo "$folder" | sed 's/^winfiles_from_iso_//g' | sed 's/^winfiles_//g' | awk -F_ '{print $2}')"
                
                list+="FALSE\n$(get_os_name "$BID") $WIN_LANG\n${folder}\n"
                num_opts=$((num_opts+1))
              done
              unset BID WIN_LANG #Avoid leaving these variables set from the loop
              
              folder="$(echo -ne "$list" | yad "${yadflags[@]}" --height=320 \
                --list --radiolist --column=chk:CHK --column=human --column=script:HD --no-headers --print-column=3 --no-selection \
                --text=$'<big><b>Choose cached version</b></big>\nIf the list is empty, please use the same working directory (DL_DIR) you used last time.\nDL_DIR: <b><u>'"$DL_DIR"'</u></b>' \
                --button='<b>Change DL<u>  </u>DIR</b>':2 \
                --button='<b>Next</b>':0)"
              button=$?
              
              case $button in
                0) #Next
                  if [ ! -z "$folder" ];then
                    #A cached version of windows (winfiles folder) was selected; infer BID and WIN_LANG from it
                    BID="$(echo "$folder" | sed 's/^winfiles_from_iso_//g' | sed 's/^winfiles_//g' | awk -F_ '{print $1}')"
                    WIN_LANG="$(echo "$folder" | sed 's/^winfiles_from_iso_//g' | sed 's/^winfiles_//g' | awk -F_ '{print $2}')"
                    
                    #DL_DIR cannot be changed later on - it is being relied upon for winfiles
                    break
                  else
                    #nothing selected; present the window again
                    true
                  fi
                  ;;
                2) #change DL_DIR
                  DL_DIR="$(yad "${yadflags[@]}" --file --directory --mime-filter="Directories | inode/directory" \
                    --width=500 --height=400 --title="Choose DL_DIR" \
                    --text=$'Choose directory for everything to be downloaded.\nIn this case you should select the directory where everything <i>was</i> downloaded the last time you ran WoR-Flasher.' \
                    --button="<b>Cancel</b>":1 --button="<b>OK</b>":0 \
                    || echo "$DL_DIR")"
                    #This ^^^^^^^^^^^ preserves the current value of DL_DIR if anything other than OK is clicked
                  ;;
                *)
                  exit 0 #user wishes to exit the list of previously extracted winfiles
                  ;;
              esac
            done
            ;;
        esac
      done
      ;;
    *)
      error "Unrecognized user-selected WINDOWS_VER '$WINDOWS_VER'"
      ;;
  esac
fi
echo "BID: $BID
RPI_MODEL: $RPI_MODEL"
}

{ #choose language
if [ -z "$WIN_LANG" ];then
  
  #move 'en-*' languages to top of list, and of those put en-us at the very top and make it preselected
  LANG_LIST="$(list_langs | grep '^en-us'
list_langs | grep '^en-*' | grep -v '^en-us'
list_langs | grep -v '^en-')"
  
  while true; do
    WIN_LANG="$(echo "$LANG_LIST" | sed 's/^/FALSE:/g' | tr ':' '\n' | sed -e '0,/FALSE/ s/FALSE/TRUE/' | yad "${yadflags[@]}" \
      --list --radiolist --column=chk:CHK --column=short --column=long --no-headers --print-column=2 --no-selection \
      --text=$'<big><b>Language</b></big>\nChoose language for Windows:' \
      --button='<b>Next</b>':0)"
    button=$?
    [ $button != 0 ] && exit 1
    
    if echo "$LANG_LIST" | grep -q "^$WIN_LANG": ;then
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
      DEV_LIST="FALSE
${device}
<b>${device}</b>
$(lsblk -dno SIZE "$device")B
$(get_device_name "$device")
$DEV_LIST"
    done
    
    DEVICE="$(echo -n "$DEV_LIST" | sed -e '0,/FALSE/ s/FALSE/TRUE/' | yad "${yadflags[@]}" --text='Choose device to flash:' --width=420 \
      --list --radiolist --no-selection --no-headers --column=chk:CHK --column=echoname:HD --column=name --column=size --column=pretty-name \
      --print-column=2 --tooltip-column=3 \
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
      exit 1
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

window_text="- Target drive: <b>$DEVICE</b> ($(lsblk -dno SIZE "$DEVICE" | tr -d ' ')B $(get_device_name "$DEVICE"))
- $(echo "$CAN_INSTALL_ON_SAME_DRIVE" | sed 's/1/Drive is larger than 25 GB - can install Windows on itself/g' | sed 's/0/Drive is smaller than 25 GB - can install Windows on other drives/g')
- Target hardware: <b>Raspberry Pi $RPI_MODEL</b>
- Operating system: <b>$(get_os_name "$BID" | sed "s/ build / ($WIN_LANG) arm64 build /g")</b>"

#by default, if a windows image exists, don't delete it to rebuild it
rm_img=FALSE

while true;do #repeat the Installation Overview window until Flash button clicked
  
  if [ "$DRY_RUN" == 1 ];then
    deletion_warning="DRY_RUN=1, so the target drive will not be modified."
    deletion_warning_2="$deletion_warning"
  else
    deletion_warning="<b>Warning!</b> All data on the target drive will be deleted!"
    deletion_warning_2="$deletion_warning Backup any files before it's too late!"
  fi
  
  output="$(yad "${yadflags[@]}" --width=500 --height=400 --image="$DIRECTORY/overview.png" --image-on-top \
    --form --field="$window_text":LBL '' \
    "${existing_img_chk[@]}" \
    --field="<b>Edit config.txt:</b>     <small>Want to overclock? <a href="\""file://${DIRECTORY}/config_txt_tips"\"">Click here</a></small>":TXT "$CONFIG_TXT" \
    --field="$deletion_warning":LBL '' \
    --button='<b>Advanced...</b>'!!"More settings, intended for the advanced user or for troubleshooting":2 \
    --button='<b>Flash</b>'!!"$deletion_warning_2":0
  )"
  button=$?
  
  #remove first line from yad output - remove newline from label field
  output="$(echo -e "$output" | tail -n +2)"
  
  CONFIG_TXT="$output"
  
  if [ $button == 0 ];then
    #button: Flash
    break
  elif [ $button == 2 ];then
    #button: Advanced options
    
    refresh_prompt=() #this variable is populated if the Advanced Options window is repeated, to let the user know why
    
    while true;do #repeat the advanced options window until the DL_DIR is not changed, or until Cancel is clicked
      fields=()
      #make entry to change DL_DIR
      if [ -f "${DL_DIR}/winfiles_from_iso_${BID}_${WIN_LANG}/alldone" ];then
        #lock DL_DIR if winfiles come from previously extracted ISO - changing it would lose these files and they cannot be replaced by the internet
        fields+=("--field=Working directory: (DL<u>  </u>DIR):RO" 'Cannot be changed')
      else
        fields+=("--field=Working directory: (DL<u>  </u>DIR):DIR" "$DL_DIR")
      fi
      
      #make entry for peinstaller
      if [ -d "$DL_DIR/peinstaller" ];then
        fields+=("--field=Check this box to re-download PE Installer":CHK 'FALSE')
      else
        fields+=("--field=Will download PE Installer":LBL '')
      fi
      fields+=("--field=            <u>$DL_DIR/peinstaller</u>":LBL '')
      
      #make entry for driverpackage
      if [ -d "$DL_DIR/driverpackage" ];then
        fields+=("--field=Check this box to re-download RPi Drivers":CHK 'FALSE')
      else
        fields+=("--field=Will download RPi Drivers":LBL '')
      fi
      fields+=("--field=            <u>$DL_DIR/driverpackage</u>":LBL '')
      
      #make entry for uefipackage
      if [ -d "$DL_DIR/pi${RPI_MODEL}-uefipackage" ];then
        fields+=("--field=Check this box to re-download UEFI package":CHK 'FALSE')
      else
        fields+=("--field=Will download UEFI package":LBL '')
      fi
      fields+=("--field=            <u>$DL_DIR/pi${RPI_MODEL}-uefipackage</u>":LBL '')
      
      #display status of winfiles - if they will be downloaded or are ready to use
      if [ -f "${DL_DIR}/winfiles_${BID}_${WIN_LANG}/alldone" ];then
        #already extracted
        fields+=("--field=Windows files: Already extracted and ready to use.":LBL '')
        fields+=("--field=            <small><u>${DL_DIR}/winfiles_${BID}_${WIN_LANG}</u></small>":LBL '')
      elif [ -f "${DL_DIR}/winfiles_from_iso_${BID}_${WIN_LANG}/alldone" ];then
        #already extracted
        fields+=("--field=Windows files: Already extracted and ready to use.":LBL '')
        fields+=("--field=            <small><u>${DL_DIR}/winfiles_from_iso_${BID}_${WIN_LANG}</u></small>":LBL '')
      elif [ ! -z "$SOURCE_FILE" ];then
        #will use ISO file
        fields+=("--field=Windows files: Will be extracted from your ISO file.":LBL '')
        fields+=("--field=            <small><u>${SOURCE_FILE}</u></small>":LBL '')
      else
        #ESD will be downloaded
        fields+=("--field=Windows files: Will download and extract Windows ESD image":LBL '')
        fields+=("--field=            <small><u>${DL_DIR}/winfiles_${BID}_${WIN_LANG}</u></small>":LBL '')
      fi
      
      #make entry for dry run
      fields+=("--field=Skip flashing the device (DRY_RUN)":CHK "$(echo "$DRY_RUN" | sed 's/1/TRUE/g' | sed 's/0/FALSE/g')")
      
      output="$(yad "${yadflags[@]}" --width=500 --height=400 --image-on-top \
        "${refresh_prompt[@]}" \
        --form \
        "${fields[@]}" \
        --button="<b>Cancel</b>":1 --button="<b>OK</b>":0
      )"
      button=$?
      
      if [ "$button" == 0 ];then #everything in this if statement is skipped if Cancel is clicked
        if [ ! -f "${DL_DIR}/winfiles_from_iso_${BID}_${WIN_LANG}/alldone" ] && [ "$DL_DIR" != "$(echo "$output" | sed -n 1p)" ];then
          #DL_DIR was changed - only honor the value if it is allowed to be changed
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
            echo "User checked the box to delete $DL_DIR/pi${RPI_MODEL}-uefipackage"
            rm -rf "$DL_DIR/pi${RPI_MODEL}-uefipackage"
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
        
      else #button != OK
        break #Don't save and go back to Installation Overview
      fi
    done #end of repeating the advanced options window
    
  else
    #User exited when reviewing information and customizing config.txt
    exit 1
  fi
  
done #end of repeating the Installation Overview window

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
BID="\""$BID"\""
WIN_LANG="\""$WIN_LANG"\""
RPI_MODEL="\""$RPI_MODEL"\""
DEVICE="\""$DEVICE"\""
CAN_INSTALL_ON_SAME_DRIVE="\""$CAN_INSTALL_ON_SAME_DRIVE"\""
CONFIG_TXT="\""$CONFIG_TXT"\""
RUN_MODE=gui
DRY_RUN="\""$DRY_RUN"\""
SOURCE_FILE="\""$SOURCE_FILE"\""
$cli_script
if [ "\$"? == 0 ];then
  #display 'next steps' window
  yad --center --window-icon="\""$DIRECTORY/logo.png"\"" --title='Windows on Raspberry' \
    --image="\""${DIRECTORY}/next-steps.png"\"" --button=Close:0
else
  sleep infinity
fi" "Running $(basename "$cli_script")"

echo "The terminal running install-wor.sh has been closed."











