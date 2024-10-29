@echo off
setlocal enabledelayedexpansion

REM List physical devices
echo Listing physical devices:
wmic diskdrive list brief

REM Prompt user to select a device
set /p "selectedDevice=Enter the number of the physical device you want to use for the QEMU VM (e.g., Disk 0): "

REM Prompt user to enter the amount of RAM
set /p "ramAmount=Enter the amount of RAM for the QEMU VM in MB: "

REM Set the number of CPU cores
set "cpuCores=4"

REM Additional QEMU options for performance
set "qemuOptions=-m !ramAmount! -smp !cpuCores! -drive file=\\.\PhysicalDrive%selectedDevice%,format=raw"

REM Display selected drive details
echo.
echo Selected Drive: !selectedDevice!
wmic diskdrive where index=!selectedDevice! get Caption,Size

REM Display QEMU command
echo.
echo QEMU COMMAND:
echo qemu-system-x86_64.exe %qemuOptions%

REM Execute QEMU command
qemu-system-x86_64.exe %qemuOptions%

REM Check for errors
if %errorlevel% neq 0 (
    echo.
    echo ERROR: QEMU failed to start. Check the QEMU command and ensure proper setup.
    pause
) else (
    echo.
    echo QEMU started successfully.
)

endlocal
