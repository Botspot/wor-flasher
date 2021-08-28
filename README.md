# ![app icon](https://github.com/Botspot/wor-flasher/blob/main/logo.png?raw=true) WoR-flasher
**Use a Linux machine to install Windows 10 or Windows 11 on a Raspberry Pi SD card.**

A year ago, this was flat-out impossible.  
In July 2021, this required following [a complicated tutorial](https://worproject.ml/guides/how-to-install/from-other-os).  
Now, using the new WoR-flasher, it's a *piece of cake*.  

## Useful information
- This tool is **100% legal**. All propriatary Windows components are downloaded straight from Microsoft's update servers using [uupdump](https://uupdump.net).
- Disclaimer: This tool has only been tested to run correctly on Raspberry Pi OS 32-bit. Botspot (the developer of this tool) cannot be held responsible for data loss!
- Need help using the WoR-flasher tool? You can [open an issue](https://github.com/Botspot/wor-flasher/issues/new/choose) or ask for help in [the Botspot Software discord server](https://discord.gg/RXSTvaUvuu)
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
- A terminal will launch and run the `install-wor.sh` script:  
![terminal3](https://user-images.githubusercontent.com/54716352/131228381-11dc3a4e-96da-40ec-8f46-8b28ade5ee52.png)
- If all goes well, the terminal will close and you will be told what to do next.  
![next steps](https://user-images.githubusercontent.com/54716352/131228409-f84ede9b-a1fc-43f9-a79c-5b1853513960.png)




