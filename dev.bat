@echo off

jai first.jai
copy /Y build_debug\focus_debug.exe focus_dev.exe
copy /Y build_debug\focus_debug.pdb focus_dev.pdb