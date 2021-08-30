# ![app icon](https://github.com/Botspot/wor-flasher/blob/main/logo.png?raw=true) WoR-flasher
**Use a Linux machine to install Windows 10 or Windows 11 on a Raspberry Pi SD card.**

A year ago, this was flat-out impossible.  
In July 2021, this required following [a complicated tutorial](https://worproject.ml/guides/how-to-install/from-other-os).  
Now, using the new WoR-flasher, it's a *piece of cake*.  

## Useful information
- This tool is **100% legal**. All propriatary Windows components are downloaded straight from Microsoft's update servers using [uupdump](https://uupdump.net). Consider reading [this debate](https://www.raspberrypi.org/forums/viewtopic.php?f=29&t=318599) that took place on the Raspberry Pi Forums. At the conclusion of the thread, Raspberry Pi moderators [confirm](https://www.raspberrypi.org/forums/viewtopic.php?f=29&t=318599#p1907313) that WoR is 100% legal.
- In theory, this tool will run correctly on any Debian-based Linux, ARM or x86. However, this tool has only been tested to run correctly on Raspberry Pi OS 32-bit. Botspot (the developer of this tool) cannot be held responsible for data loss!
- Need help using the WoR-flasher tool? You can [open an issue](https://github.com/Botspot/wor-flasher/issues/new/choose) or ask for help in [the Botspot Software discord server](https://discord.gg/RXSTvaUvuu)
- Need help using Windows on Raspberry (The operating system)? Contact the WoR developers [through email](https://worproject.ml/contact) or [join their Discord server](https://discord.gg/worofficial).
- By default, WoR will limit your usable RAM to 3GB due to a complication in the Pi4's CPU design. There is a workaround, but it's not the default. [Click here for details](https://worproject.ml/faq#only-3-gb-of-ram-are-available-how-can-i-fix-this)

## WoR-flasher walkthrough
### To download WoR-flasher
```
git clone https://github.com/Botspot/wor-flasher
```
This will create a new folder in your home directory named `wor-flasher`.
### To run WoR-flasher using the graphical interface
```
~/wor-flasher/install-wor-gui.sh
```
- Choose a Windows version and choose which Raspberry Pi model will be running it.  
![page1](https://user-images.githubusercontent.com/54716352/131228226-5d5b8456-b273-48a5-b4c3-5e90790cf21e.png)
- Choose a language for Windows.  
![page2](https://user-images.githubusercontent.com/54716352/131228261-e7e1a989-4151-4df7-8aa2-eff95704df41.png)
- Plug in a writable storage device to flash Windows to.  
![page3](https://user-images.githubusercontent.com/54716352/131228296-fb61f216-9a12-412a-b7b5-0bcd185891a0.png)
  - If the storage device is larger than 25GB, it can install Windows on itself.
  - If the storage device is smaller than 25GB but larger than 7GB, it can only install Windows on other drives. (like a Windows recovery disk)
  - If the storage device is smaller than 7GB, it is too small to be usable.
- Double-check that everything looks correct before clicking the Flash button.  
![page4](https://user-images.githubusercontent.com/54716352/131228359-5d322ee6-ecd7-41b9-8220-d18e9f38f232.png)
- A terminal will launch and run the `install-wor.sh` script: (Note that now, the script will start downloading Windows piece-by-piece from Microsoft's update servers. A lot of bandwidth will be used at this step to download the ~3GB OS image, so make sure there won't be issues with internet usage. This step will also take up to 30 minutes depending on your internet speed, so just leave it running in the background and go drink some water)  
![terminal3](https://user-images.githubusercontent.com/54716352/131228381-11dc3a4e-96da-40ec-8f46-8b28ade5ee52.png)
- If all goes well, the terminal will close and you will be told what to do next.  
![next steps](https://user-images.githubusercontent.com/54716352/131228409-f84ede9b-a1fc-43f9-a79c-5b1853513960.png)
### To run WoR-flasher using the terminal interface
```
~/wor-flasher/install-wor.sh
```
<details><summary>Example terminal walkthrough (click to expand)</summary>
$ ~/wor-flasher/install-wor.sh
Choose Windows version:
1) Windows 11
2) Windows 10
3) Custom...
Enter 1, 2 or 3: 1

Choose language: en-us

Choose Raspberry Pi model to deploy Windows on:
1) Raspberry Pi 4 / 400
2) Raspberry Pi 2 rev 1.2 / 3 / CM3
Enter 1 or 2: 1

Available devices:
/dev/sdb - 59.5GB - USB Storage
Choose a device to flash the Windows setup files to: /dev/sdb

1) Create an installation drive (minimum 25 GB) capable of installing Windows to itself
2) Create a recovery drive (minimum 7 GB) to install Windows on other >16 GB drives
Choose the installation mode (1 or 2): 1

Input configuration:
DL_DIR: /home/pi/wor-flasher-files
RUN_MODE: cli
RPI_MODEL: 4
DEVICE: /dev/sdb
CAN_INSTALL_ON_SAME_DRIVE: 1
UUID: 6f7de912-4143-431b-b605-924c22ab9b1f
WIN_LANG: en-us

Formatting /dev/sdb
Generating partitions
Generating filesystems
# script output continues... It generates a Windows image legally, downloads all necessary drivers, the BIOS, the bootloader, and the modified kernel. Once done it ejects the drive.
</details>
This script is actually what does the flashing: The gui script is just a front-end that launches dialog windows and finally runs install-wor.sh in a terminal.

### Environment variables
The `install-wor.sh` script is designed to be used within other, larger bash scripts. For automation and customization, `install-wor.sh` will detect and obey certain environment variables:

- `DL_DIR`: Set this variable to change the default download location. By default, it's `~/wor-flasher-files`.
- `UUID`: Set this variable to choose an exact Windows update ID. Example value: "`db8ec987-d136-4421-afb8-2ef109396b00`". When this variable is set, `install-wor.sh` will not ask the user which Windows version to use.
- `WIN_LANG`: Set this variable to choose a language for the Windows image. Example value: "`en-us`". When this variable is set, `install-wor.sh` will not ask the user which language to use.
- `RPi_MODEL`: Set this variable to choose Raspberry Pi model. Allowed values: "`3`", "`4`". When this variable is set, `install-wor.sh` will not ask the user which Raspberry Pi model to use.
- `DEVICE`: Set this variable to the device you want to flash. Example value: "`/dev/sda`" When this variable is set, `install-wor.sh` will not ask the user which device to use.
- `CAN_INSTALL_ON_SAME_DRIVE`: Set this variable to "`1`" if the device is larger than 25GB and you wish to install Windows on itself. Otherwise, set it to "`0`".
- `CONFIG_TXT`: Set this variable to customize the `/boot/config.txt` of the resulting drive. This is commonly used for overclocking or to change HDMI settings. [This is the default value.](https://github.com/pftf/RPi4/blob/master/config.txt)
- `RUN_MODE`: Set this to "`gui`" if you want `install-wor.sh` to display graphical error messages.


