@echo off
REM SoloPool Miner Build Script for Windows
REM Requires: NVIDIA CUDA Toolkit, Visual Studio 2019/2022/2024

echo ==========================================
echo  SoloPool Miner v1.0.4 Build Script
echo  Universal GPU Compatibility Edition
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

echo Building SoloPool Miner with multi-GPU support...
echo Supported: RTX 2000/3000/4000/5000 series (CUDA), older GPUs use OpenCL
echo.

REM Build with CUDA multi-architecture support
REM CUDA 13.1 minimum is sm_75 (Turing)
REM Older GPUs (GTX 1000 and below) will use OpenCL fallback
REM sm_75 = Turing (RTX 2000 series)
REM sm_86 = Ampere (RTX 3000 series)
REM sm_89 = Ada Lovelace (RTX 4000 series)
REM compute_90 = PTX for future GPUs (Blackwell/RTX 5000+)

nvcc -O3 ^
     -gencode arch=compute_75,code=sm_75 ^
     -gencode arch=compute_86,code=sm_86 ^
     -gencode arch=compute_89,code=sm_89 ^
     -gencode arch=compute_90,code=compute_90 ^
     -allow-unsupported-compiler ^
     -ccbin "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64" ^
     -Xlinker /SUBSYSTEM:WINDOWS ^
     -o SoloPoolMiner.exe solopool_miner_v1.0.4.cu ^
     -lws2_32 -lcomctl32 -lgdi32 -luser32 -lshell32 -lnvml -lOpenCL

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ==========================================
    echo  BUILD SUCCESSFUL!
    echo  Output: SoloPoolMiner.exe
    echo ==========================================
    echo.
    echo GPU Support (CUDA):
    echo   - NVIDIA RTX 2000 series (Turing)
    echo   - NVIDIA RTX 3000 series (Ampere)
    echo   - NVIDIA RTX 4000 series (Ada)
    echo   - NVIDIA RTX 5000+ series (Blackwell+, via PTX)
    echo.
    echo GPU Support (OpenCL fallback):
    echo   - NVIDIA GTX 900/1000 series
    echo   - AMD GPUs
    echo.
) else (
    echo.
    echo ==========================================
    echo  BUILD FAILED!
    echo  Check error messages above.
    echo ==========================================
    echo.
    echo Common fixes:
    echo   - Install Visual Studio Build Tools
    echo   - Update CUDA Toolkit
    echo   - Check PATH includes CUDA bin directory
)

pause
