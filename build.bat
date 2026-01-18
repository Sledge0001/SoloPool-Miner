@echo off
REM SoloPool Miner Build Script for Windows
REM Requires: NVIDIA CUDA Toolkit, Visual Studio 2019/2022

echo ==========================================
echo  SoloPool Miner v1.0.0 Build Script
echo ==========================================
echo.

REM Check for nvcc
where nvcc >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: nvcc not found. Please install NVIDIA CUDA Toolkit.
    echo Download from: https://developer.nvidia.com/cuda-toolkit
    pause
    exit /b 1
)

echo Building SoloPool Miner...
echo.

REM Build with CUDA + OpenCL support
nvcc -O3 -arch=sm_86 -allow-unsupported-compiler -Xlinker /SUBSYSTEM:WINDOWS ^
     -o SoloPoolMiner.exe solopool_miner.cu ^
     -lws2_32 -lcomctl32 -lgdi32 -luser32 -lshell32 -lnvml -lOpenCL

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ==========================================
    echo  BUILD SUCCESSFUL!
    echo  Output: SoloPoolMiner.exe
    echo ==========================================
) else (
    echo.
    echo ==========================================
    echo  BUILD FAILED!
    echo  Check error messages above.
    echo ==========================================
)

pause
