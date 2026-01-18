# SoloPool Miner v1.0.4

A high-performance Bitcoin solo mining application with GUI for [SoloPool.com](https://solopool.com).

![SoloPool Miner Screenshot](screenshot.png)

## Features

- **Full Windows GUI** - Easy-to-use interface with real-time statistics
- **NVIDIA GPU Mining** - CUDA-accelerated SHA256d (~2+ GH/s on RTX 3070)
- **AMD/Intel GPU Mining** - OpenCL support for non-NVIDIA GPUs
- **CPU Mining** - SHA256-NI hardware acceleration (Intel/AMD)
- **Power Management** - Adjustable power sliders (10-100%) for CPU and GPU
- **Red Zone Mode** - Push past 80% for maximum hashrate (with warnings)
- **Real-time Graphs** - Live GPU/CPU utilization monitoring
- **Address Persistence** - Saves your BTC address between sessions
- **Log File** - All activity logged to `solopool_miner.log`
- **Auto-connect** - Hardcoded to stratum.solopool.com:3333

## Pool Fee

**SoloPool.com charges a 2% fee only when you find a block.** There are no fees for mining or submitting shares - you only pay if you win!

| Event | Fee |
|-------|-----|
| Mining/Shares | **FREE** |
| Block Found | **2%** of block reward |

## Requirements

### For Running Pre-built Binary
- Windows 10/11 (64-bit)
- NVIDIA GPU with recent drivers (for CUDA mining)
- Or AMD/Intel GPU with OpenCL support

### For Building from Source
- [NVIDIA CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit) (v12.0 or later recommended)
- Visual Studio 2019, 2022, or 2024 (for MSVC compiler)
- OpenCL SDK (usually included with GPU drivers)

## Quick Start

1. Download the latest release ([https://github.com/Sledge0001/SoloPool-Miner/blob/main/SoloPoolMiner.exe))](https://github.com/Sledge0001/SoloPool-Miner/blob/main/SoloPoolMiner.exe)
2. Run `SoloPoolMiner.exe`
3. Enter your Bitcoin address and worker name (e.g., `bc1qYourAddress.WorkerName`)
4. Adjust CPU/GPU power sliders as desired
5. Click **"Generate Coins"** to start mining!

## Building from Source

### Windows (Multi-GPU Support)

Build for all supported NVIDIA GPUs (RTX 2000/3000/4000/5000 series):

```batch
nvcc -O3 ^
     -gencode arch=compute_75,code=sm_75 ^
     -gencode arch=compute_86,code=sm_86 ^
     -gencode arch=compute_89,code=sm_89 ^
     -gencode arch=compute_90,code=compute_90 ^
     -allow-unsupported-compiler ^
     -ccbin "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.xx.xxxxx\bin\Hostx64\x64" ^
     -Xlinker /SUBSYSTEM:WINDOWS ^
     -o SoloPoolMiner.exe solopool_miner_v1.0.4.cu ^
     -lws2_32 -lcomctl32 -lgdi32 -luser32 -lshell32 -lnvml -lOpenCL
```

**Note:** Adjust the `-ccbin` path to match your Visual Studio installation.

### GPU Architecture Support

| Architecture | GPUs | Support |
|--------------|------|---------|
| sm_75 | RTX 2000 series (Turing) | CUDA |
| sm_86 | RTX 3000 series (Ampere) | CUDA |
| sm_89 | RTX 4000 series (Ada) | CUDA |
| compute_90 | RTX 5000+ series (Blackwell) | CUDA (PTX) |
| GTX 900/1000 | Maxwell/Pascal | OpenCL fallback |
| AMD GPUs | All with OpenCL | OpenCL |

### Build Script

Use the included `build_v1.0.4.bat` for easy compilation.

## Usage

### Power Settings

| Range | Description |
|-------|-------------|
| 10-50% | Light mining, minimal system impact |
| 50-80% | Balanced mining, moderate heat |
| 80-100% | **RED ZONE** - Maximum hashrate, runs HOT! |

When entering the Red Zone (>80%), you'll see a warning dialog. Your hardware will run at maximum capacity - **monitor your temperatures!**

### Statistics Display

```
CPU: 85.00 MH/s | GPU: 2200.00 MH/s | Total: 2285.00 MH/s
CPU: 5/0 | GPU: 12/0 | Total: 17/0 (100.0%) | SPM: 8.5
Best: 45000.0 / 47000.0 | Uptime: 01:23:45 | Diff: 3 | Suggested: 3
```

- **MH/s** - Megahashes per second
- **X/Y** - Accepted/Rejected shares
- **SPM** - Shares per minute
- **Best** - Highest difficulty share found (session / all-time)
- **Diff** - Current pool difficulty
- **Suggested** - Auto-adjusted difficulty for optimal SPM

### Configuration Files

| File | Purpose |
|------|---------|
| `solopool_miner.log` | Activity log (persists across sessions) |
| `solopool_config.txt` | Saved BTC address and password |
| `bestshare.txt` | All-time best share record |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Win32 GUI (WndProc)                  │
├─────────────────────────────────────────────────────────┤
│  Stratum Thread  │  CPU Threads  │  GPU Thread(s)      │
│  (networking)    │  (SHA256d)    │  (CUDA/OpenCL)      │
├─────────────────────────────────────────────────────────┤
│              Shared State (thread-safe)                 │
│         job data, nonces, statistics, results          │
└─────────────────────────────────────────────────────────┘
```

## Solo Mining Odds

**Important:** Solo mining Bitcoin is essentially a lottery. With current network difficulty (~90T), even a powerful GPU has astronomically low odds of finding a block.

| Hashrate | Time to Find Block (avg) |
|----------|--------------------------|
| 1 GH/s | ~2,700 years |
| 100 GH/s | ~27 years |
| 1 TH/s | ~2.7 years |

**Why solo mine anyway?**
- Educational/hobby purposes
- Supporting network decentralization  
- The dream of hitting a ~3.125 BTC block reward
- Low pool fee (2% only if you win!)

## Troubleshooting

### "No CUDA devices found"
- Ensure NVIDIA drivers are up to date
- Verify GPU supports CUDA (GTX 900+ series)
- Older GPUs (GTX 1000 and below) will use OpenCL fallback

### "No GPU devices found"
- For AMD: Install AMD Adrenalin drivers with OpenCL
- For Intel: Install Intel Graphics drivers with OpenCL

### Low hashrate
- Increase power slider
- Ensure no thermal throttling (check GPU temp)
- Close other GPU-intensive applications

### Connection issues
- Check internet connection
- Verify firewall allows outbound port 3333
- Try restarting the miner

## Changelog

### v1.0.4
- Added address persistence (saves between sessions)
- Improved power scaling for 80-100% range
- Fixed log not updating after stop/restart
- Multi-GPU build support (RTX 2000-5000 series)
- Batched log updates for better UI responsiveness
- Gradual difficulty adjustments

### v1.0.0
- Initial release

## ⚠️ DISCLAIMER

**USE THIS SOFTWARE AT YOUR OWN RISK.**

1. **No Warranty**: This software is provided "AS IS" without warranty of any kind, express or implied. The authors are not responsible for any damages, losses, or other liabilities arising from its use.

2. **Hardware Risks**: Mining cryptocurrency can put significant stress on your hardware. Running at high power levels (especially in "Red Zone" mode) can cause:
   - Increased electricity consumption and costs
   - Elevated temperatures that may reduce component lifespan
   - Potential hardware damage if cooling is inadequate
   - System instability

3. **Financial Risks**: 
   - Solo mining has extremely low odds of finding a block
   - Electricity costs will almost certainly exceed any rewards
   - Cryptocurrency values are volatile
   - This is NOT a get-rich-quick scheme

4. **Security**: 
   - Only download from official sources
   - Verify checksums when available
   - Never share your private keys

5. **Legal Compliance**: Ensure cryptocurrency mining is legal in your jurisdiction. You are responsible for any applicable taxes or regulations.

**By using this software, you acknowledge that you understand and accept these risks.**

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Links

- **Pool**: [https://solopool.com](https://www.solopool.com)
- **Stratum**: stratum.solopool.com:3333
- **Support**: [SoloPool Discord/Support] https://discord.gg/MskYhewU

## Acknowledgments

- SoloPool.com for providing solo mining infrastructure
- The Bitcoin community

---

*Happy mining! May the hashes be ever in your favor.* 🎰⛏️
