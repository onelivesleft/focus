@echo off

:loop
jai first.jai - dev
if errorlevel 1 goto loop
