# ![app icon](https://github.com/Botspot/wor-flasher/blob/main/logo.png?raw=true) WoR-flasher
**Use a Linux machine to install Windows 10 or Windows 11 on a Raspberry Pi SD card.**

A year ago, this was flat-out impossible.  
In July 2021, this required following [a complicated tutorial](https://worproject.ml/guides/how-to-install/from-other-os).  
Now, using the new WoR-flasher, it's a *piece of cake*.  

## Useful information
- This tool is **100% legal**. All propriatary Windows components are downloaded straight from Microsoft's update servers using [uupdump](https://uupdump.net).
- Disclaimer: This tool has only been tested to run correctly on Raspberry Pi OS 32-bit. Botspot (the developer of this tool) cannot be held responsible for data loss!
- Need help using the WoR-flasher tool? You can open an issue or ask for help in [the Botspot Software discord server](https://discord.gg/RXSTvaUvuu)
- Need help using Windows on Raspberry (The operating system)? Contact the WoR developers [through email](https://worproject.ml/contact) or [join their Discord server](https://discord.gg/worofficial).
- By default, WoR will limit your usable RAM to 3GB due to a complication in the Pi4's CPU design. There is a workaround, but it's not the default. [Click here for details](https://worproject.ml/faq#only-3-gb-of-ram-are-available-how-can-i-fix-this)

## WoR-flasher walkthrough
### To download WoR-flasher
```
git clone https://github.com/Botspot/wor-flasher
```
This will create a new folder in your home directory named `wor-flasher`.
### To run WoR-flasher using the terminal interface
```
~/wor-flasher/install-wor.sh
```
### To run WoR-flasher using the graphical interface

```
~/wor-flasher/install-wor-gui.sh
```


