@echo off

if exist build_release\locus.exe goto check
goto compile

:check
for /F "tokens=*" %%# in ('del /Q "build_release\locus.exe" 2^>^&1 1^> nul') do (2> nul set =)
if errorlevel 1 goto locked

:compile
echo Compiling...
jai first.jai - release
move build_release\*.* .
copy global.focus-config my_config.focus-config /y

goto:eof

:locked
echo Close Locus first!
