#!/bin/bash

#Written by Botspot
#This script is an automation for the tutorial that can be found here: https://worproject.com/guides/how-to-install/from-other-os

error() { #Input: error message
  echo -e "\e[91m$1\e[0m" 1>&2
  [ "$RUN_MODE" == gui ] && zenity --error --title "$(basename "$0")" --width 360 --text "$(echo -e "An error has occurred:\n$1\nExiting now." | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*//g' | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")"
  exit 1
}

status() { #blue text to indicate what is happening
  
  #detect if a flag was passed, and if so, pass it on to the echo command
  if [[ "$1" == '-'* ]] && [ ! -z "$2" ];then
    echo -e $1 "\e[96m$2\e[0m" 1>&2
  else
    echo -e "\e[96m$1\e[0m" 1>&2
  fi
}

echo_green() { #announce the success of a major action
  echo -e "\e[92m$1\e[0m" 1>&2
}

echo_red() { #announce the failure of a nonfatal action
  echo -e "\e[91m$1\e[0m" 1>&2
}

wget() { #wrapper function for the wget command for better reliability
  command wget --no-check-certificate -4 "$@"
}

wget() { #Intercept all wget commands. When possible, uses aria2c.
  local file=''
  local url=''
  #determine the download manager to use
  local use=aria2c
  #determine if being run silently (if the '-q' flag was passed)
  local quiet=0
  
  #use these flags for aria2c
  aria2_flags=(-x 16 -s 16 --max-tries=10 --retry-wait=30 --max-file-not-found=5 --http-no-cache=true --check-certificate=false \
    --allow-overwrite=true --auto-file-renaming=false --remove-control-file --auto-save-interval=0 \
    --console-log-level=error --show-console-readout=false --summary-interval=1)
  
  #convert wget arguments to newline-separated list
  local IFS=$'\n'
  local opts="$(IFS=$'\n'; echo "$*")"
  for opt in $opts ;do
    
    #check if this argument to wget begins with '--'
    if [[ "$opt" == '--'* ]];then
      if [ "$opt" == '--quiet' ];then
        quiet=1
      elif [[ "$opt" == '--load-cookies='* ]];then
        aria2_flags+=("$opt")
      else #for any other arguments, fallback to wget
        use=wget
      fi
      
    elif [ "$opt" == '-' ];then
      #writing to stdout, use wget and hide output
      use=wget
      quiet=1
    elif [[ "$opt" == '-'* ]];then
      #this opt is a flag beginning with one '-'
      
      #check the value of every letter in this argument
      local i
      for i in $(fold -w1 <<<"$opt" | tail -n +2) ;do
        
        if [ "$i" == q ];then
          quiet=1
        elif [ "$i" == O ];then
          true
        elif [ "$i" == '-' ];then
          #writing to stdout, use wget and hide output
          use=wget
          quiet=1
        else #any other wget arguments
          use=wget
        fi
      done
      
    elif [[ "$opt" == *'://'* ]]; then
      #this opt is web address
      url="$opt"
    elif [[ "$opt" == '/'* ]]; then
      #this opt is file output
      if [ -z "$file" ];then
        file="$opt"
        #if output file is /dev/stdout, /dev/null, etc, use wget
        if [[ "$file" == /dev/* ]];then
          use=wget
          quiet=1
        fi
      else #file var already populated
        use=wget
      fi
    else
      #This argument does not begin with '-', contain '://', or begin with '/'.
      #Assume output file specified shorthand if file-argument is not already set
      if [ -z "$file" ];then
        file="$(pwd)/${opt}"
      else #file var already populated
        use=wget
      fi
    fi
  done
  
  if ! command -v aria2c >/dev/null ;then
    #aria2c command not found
    use=wget
  fi
  
  #now, perform the download using the chosen method
  if [ "$use" == wget ];then
    #run the true wget binary with all this function's args
    
    command wget --progress=bar:force:noscroll "$@"
    local exitcode=$?
  elif [ "$use" == aria2c ];then
    
    #if $file empty, generate it based on url
    if [ -z "$file" ];then
      file="$(pwd)/$(basename "$url")"
    fi
    
    aria2_flags+=("$url" -d "$(dirname "${file}")" -o "$(basename "${file}")")
    
    #suppress output if -q flag passed
    if [ "$quiet" == 1 ];then
      aria2c --quiet "${aria2_flags[@]}"
      local exitcode=$?
      
    else #run aria2c without quietness and format download-progress output
      local terminal_width="$(tput cols || echo 80)"
      
      #run aria2c and reduce its output.
      aria2c "${aria2_flags[@]}" | while read -r line ;do
        
        #filter out unnecessary lines
        line="$(grep --line-buffered -v '\-\-\-\-\-\-\-\-\|======\|^FILE:\|^$\|Summary\|Results:\|download completed\.\|^Status Legend:\||OK\||stat' <<<"$line" || :)"
        
        if [ ! -z "$line" ];then #if this line still contains something and was not erased by grep
          
          #check if this line is a progress-stat line, like: "[#a6567f 20MiB/1.1GiB(1%) CN:16 DL:14MiB ETA:1m19s]"
          if [[ "$line" == '['*']' ]];then
            
            #hide cursor
            printf "\033[?25l"
            
            #print the total data only, like: "0.9GiB/1.1GiB"
            statsline="$(echo "$line" | awk '{print $2}' | sed 's/(.*//g' | tr -d '\n') "
            #get the length of statsline
            characters_subtract=${#statsline}
            
            #determine how many characters are available for the progress bar
            available_width=$(($terminal_width - $characters_subtract))
            #make sure available_width is a positove number (in case bash-variable COLUMNS is empty)
            [ "$available_width" -le 0 ] && available_width=20
            
            #get progress percentage from aria2c output
            percent="$(grep -o '(.*)' <<<"$line" | tr -d '()%')"
            
            #echo "percent: $percent"
            #echo "available_width: $available_width"
            
            #determine how many characters in progress bar to light up
            progress_characters=$(((percent*available_width)/100))
            
            statsline+="\e[92m\e[1m$(for ((i=0; i<$progress_characters; i++)); do printf "—"; done)\e[39m" # other possible characters to put here: █🭸
            echo -ne "\e[0K${statsline}\r\033\e[0m" 1>&2 #clear and print over previous line
            
            #reduce the line and print over the previous line, like: "1.1GiB/1.1GiB(98%) DL:18MiB"
            #echo "$line" | awk '{print $2 " " $4 " " substr($5, 1, length($5)-1)}' | tr -d '\n'
            
          else
            #this line is not a progress-stat line; don't format output
            echo "$line"
          fi
        fi
        
      done
      local exitcode=${PIPESTATUS[0]}
    fi
  fi
  
  #display a "download complete" message
  if [ $exitcode == 0 ] && [ "$quiet" == 0 ];then
    
    #show cursor
    printf "\033[?25h"
    
    #display "done" message
    if [ "$use" == aria2c ];then
      local progress_characters=$(($terminal_width - 5))
      echo -e "\e[0KDone \e[92m\e[1m$(for ((i=0; i<$progress_characters; i++)); do printf "—"; done)\e[39m\e[0m" 1>&2 #clear and print over previous line
    else
      echo
      echo_green "Done" 1>&2
    fi
  elif [ $exitcode != 0 ] && [ "$quiet" == 0 ];then
    #show cursor
    printf "\033[?25h"
    
    echo -e "\n\e[91mFailed to download: $url\nPlease review errors above.\e[0m" 1>&2
  fi
  
  return $exitcode
}

cache_downloader() { #returns contents of url, using cached output from a previous run if necessary
  [ -z "$1" ] && error "cache_downloader(): no url specified!"
  [ -z "$DIRECTORY" ] && error "cache_downloader(): DIRECTORY variable not set!"
  local output
  output="$(wget -qO- "$1")"
  
  if [ -z "$output" ];then
    output="$(cat "$DIRECTORY/cache/$(basename "$1")" 2>/dev/null)" || error "Unable to download $1"
  else
    echo "$output" > "$DIRECTORY/cache/$(basename "$1")"
  fi
  echo "$output"
}

download_from_gdrive() { #Input: file UUID and filename
  [ -z "$1" ] && error "download_from_gdrive(): requires a Google Drive file UUID!\nFile UUID is the end of a sharable link: https://drive.google.com/uc?export=download&id=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  [ -z "$2" ] && error "download_from_gdrive(): requires specifying a filename to save to."
  
  local FILEUUID="$1"
  local FILENAME="$2"
  
  #this seems broken
  #wget --load-cookies=/tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies 'https://docs.google.com/uc?export=download&id='"$FILEUUID" -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=$FILEUUID" -O "$2" && rm -rf /tmp/cookies.txt
  
  #but now this works
  wget "https://drive.usercontent.google.com/download?id=$FILEUUID&confirm=t" -O "$2"
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
    status "Installing packages: $install_list"
    sudo apt update || error "Failed to run 'sudo apt update'! This is not an error in WoR-flasher."
    sudo apt install -yf $install_list --no-install-recommends || error "Failed to install dependency packages! This is not an error in WoR-flasher."
  fi
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

get_device_name() { #get human-readable name of storage device: manufacturer and model name
  #Botspot made this by reverse-engineering the usb-devices command and udevadm commands.
  #input: /dev device
  [ -z "$1" ] && error "get_device_name(): requires an argument"
  [ ! -b "$1" ] && error "get_device_name(): Specified block device '$1' does not exist!"
  
  sys_path="$(find /sys/devices/platform -type d -name "$(basename "$1")")"
  #sys_path may be: /sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-2/2-2:1.0/host0/target0:0:0/0:0:0:0/block/sda
  
  if [ -z "$sys_path" ];then
    echo "get_device_name(): Failed to find a /sys/devices/platform entry for '$1'. Continuing." 1>&2
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

list_devs() { #Output: human-readable, colorized list of valid block devices to write to. Omits /dev/loop* and the root device. Returns code 1 if no drives found
  local IFS=$'\n'
  local exitcode=1
  for device in $(lsblk -I 8,179,259 -dno NAME | sed 's+^+/dev/+g' | grep -v loop | grep -vx "$ROOT_DEV") ;do
    if [ $(lsblk -dnbo SIZE "$device") -gt 0 ];then
      echo -e "\e[1m\e[97m${device}\e[0m - \e[92m$(lsblk -dno SIZE "$device")B\e[0m - \e[36m$(get_device_name "$device")\e[0m"
      exitcode=0
    fi
  done
  return $exitcode 
}

list_langs() { #Output: colon-delimited list of languages. Format is <lang-code>:<lang-name>
  #echo "$catalog" | sed 's/></>\n</g' | sed -n '/<Languages>/q;p' | grep '<LanguageCode>\|<Language>' | tr -d '\n' | sed 's/<\/Language><LanguageCode>/\n/g' | sed 's/<\/LanguageCode><Language>/:/g' | sed 's/^<LanguageCode>//g' | sed 's/<\/Language>$/\n/g' | sed 's/&#xE5;/å/g' | sort
  
  echo -e "ar-sa:Arabic (Saudi Arabia)\nbg-bg:Bulgarian (Bulgaria)\ncs-cz:Czech (Czechia)\nda-dk:Danish (Denmark)\nde-de:German (Germany)\nel-gr:Greek (Greece)\nen-gb:English (United Kingdom)\nen-us:English (United States)\nes-es:Spanish (Spain, International Sort)
es-mx:Spanish (Mexico)\net-ee:Estonian (Estonia)\nfi-fi:Finnish (Finland)\nfr-ca:French (Canada)\nfr-fr:French (France)\nhe-il:Hebrew (Israel)\nhr-hr:Croatian (Croatia)\nhu-hu:Hungarian (Hungary)\nit-it:Italian (Italy)\nja-jp:Japanese (Japan)\nko-kr:Korean (Korea)
lt-lt:Lithuanian (Lithuania)\nlv-lv:Latvian (Latvia)\nnb-no:Norwegian Bokmål (Norway)\nnl-nl:Dutch (Netherlands)\npl-pl:Polish (Poland)\npt-br:Portuguese (Brazil)\npt-pt:Portuguese (Portugal)\nro-ro:Romanian (Romania)\nru-ru:Russian (Russia)\nsk-sk:Slovak (Slovakia)
sl-si:Slovenian (Slovenia)\nsr-latn-rs:Serbian (Latin, Serbia)\nsv-se:Swedish (Sweden)\nth-th:Thai (Thailand)\ntr-tr:Turkish (Turkey)\nuk-ua:Ukrainian (Ukraine)\nzh-cn:Chinese (Simplified, China)\nzh-tw:Chinese (Traditional, Taiwan)"
}

list_bids() { #input: '10' or '11', Output: build IDs for ESD releases. Format: "$BID ($date)"
  if [ -z "$versions" ];then
    #Get list of major Windows ESD versions from worproject.com
    versions="$(cache_downloader 'https://worproject.com/dldserv/esd/getversions.php')" || return 1
    #format variable
    versions="$(echo "$versions" | sed 's/<release /\n<release /g' | sed 's+</release></releases>+\n</release></releases>+g')"
  fi
  
  if [ "$1" == 11 ];then
    #List Windows 11 versions
    echo "$versions" | sed -n '/version number="11"/,/version number="10"/p' | grep 'release build' | sed 's/^<release build="//g' | sed 's/"><date>/ (/g' | sed 's/<\/date>.*/)/g' | sed 's/.....$/-&/' | sed 's/...$/-&/'
  elif [ "$1" == 10 ];then
    #List Windows 10 versions
    echo "$versions" | sed -n '/version number="10"/,/release build="17134.112"/p' | grep 'release build' | sed 's/^<release build="//g' | sed 's/"><date>/ (/g' | sed 's/<\/date>.*/)/g' | sed 's/.....$/-&/' | sed 's/...$/-&/'
  else
    error "list_bids(): unrecognized OS version. Expected '10' or '11'."
  fi
}

get_bid() { #input: '10' or '11', Output: latest build ID
  if [ "$1" == 11 ];then
    list_bids 11 | awk '{print $1}' | head -n1
  elif [ "$1" == 10 ];then
    list_bids 10 | awk '{print $1}' | head -n1
  else
    error "get_bid(): unrecognized OS version. Expected '10' or '11'."
  fi
}

get_os_name() { #input: build id, Output: either "Windows 10 build $BID" or "Windows 11 build $BID"
  local BID="$1"
  if [ "$(echo "$BID" | awk -F. '{print $1}')" -ge 22000 ];then
    echo "Windows 11 build $BID"
  elif [ "$(echo "$BID" | awk -F. '{print $1}')" -lt 22000 ];then
    echo "Windows 10 build $BID"
  fi
}

setup() { #run safety checks and install packages
  #check for internet connection
  echo -n "Checking for internet connection... "
  local errors
  errors="$(command wget --spider github.com 2>&1)"
  if [ $? != 0 ];then
    error "No internet connection!\ngithub.com failed to respond.\nErrors: $errors"
  fi
  echo Done
  
  if [ "$(id -u)" == 0 ];then
    status "WoR-Flasher is not designed to be run as root.\nDoing so is known to cause problems."
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
  
  #Make sure modules exist for the running kernel - otherwise a kernel upgrade occurred and the user needs to reboot. See https://github.com/Botspot/wor-flasher/issues/35
  if [ ! -d /lib/modules/$(uname -r) ];then
    error "The running kernel ($(uname -r)) does not match any directory in /lib/modules.
Usually this means you have not yet rebooted since upgrading the kernel.
Try rebooting.
If this error persists, contact Botspot - the WoR-flasher developer."
  fi
  
  #install dependencies
  install_packages 'yad aria2 cabextract wimtools chntpw genisoimage exfat-fuse wget udftools bc' || exit 1
  
  #install exfat partition manipulation utility. exfatprogs replaces exfat-utils, but they cannot both be installed at once.
  if package_available exfatprogs && ! package_installed exfat-utils ;then
    install_packages exfatprogs || exit 1
  else
    install_packages exfat-utils || exit 1
  fi
}

#
######## END OF FUNCTIONS, BEGINNING OF SCRIPT
#

#Determine the directory to download windows component files to
[ -z "$DL_DIR" ] && DL_DIR="$HOME/wor-flasher-files"

#Determine the directory that contains this script
[ -z "$DIRECTORY" ] && DIRECTORY="$(readlink -f "$(dirname "$0")")"

#clear the variable storing path to this script, if the folder does not contain a file named 'install-wor.sh'
[ ! -f "${DIRECTORY}/install-wor.sh" ] && DIRECTORY=''

#Determine what /dev/ block-device is the system's rootfs device. This drive is exempted from the list of available flashing options.
ROOT_DEV="/dev/$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")"
IFS=$'\n'

{ #check for updates and auto-update if the no-update files does not exist
if [ -e "$DIRECTORY" ] && [ ! -f "${DIRECTORY}/no-update" ];then
  prepwd="$PWD"
  cd "$DIRECTORY"
  localhash="$(git rev-parse HEAD)"
  latesthash="$(git ls-remote https://github.com/Botspot/wor-flasher HEAD | awk '{print $1}')"
  
  if [ "$localhash" != "$latesthash" ] && [ ! -z "$latesthash" ] && [ ! -z "$localhash" ];then
    status "Auto-updating wor-flasher for the latest features and improvements..."
    status "To disable this next time, create a file at ${DIRECTORY}/no-update"
    sleep 1
    git pull | cat #piping through cat makes git noninteractive
    
    status "git pull finished. Reloading script..."
    set -a #export all variables so the script can see them
    #run updated script
    "$0" "$@"
    exit $?
  fi
  cd "$prepwd"
fi
}

mkdir -p "${DIRECTORY}/cache"

[ "$1" == 'source' ] && return 0 #If being sourced, exit here at this point in the script
#past this point, this script is being run, not sourced.

#Ensure this script's parent directory is valid
[ ! -e "$DIRECTORY" ] && error "$(basename "$0"): Failed to determine the directory that contains this script. Try running this script with full paths."

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
using_esd=true #indicate that ESD download is required - will be changed to false otherwise
if [ -f "${DL_DIR}/winfiles_from_iso_${BID}_${WIN_LANG}/alldone" ];then
  #If pre-provided DL_DIR, BID and WIN_LANG show that a previously extracted ISO will be used, don't use ESD
  using_esd=false
fi

if [ -z "$BID" ];then
  
  while [ -z "$BID" ];do
    echo -ne "\nChoose Windows version:
\e[96m1\e[0m) Windows 11
\e[96m2\e[0m) Windows 10
\e[96m3\e[0m) More options...
Enter \e[96m1\e[0m, \e[96m2\e[0m or \e[96m3\e[0m: "
    read reply
    
    case $reply in
      1 | 2)
        #latest Windows 10/11 chosen
        echo -e "\nFinding newest build..."
        
        if [ "$reply" == 1 ];then
          #Windows 11
          BID="$(get_bid 11)" || exit 1
        elif [ "$reply" == 2 ];then
          #Windows 10
          BID="$(get_bid 10)" || exit 1
        fi
        ;;
      3)
        #more options
        while true;do
          
          #Discover past extracted ISO files so user does not need to keep ISO
          num_opts=3 #default number of options already in the "Additional options" menu
          add_options='' #Store additional options to display to the user
          available_extracted_isos="$(find "$PWD" -maxdepth 2 -type f -name 'alldone' | grep -o "/winfiles_from_iso.*/" | sed 's+/$++' | sed 's+/winfiles_from_iso_++g' | sort)"
          
          for folder in $available_extracted_isos ;do
            BID="$(echo "$folder" | awk -F_ '{print $1}')"
            WIN_LANG="$(echo "$folder" | awk -F_ '{print $2}')"
            add_options+="\n\e[96m${num_opts}\e[0m) Use $(get_os_name "$BID") $WIN_LANG (extracted from your ISO last time)"
            num_opts=$((num_opts+1))
          done
          unset BID WIN_LANG #Avoid leaving these variables set from the loop
          
          echo -ne "\nAdditional options:
\e[96m1\e[0m) Enter an exact Windows version to download
\e[96m2\e[0m) Use a Windows ISO file${add_options}
\e[96m$num_opts\e[0m) Go back
$([ $num_opts == 3 ] && echo 'Enter \e[96m1\e[0m, \e[96m2\e[0m or \e[96m3\e[0m: ' || echo 'Enter a number: ')"
          read reply
          
          case $reply in
            1) #Enter an exact Windows version to download
              echo -e "\nFinding builds..."
              
              #versions=''
              list_bids 10 >/dev/null #set $versions globally so it is not downloaded twice
              list_bids 11 | sed 's/ /'$(echo -e '\e[0m')' /g' | sed 's/^/Windows 11 '$(echo -e '\e[96m')'/g'
              list_bids 10 | sed 's/ /'$(echo -e '\e[0m')' /g' | sed 's/^/Windows 10 '$(echo -e '\e[96m')'/g'
              
              read -p $'\nFrom the list above, enter a Windows version number: ' BID
              if (list_bids 11 ; list_bids 10) | awk '{print $1}' | grep -qFx "$BID" ;then
                break #exit the while loop
              else
                echo_red "Invalid answer. Expected to see something like '22621.525'. Try again."
              fi
              ;;
              
            2) #Use a Windows ISO file
              while [ -z "$SOURCE_FILE" ];do
                read -p $'\nEnter the full path to a Windows 10/11 ARM64 ISO file: ' SOURCE_FILE
                if [ -z "$SOURCE_FILE" ];then
                  break #exit ISO file menu 
                elif [ ! -f "$SOURCE_FILE" ];then
                  echo_red "This file does not exist. Check spelling and try again."
                  SOURCE_FILE=''
                elif [[ "$SOURCE_FILE" != *'.ISO' ]] && [[ "$SOURCE_FILE" != *'.iso' ]];then
                  echo_red "This file does not have a .ISO file extension."
                  SOURCE_FILE=''
                elif [ "$(du -b "$SOURCE_FILE" | awk '{print $1}')" -lt $((3*1024*1024*1024)) ];then
                  echo_red "This file is smaller than 3GB and is probably incomplete."
                  SOURCE_FILE=''
                else #ISO file looks good
                  #Infer Build ID based on filename of ISO
                  BID="$(basename "$SOURCE_FILE" | tr '_ -' '\n' | grep -E -m 1 '^[0-9]{5}')"
                  if [ -z "$BID" ];then
                    read -p $'\nTo store files from this ISO, this script needs to know the Windows build number of this ISO.\nPlease enter it now: (example: 22621.525) ' BID
                    [ -z "$BID" ] && error "Cannot proceed without a build number for your ISO file."
                  fi
                  #Infer language based on filename of ISO
                  WIN_LANG="$(basename "$SOURCE_FILE" | tr '_ ' '\n' | grep -io -m 1 "$(list_langs | awk -F: '{print $1}' | tr '\n' ';' | sed 's/;/\\|/g' | sed 's/\\|$/\n/g')" | tr '[A-Z]' '[a-z]')"
                  if [ -z "$WIN_LANG" ];then
                    read -p $'\nTo store files from this ISO, this script needs to know the language of this Windows ISO.\nPlease enter it now: (example: en-us) ' WIN_LANG
                    if [ -z "$WIN_LANG" ];then
                      error "Cannot proceed without a language for your ISO file."
                    elif ! list_langs | awk -F: '{print $1}' | grep -q "$WIN_LANG" ;then
                      error "Language code was not found in the list!\n$(list_langs | awk '{print $1}')"
                    fi
                  fi
                  using_esd=false #indicate that ESD will not be downloaded
                fi
              done
              
              if [ ! -z "$SOURCE_FILE" ];then
                break #exit "more options" menu
              fi
              ;;
            $num_opts)
              #go back
              break
              ;;
            *)
              #any number chosen other than 1,2,3: could be an additional option to choose pre-extracted ISO
              if [ "$reply" -le $num_opts ];then
                i="$(echo "$available_extracted_isos" | sed -n $((reply-2))p)"
                BID="$(echo "$i" | awk -F_ '{print $1}')"
                WIN_LANG="$(echo "$i" | awk -F_ '{print $2}')"
                using_esd=false #indicate that ESD will not be downloaded
                break
              else
                echo_red "Invalid option ${reply}.$([ $num_opts == 3 ] && echo " Expected '1', '2' or '3'.")"
              fi
              ;;
          esac
        done #End of loop for more options when choosing OS
        ;;
      *) echo_red "Invalid answer '${reply}'. Expected '1', '2' or '3'.";;
    esac
  done
  
  echo "Selected version: $(get_os_name "$BID") $WIN_LANG"
else
  
  #Verify SOURCE_FILE value provided to script
  if [ ! -z "$SOURCE_FILE" ];then
    if [ ! -f "$SOURCE_FILE" ];then
      error "Specified ISO file '$SOURCE_FILE' does not exist."
    elif [[ "$SOURCE_FILE" != *'.ISO' ]] && [[ "$SOURCE_FILE" != *'.iso' ]];then
      error "Specified ISO file '$SOURCE_FILE' does not have a .ISO file extension."
    elif [ "$(du -b "$SOURCE_FILE" | awk '{print $1}')" -lt $((3*1024*1024*1024)) ];then
      error "Specified ISO file '$SOURCE_FILE' is smaller than 3GB and is probably incomplete."
    fi
    
  #Verify BID value provided to script
  elif [ "$using_esd" == true ] && ! (list_bids 10 ; list_bids 11) | awk '{print $1}' | grep -Fqx "$BID" ;then
    error "Build ID '$BID' not found on list of available ones."
  fi
fi
}

{ #choose language
if [ -z "$WIN_LANG" ];then
  #list languages and highlight the language codes
  echo
  list_langs | sed 's/^/'$(echo -e '\e[96m')'/g' | sed 's/:/'$(echo -e '\e[0m')' - /g' | sort
  
  while true; do
    read -p $'\nFrom the list above, enter a language: ' WIN_LANG
    
    if list_langs | awk -F: '{print $1}' | grep -qFx "$WIN_LANG" ;then
      #if selected language matches line in language list
      break
    else
      echo_red "Invalid answer. Expected to see something like 'en-us'. Try again."
    fi
    
  done
  
#Verify WIN_LANG value provided to script
elif ! list_langs | awk -F: '{print $1}' | grep -qFx "$WIN_LANG" ;then
  error "Invalid WIN_LANG value '$WIN_LANG'.\nAvailable languages:\n$(list_langs | awk -F: '{print $1}')"
fi
}

{ #choose destination RPi model
if [ -z "$RPI_MODEL" ];then
  while true; do
    echo -ne "\nChoose Raspberry Pi model to deploy Windows on:
\e[96m1\e[0m) Raspberry Pi 4 / 400
\e[96m2\e[0m) Raspberry Pi 3 or Pi2 v1.2
Enter \e[96m1\e[0m or \e[96m2\e[0m: "
    read reply
    case $reply in
      1)
        RPI_MODEL=4
        break
        ;;
      2)
        RPI_MODEL=3
        break
        ;;
      *) echo_red "Invalid option '${reply}'. Expected '1' or '2'.";;
    esac
  done
elif [ "$RPI_MODEL" != 3 ] && [ "$RPI_MODEL" != 4 ];then
  error "Unknown value for RPI_MODEL. Expected '3' or '4'."
fi
}

{ #choose output device
if [ -z "$DEVICE" ];then
  while true;do
    echo
    echo "Available devices:"
    list_devs || echo -e "\e[93mNone found - please insert a storage device and press Enter\e[0m"
    read -p "Choose a device to flash the Windows setup files to: " DEVICE
    if [ "$DEVICE" == "$ROOT_DEV" ];then
      echo_red "Device $DEVICE is your current boot drive! You cannot overwrite this drive."
    elif [ -b "$DEVICE" ];then
      break #exit loop
    elif [ -z "$DEVICE" ];then
      true #refresh list if user presses Enter
    else
      echo_red "Device $DEVICE is not a valid block device!"
    fi
  done
  
elif [ ! -b "$DEVICE" ];then
  error "Invalid value for DEVICE: block device $DEVICE does not exist. Available devices:\n$(list_devs)"
elif [ "$DEVICE" == "$ROOT_DEV" ];then
  error "Refusing to overwrite current boot drive $DEVICE."
fi
}

{ #CAN_INSTALL_ON_SAME_DRIVE
if [ "$(get_size_raw "$DEVICE")" -lt $((7*1024*1024*1024)) ];then
  error "Drive $DEVICE is smaller than 7GB and cannot be used."
fi

if [ -z "$CAN_INSTALL_ON_SAME_DRIVE" ] && [ "$(get_size_raw "$DEVICE")" -ge $((25*1024*1024*1024)) ];then
  #Drive is >=25GB, so present the user with the option to make this a recovery drive or a full installation
  
  while true; do
    echo -ne "\nWould you like to:
\e[96m1\e[0m) Create an installation drive capable of installing Windows to itself
\e[96m2\e[0m) Create a recovery drive to install Windows on other >16 GB drives
Choose the installation mode (\e[96m1\e[0m or \e[96m2\e[0m): "
    read reply
    case $reply in
      1)
        CAN_INSTALL_ON_SAME_DRIVE=1
        break
        ;;
      2)
        CAN_INSTALL_ON_SAME_DRIVE=0
        break
        ;;
      *) echo_red "Invalid option '${reply}'. Expected '1' or '2'.";;
    esac
  done
  
elif [ -z "$CAN_INSTALL_ON_SAME_DRIVE" ];then
  #Drive is <25GB, so user's only choice is to make this a recovery drive
  
  while true; do
    echo -ne "\nDrive $DEVICE is too small to install Windows to itself. (25 GB is necessary)
Would you like to:\n\e[96m1\e[0m) Exit
\e[96m2\e[0m) Create a recovery drive to install Windows on other >16 GB drives
Choose the installation mode (\e[96m1\e[0m or \e[96m2\e[0m): "
    read reply
    case $reply in
      1)
        error "exited"
        ;;
      2)
        CAN_INSTALL_ON_SAME_DRIVE=0
        break
        ;;
      *) echo_red "Invalid option ${reply}. Expected '1' or '2'.";;
    esac
  done
  
elif [ "$CAN_INSTALL_ON_SAME_DRIVE" != 0 ] && [ "$CAN_INSTALL_ON_SAME_DRIVE" != 1 ];then
  error "Unknown value for CAN_INSTALL_ON_SAME_DRIVE. Expected '0' or '1'."
  
elif [ "$CAN_INSTALL_ON_SAME_DRIVE" == 1 ];then
  #Variable pre-populated, so if it is 1 make sure the drive is 25GB or larger
  if [ "$(get_size_raw "$DEVICE")" -lt $((25*1024*1024*1024)) ];then
    error "Drive $DEVICE is smaller than 25GB and cannot be used for self-installation.\nPlease set CAN_INSTALL_ON_SAME_DRIVE=0"
  fi
  #no need to check if drive is >7GB, because it was already done earlier
fi
}

echo "
Input configuration:
DL_DIR: $DL_DIR
RUN_MODE: $RUN_MODE
RPI_MODEL: $RPI_MODEL
DEVICE: $DEVICE
CAN_INSTALL_ON_SAME_DRIVE: $CAN_INSTALL_ON_SAME_DRIVE"
[ ! -z "$SOURCE_FILE" ] && echo "SOURCE_FILE: $SOURCE_FILE"
echo "BID: $BID
WIN_LANG: $WIN_LANG"
[ ! -z "$CONFIG_TXT" ] && echo "CONFIG_TXT: ⤵
$(echo "$CONFIG_TXT" | grep . | sed 's/^/  > /g')
CONFIG_TXT: ⤴"
[ ! -z "$DRY_RUN" ] && echo "DRY_RUN: $DRY_RUN"
echo

if [ ! -d "$PWD/peinstaller" ];then
  status "Downloading WoR PE-based installer from Google Drive"
  
  PE_INSTALLER_SHA256=$(wget -qO- http://worproject.com/dldserv/worpe/gethashlatest.php | cut -d ':' -f2)
  [ -z "$PE_INSTALLER_SHA256" ] && error "Failed to determine a hashsum for WoR PE-based installer.\nURL: http://worproject.com/dldserv/worpe/gethashlatest.php"
  
  #from: https://worproject.com/downloads#windows-on-raspberry-pe-based-installer
  URL='http://worproject.com/dldserv/worpe/downloadlatest.php'
  #determine Google Drive FILEUUID from given redirect URL
  FILEUUID="$(wget --spider --content-disposition --trust-server-names -O /dev/null "$URL" 2>&1 | grep Location | sed 's/^Location: //g' | sed 's/ \[following\]$//g' | grep 'drive\.google\.com' | sed 's+.*/++g' | sed 's/.*&id=//g')"
  download_from_gdrive "$FILEUUID" "$PWD/WoR-PE_Package.zip" || error "Failed to download Windows on Raspberry PE-based installer"
  
  if [ "$PE_INSTALLER_SHA256" != "$(sha256sum "$PWD/WoR-PE_Package.zip" | awk '{print $1}' | tr '[a-z]' '[A-Z]')" ];then
    error "PE-based installer integrity check failed"
  fi
  
  rm -rf "$PWD/peinstaller"
  unzip -q "$PWD/WoR-PE_Package.zip" -d "$PWD/peinstaller"
  if [ $? != 0 ];then
    rm -rf "$PWD/peinstaller"
    error "The unzip command failed to extract $PWD/WoR-PE_Package.zip"
  fi
  rm -f "$PWD/WoR-PE_Package.zip"
  echo
else
  echo "Not downloading $PWD/peinstaller - folder exists"
fi

if [ ! -d "$PWD/driverpackage" ];then
  status "Downloading ARM64 drivers"
  #from: https://github.com/worproject/RPi-Windows-Drivers/releases
  #example download URL (will be outdated) https://github.com/worproject/RPi-Windows-Drivers/releases/download/v0.11/RPi4_Windows_ARM64_Drivers_v0.11.zip
  #determine latest release download URL:
  URL="$(wget -qO- https://api.github.com/repos/worproject/RPi-Windows-Drivers/releases/latest | grep '"browser_download_url":'".*RPi${RPI_MODEL}_Windows_ARM64_Drivers_.*\.zip" | sed 's/^.*browser_download_url": "//g' | sed 's/"$//g')"
  wget -O "$PWD/RPi${RPI_MODEL}_Windows_ARM64_Drivers.zip" "$URL" || error "Failed to download driver package"
  
  rm -rf "$PWD/driverpackage"
  unzip -q "$PWD/RPi${RPI_MODEL}_Windows_ARM64_Drivers.zip" -d "$PWD/driverpackage"
  if [ $? != 0 ];then
    rm -rf "$PWD/driverpackage"
    error "The unzip command failed to extract $PWD/RPi${RPI_MODEL}_Windows_ARM64_Drivers.zip"
  fi
  
  rm -f "$PWD/RPi${RPI_MODEL}_Windows_ARM64_Drivers.zip"
  echo
else
  echo "Not downloading $PWD/driverpackage - folder exists"
fi

if [ ! -d "$PWD/pi${RPI_MODEL}-uefipackage" ];then
  status "Downloading Pi${RPI_MODEL} UEFI firmware"
  rm -rf "$PWD/pi${RPI_MODEL}-uefipackage" "$PWD/uefipackage" "$PWD/RPi${RPI_MODEL}_UEFI_Firmware.zip"
  #from: https://github.com/pftf/RPi4/releases
  #example download URL (will be outdated) https://github.com/pftf/RPi4/releases/download/v1.29/RPi4_UEFI_Firmware_v1.29.zip
  
  #determine latest release download URL:
  #URL="$(wget -qO- https://api.github.com/repos/pftf/RPi${RPI_MODEL}/releases/latest | grep '"browser_download_url":'".*RPi${RPI_MODEL}_UEFI_Firmware_.*\.zip" | sed 's/^.*browser_download_url": "//g' | sed 's/"$//g')"
  
  case "$RPI_MODEL" in
    5)
      URL='https://github.com/worproject/rpi5-uefi/releases/download/v0.2/RPi5_UEFI_Release_v0.2.zip'
      ;;
    4)
      URL='https://github.com/pftf/RPi4/releases/download/v1.33/RPi4_UEFI_Firmware_v1.33.zip'
      #held back on 1.33 for greater stability: https://github.com/pftf/RPi4/issues/227
      ;;
    3)
      URL='https://github.com/pftf/RPi3/releases/download/v1.39/RPi3_UEFI_Firmware_v1.39.zip'
  esac
  
  wget -O "$PWD/RPi${RPI_MODEL}_UEFI_Firmware.zip" "$URL" || error "Failed to download UEFI package"
  
  rm -rf "$PWD/pi${RPI_MODEL}-uefipackage"
  unzip -q "$PWD/RPi${RPI_MODEL}_UEFI_Firmware.zip" -d "$PWD/pi${RPI_MODEL}-uefipackage"
  if [ $? != 0 ];then
    rm -rf "$PWD/pi${RPI_MODEL}-uefipackage"
    error "The unzip command failed to extract $PWD/RPi${RPI_MODEL}_UEFI_Firmware.zip"
  fi
  
  rm -f "$PWD/RPi${RPI_MODEL}_UEFI_Firmware.zip"
  echo
else
  echo "Not downloading $PWD/pi${RPI_MODEL}-uefipackage - folder exists"
fi

{ #Download Windows ESD if an ISO was not provided and one has not already been extracted

if [ ! -z "$SOURCE_FILE" ];then
  echo "Not downloading ESD image - using your ISO instead"
  
  #set folder name to store files from the ISO
  #files are stored in a folder specific to the OS version and language
  winfiles="winfiles_from_iso_${BID}_${WIN_LANG}"
  mkdir -p "$PWD/$winfiles"
  
elif [ -f "$PWD/winfiles_from_iso_${BID}_${WIN_LANG}/alldone" ];then
  echo "Not downloading ESD image - using a previously extracted ISO instead"
  winfiles="winfiles_from_iso_${BID}_${WIN_LANG}"
  
elif [ -f "$PWD/winfiles_${BID}_${WIN_LANG}/alldone" ];then
  echo "Not downloading ESD image - already extracted"
  winfiles="winfiles_${BID}_${WIN_LANG}"
  
else #Download and extract ESD
  
  #Get list of all Windows ESD releases for this Build ID from worproject.com
  if [ "$using_esd" == true ];then
    #Only do it if ESD download is required
    catalog="$(cache_downloader "https://worproject.com/dldserv/esd/getcatalog.php?build=$BID&arch=ARM64&edition=Professional")" || exit 1
  fi
  
  #Shorten catalog to only show the ESD for this language
  catalog="$(echo "$catalog" | sed 's/></>\n</g' | sed -n '/<Languages>/q;p' | sed -n '/^<LanguageCode>'"${WIN_LANG}"'/,${p;/^<\/File>/q}')"
  
  #Get download link, size, and SHA1 hash for ESD
  URL="$(echo "$catalog" | grep '<FilePath>' -m 1 | sed 's/<FilePath>//g' | sed 's/<\/FilePath>//g')"
  SIZE="$(echo "$catalog" | grep '<Size>' -m 1 | sed 's/<Size>//g' | sed 's/<\/Size>//g')"
  SHA1="$(echo "$catalog" | grep '<Sha1>' -m 1 | sed 's/<Sha1>//g' | sed 's/<\/Sha1>//g')"
  
  #DL_DIR could be on a FAT partition, which is only OK if no files are larger than 4GB.
  #Make sure that the ESD is smaller than 4GB if DL_DIR is on FAT-type partition
  if [ "$SIZE" -ge $((4*1024*1024*1024)) ] && df -T "$DL_DIR" 2>/dev/null | grep -q 'fat' ;then
    error "The $DL_DIR directory is on a FAT32/FAT16/vfat partition. This type of partition cannot contain files larger than 4GB, however the Windows ESD image will be larger than that.\nPlease format the drive with an Ext4 partition, or use another drive."
  fi
  
  #set folder name to store files from the ESD
  #files are stored in a folder specific to the OS version and language
  winfiles="winfiles_${BID}_${WIN_LANG}"
  mkdir -p "$PWD/$winfiles"
  
  if [ -f "$PWD/$winfiles/image.esd" ] && [ "$SHA1" == "$(sha1sum "$PWD/$winfiles/image.esd" | awk '{print $1}')" ];then
    echo "Not downloading $PWD/$winfiles/image.esd - file exists"
  else
    status "Downloading Windows ESD image"
    wget "$URL" -O "$PWD/$winfiles/image.esd" || error "Failed to download ESD image"
    status -n "Verifying download... "
    LOCAL_SHA1="$(sha1sum "$PWD/$winfiles/image.esd" | awk '{print $1}')"
    if [ "$SHA1" != "$LOCAL_SHA1" ];then
      error "\nSuccessfully downloaded ESD image, but it appears to be corrupted. Please run this script again.\n(Expected SHA1 hash is $SHA1, but downloaded file has SHA1 hash $LOCAL_SHA1"
    fi
    echo_green "Done"
  fi
  SOURCE_FILE="$PWD/$winfiles/image.esd"
fi
}

#Extract ESD or ISO to standardized locations in $DL_DIR
if [[ "$SOURCE_FILE" == *'.ESD' ]] || [[ "$SOURCE_FILE" == *'.esd' ]];then
  cd "$PWD/$winfiles" || error "Failed to access $PWD/$winfiles folder"
  
  status "Extracting $(basename "$SOURCE_FILE") to $PWD"
  #Extract first volume containing boot files
  errors="$(wimextract "$SOURCE_FILE" 1 boot efi --dest-dir="$PWD/bootpart" 2>&1)" || error "Failed to extract first partition of $SOURCE_FILE\nErrors:\n$errors"
  
  #Create boot.wim file
  mkdir "$PWD/bootpart/sources"
  #Export WinPE & Setup editions to non-solid boot.wim
  errors="$(wimexport "$SOURCE_FILE" 2 "$PWD/bootpart/sources/boot.wim" --compress=LZX 2>&1)" || error "Failed to export WinPE edition to $PWD/bootpart/sources/boot.wim\nErrors:\n$errors"
  errors="$(wimexport "$SOURCE_FILE" 3 "$PWD/bootpart/sources/boot.wim" --compress=LZX --boot 2>&1)" || error "Failed to export Setup edition to $PWD/bootpart/sources/boot.wim\nErrors:\n$errors"
  
  #If using an external ESD file, make a copy before modifying it
  if [ "$SOURCE_FILE" != "$PWD/image.esd" ];then
    cp "$SOURCE_FILE" "$PWD/image.esd" || error "Failed to copy the ESD to $PWD/image.esd"
    SOURCE_FILE="$PWD/image.esd"
  fi
  #Remove first 3 partitions from ESD file
  errors="$(wimdelete "$SOURCE_FILE" 1 --soft 2>&1)" || error "Failed to remove a partition from $SOURCE_FILE\nErrors:\n$errors"
  errors="$(wimdelete "$SOURCE_FILE" 1 --soft 2>&1)" || error "Failed to remove a partition from $SOURCE_FILE\nErrors:\n$errors"
  errors="$(wimdelete "$SOURCE_FILE" 1 --soft 2>&1)" || error "Failed to remove a partition from $SOURCE_FILE\nErrors:\n$errors" #remove --soft for this last one to minimize filesize
  mv -f "$SOURCE_FILE" "$PWD/install.wim" || error "Failed to rename $SOURCE_FILE to install.wim"
  
  touch "$PWD/alldone" #mark this folder of microsoft stuff as complete
  
  #Change working directory back to $DL_DIR
  cd ..
  
elif [[ "$SOURCE_FILE" == *'.ISO' ]] || [[ "$SOURCE_FILE" == *'.iso' ]];then
  cd "$PWD/$winfiles" || error "Failed to access $PWD/$winfiles folder"
  
  status "Mounting $(basename "$SOURCE_FILE")"
  mkdir -p "$PWD/isomount" || error "Failed to make $PWD/isomount folder"
  sudo umount "$PWD/isomount" 2>/dev/null
  sudo mount "$SOURCE_FILE" "$PWD/isomount" 2>/dev/null
  if [ $? != 0 ];then
    status "Failed to mount the ISO file. Trying again after loading the 'udf' kernel module."
    sudo modprobe udf
    
    if [ $? != 0 ];then
      modprobe_failed=1
    else
      modprobe_failed=0
    fi
    
    sudo mount "$SOURCE_FILE" "$PWD/isomount"
    if [ $? != 0 ];then
      if [ "$modprobe_failed" == 1 ] && [ ! -d "/lib/modules/$(uname -r)" ];then
        error "The 'udf' kernel module is required to mount the ISO file (uupdump/$(basename $(echo "$PWD/uupdump"/*.ISO))), but all kernel modules are missing! Most likely, you upgraded kernel packages and have not rebooted yet. Try rebooting."
      else
        error "Failed to mount ISO file ($(echo "$PWD/uupdump"/*.ISO)) to $PWD/isomount"
      fi
    fi
  fi
  #unmount on exit
  trap "sudo umount -q '$PWD/isomount' 2>/dev/null" EXIT
  
  mkdir -p "$PWD"/bootpart
  status "Copying files from ISO file to $PWD:"
  echo "  - Boot files"
  cp -r "$PWD/isomount/boot" "$PWD"/bootpart || error "Failed to copy $PWD/isomount/boot to $PWD/bootpart"
  echo "  - EFI files"
  cp -r "$PWD/isomount/efi" "$PWD"/bootpart || error "Failed to copy $PWD/isomount/efi to $PWD/bootpart"
  mkdir -p "$PWD"/bootpart/sources || error "Failed to make folder: $PWD/bootpart/sources"
  echo "  - boot.wim"
  cp "$PWD/isomount/sources/boot.wim" "$PWD"/bootpart/sources || error "Failed to copy $PWD/isomount/sources/boot.wim to $PWD/bootpart/sources"
  echo "  - install.wim"
  cp "$PWD/isomount/sources/install.wim" "$PWD" || error "Failed to copy $PWD/isomount/sources/install.wim to $PWD/winpart"
  
  touch "$PWD/alldone" #mark this folder of microsoft stuff as complete
  
  echo "All necessary files have been copied out. Your ISO file will not be needed for future flashes."
  
  status "Unmounting ISO file"
  sudo umount "$PWD/isomount" || echo_red "Warning: failed to unmount $PWD/isomount" #failure is non-fatal
  rmdir "$PWD/isomount" #remove mountpoint
  
  #Change working directory back to $DL_DIR
  cd ..
fi

if [ "$DRY_RUN" == 1 ];then
  status "Exiting $(basename "$0") script now because the DRY_RUN variable was set to '1'."
  exit 0
fi

#now that downloads are complete, check again if destination storage is accessible
if [ ! -b "$DEVICE" ];then
  error "Device $DEVICE is not a valid block device! Available devices:\n$(list_devs)"
fi

echo
status "Formatting $DEVICE - \e[93mThere is no turning back now."
sync
sudo umount -ql $(get_partition "$DEVICE" all)
sync
status "Creating partition table"
sudo parted -s "$DEVICE" mklabel gpt || error "Failed to make GPT partition table on ${DEVICE}!"
sync
status "Generating partitions"
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

status "Generating filesystems"
PART1="$(get_partition "$DEVICE" 1)"
PART2="$(get_partition "$DEVICE" 2)"
echo "Partition 1: $PART1, Partition 2: $PART2"

errors="$(sudo mkfs.fat -F 32 "$PART1" 2>&1)" || error "Failed to create FAT partition on $PART1\nErrors:\n$errors"
errors="$(sudo mkfs.exfat "$PART2" 2>&1)" || error "Failed to create EXFAT partition on $PART2\nErrors:\n$errors"

mntpnt="/media/$USER/wor-flasher"
status "Mounting ${DEVICE} device to $mntpnt"
sudo mkdir -p "$mntpnt"/bootpart || error "Failed to create mountpoint: $mntpnt/bootpart"
sudo mkdir -p "$mntpnt"/winpart || error "Failed to create mountpoint: $mntpnt/winpart"
sudo umount -q "$mntpnt"/bootpart
sudo umount -q "$mntpnt"/winpart
sudo mount "$PART1" "$mntpnt"/bootpart || error "Failed to mount $PART1 to $mntpnt/bootpart"
sudo mount.exfat-fuse "$PART2" "$mntpnt"/winpart
if [ $? != 0 ];then
  status "Failed to mount $PART2. Trying again after loading the 'fuse' kernel module."
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
#unmount device partitions on exit
trap "sudo umount -q '$mntpnt/bootpart' 2>/dev/null" EXIT
trap "sudo umount -q '$mntpnt/winpart' 2>/dev/null" EXIT

status "Copying files to $DEVICE:"
echo "  - Startup environment"
sudo cp -r "$PWD/$winfiles/bootpart"/* "$mntpnt"/bootpart || error "Failed to copy $PWD/$winfiles/bootpart to $mntpnt/bootpart"
echo "  - Installation files"
sudo cp "$PWD/$winfiles/install.wim" "$mntpnt"/winpart || error "Failed to copy $PWD/$winfiles/install.wim to $mntpnt/winpart"
echo "  - EFI files"
sudo cp -r "$PWD/peinstaller/efi" "$mntpnt"/bootpart || error "Failed to copy $PWD/peinstaller/efi to $mntpnt/bootpart"

echo "  - PE installer"
errors="$(sudo wimupdate "$mntpnt"/bootpart/sources/boot.wim 2 --command="add peinstaller/winpe/2 /" 2>&1)" || error "The wimupdate command failed to add $PWD/peinstaller to boot.wim\nErrors:\n$errors"

echo "  - ARM64 drivers"
errors="$(sudo wimupdate "$mntpnt"/bootpart/sources/boot.wim 2 --command="add driverpackage /drivers" 2>&1)" || error "The wimupdate command failed to add $PWD/driverpackage to boot.wim\nErrors:\n$errors"

echo "  - UEFI firmware"
sudo cp -r "$PWD/pi${RPI_MODEL}-uefipackage"/* "$mntpnt"/bootpart || error "Failed to copy $PWD/pi${RPI_MODEL}-uefipackage to $mntpnt/bootpart"

if [ ! -z "$CONFIG_TXT" ];then
  status "Customizing config.txt according to the CONFIG_TXT variable"
  echo "$CONFIG_TXT" | sudo tee "$mntpnt"/bootpart/config.txt >/dev/null
fi

if [ $RPI_MODEL == 3 ];then
  status "Applying GPT partition-table fix for the Pi3/Pi2"
  #According to @mariob, this patches the first sector of the disk to guide the bootloader into finding the fat32 partition
  #there's no other way of doing it on the pi 3 - hardware limitation
  sudo dd if=$PWD/peinstaller/pi3/gptpatch.img of="$DEVICE" conv=fsync || error "The 'dd' command failed to flash $PWD/peinstaller/pi3/gptpatch.img to $DEVICE"
fi

status -n "Allowing pending writes to finish... "
sync
echo_green "Done"

status "Ejecting drive $DEVICE"
sudo umount "$PART1" || echo_red "Warning: the umount command failed to unmount all partitions within $DEVICE"
sudo umount "$PART2" || echo_red "Warning: the umount command failed to unmount all partitions within $DEVICE"
sudo umount -q "$mntpnt"/bootpart &>/dev/null
sudo umount -q "$mntpnt"/winpart &>/dev/null
sudo eject "$DEVICE" &>/dev/null
sudo rmdir "$mntpnt"/bootpart "$mntpnt"/winpart || echo_red "Warning: Failed to remove the mountpoint folder: $mntpnt"
status "$(basename "$0") script has completed."
