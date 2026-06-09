# Rodoslov Family Tree Creator

This is a simple family tree editor/viewer. The resulting family tree is stored in a SQLite database called family.sqlite. Please note that this is really only for my personal use, so it might not be fit for your purposes at this moment. The icon is currently and AI generated placeholde, but the code is all me. The project only supports builds for android arm_64 and windows x86_64 at the moment. Make sure to  `git clone --recurse-submodules` because this prokect uses some custom libraries!

Note that when building for android you have to modify modules/Input/android.jai line 358 to `if (source & handled_sources) == 0 && event_type != .KEY {` in order to have the text input events get passed through!

[[![Demo Video](./demo.mp4)]](https://github.com/user-attachments/assets/09b5528e-1acb-4c67-81a9-78a8e2515c79)
