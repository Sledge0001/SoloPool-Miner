/*******************************************************************************
 * SoloPool.Com Miner v1.0.4 - CUDA + OpenCL + CPU Hybrid WITH GUI
 * 
 * A Bitcoin solo mining application for SoloPool.com
 * Repository: https://github.com/SoloPool-Org/solopool-miner
 * 
 * Copyright (c) 2025 SoloPool.com
 * Licensed under the MIT License - see LICENSE file for details
 * 
 * FEATURES:
 *   - Full Win32 GUI with power management
 *   - CUDA support for NVIDIA GPUs (preferred, fastest)
 *   - OpenCL support for AMD/Intel GPUs  
 *   - CPU mining with SHA256-NI acceleration (Intel/AMD)
 *   - Power sliders (10-100%) with Red Zone warning (80%+)
 *   - Real-time GPU/CPU utilization graphs
 *   - Variable Difficulty (Vardiff) auto-adjustment
 *   - Log file output (solopool_miner.log)
 *   - Hardcoded to stratum.solopool.com:3333
 * 
 * BUILD (NVIDIA with CUDA - recommended):
 *   nvcc -O3 -arch=sm_86 -allow-unsupported-compiler -Xlinker /SUBSYSTEM:WINDOWS ^
 *        -o SoloPoolMiner.exe solopool_miner.cu ^
 *        -lws2_32 -lcomctl32 -lgdi32 -luser32 -lshell32 -lnvml -lOpenCL
 * 
 * DISCLAIMER: Mining cryptocurrency involves risk. This software is provided
 * "as is" without warranty. Use at your own risk. See README.md for details.
 ******************************************************************************/

// =============================================================================
// SECTION 1: Windows and Standard Headers
// =============================================================================
#define _WIN32_WINNT 0x0601
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <commctrl.h>
#include <shellapi.h>
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(linker, "/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <time.h>
#include <math.h>
#include <intrin.h>
#include <immintrin.h>
#include <process.h>

// CUDA headers (for NVIDIA GPUs)
#ifndef OPENCL_ONLY
#include <cuda_runtime.h>
#endif

// OpenCL headers (for AMD/Intel GPUs)
#define CL_TARGET_OPENCL_VERSION 120
#include <CL/cl.h>

// NVML for NVIDIA GPU monitoring (optional)
#ifndef OPENCL_ONLY
#include <nvml.h>
#endif

#define bswap_32(x) ((((x)&0xff000000u)>>24)|(((x)&0x00ff0000u)>>8)|(((x)&0x0000ff00u)<<8)|(((x)&0x000000ffu)<<24))

// =============================================================================
// SECTION 2: Constants - HARDCODED POOL CONFIGURATION
// =============================================================================

// HARDCODED POOL - SOLOPOOL.COM
#define POOL_HOST           "stratum.solopool.com"
#define POOL_PORT           3333
#define POOL_DISPLAY        "stratum.solopool.com:3333"

// UTILIZATION SETTINGS
#define MAX_UTILIZATION_PERCENT 100  // v1.0.0: Extended to 100% for Red Zone
#define REDZONE_THRESHOLD       80   // Above this = Red Zone (max performance)
#define DEFAULT_CPU_PERCENT     10
#define DEFAULT_GPU_PERCENT     10
#define MIN_UTILIZATION_PERCENT 10

// Mining constants
#define MAX_GPU_DEVICES 8
#define MAX_CPU_THREADS 64
#define GPU_BATCH_SIZE (1 << 26)  // 64M hashes per batch
#define MAX_RESULTS 256
#define BEST_SHARE_FILE "bestshare.txt"
#define CONFIG_FILE "solopool_config.txt"
#define TARGET_SPM 18.0
#define SPM_HIGH_THRESHOLD 25.0
#define SPM_LOW_THRESHOLD 7.0
#define SPM_REACT_DELAY 60
#define SPM_REACT_COOLDOWN 30
#define DIFF_ADJUST_INTERVAL 300
#define MIN_DIFF 1
#define MAX_DIFF 65536

// Nonce partitioning
#define CPU_NONCE_START 0x00000000
#define CPU_NONCE_END   0x7FFFFFFF
#define GPU_NONCE_START 0x80000000
#define GPU_NONCE_END   0xFFFFFFFF

// GUI Constants - v1.0.0: Proper log window size
#define WINDOW_WIDTH    900
#define WINDOW_HEIGHT   880
#define LOG_HEIGHT      300

// Power scaling calibration v1.0.0 - WITH RED ZONE SUPPORT
//
// SAFE ZONE (10-80%): Throttled for cooler temps
//   10% â†’ ~10% actual utilization
//   50% â†’ ~50% actual utilization
//   80% â†’ ~80% actual utilization
//
// RED ZONE (80-100%): MAXIMUM PERFORMANCE - runs HOT!
//   90% â†’ ~95% actual utilization
//   100% â†’ 100% actual (zero throttling, max hashrate)
//
// CPU: Thread limiting + delay-based throttling
#define CPU_THREAD_SCALE    1.2     // Thread multiplier
#define CPU_DELAY_AT_MIN    120     // ms delay at 10% power
#define CPU_DELAY_AT_80     20      // ms delay at 80% power
#define CPU_DELAY_AT_MAX    0       // ms delay at 100% power (RED ZONE)

// GPU: Batch scaling + delay
#define GPU_BATCH_SCALE_MIN   0.12  // At 10% power
#define GPU_BATCH_SCALE_80    0.85  // At 80% power
#define GPU_BATCH_SCALE_MAX   1.0   // At 100% power (RED ZONE - full batches!)
#define GPU_DELAY_AT_MIN      200   // ms delay at 10% power
#define GPU_DELAY_AT_80       20    // ms delay at 80% power  
#define GPU_DELAY_AT_MAX      0     // ms delay at 100% power (RED ZONE - no delay!)

// GPU Graph Constants
#define GRAPH_WIDTH         180
#define GRAPH_HEIGHT        50
#define GRAPH_HISTORY_SIZE  60      // 60 seconds of history
#define GRAPH_SAMPLE_MS     1000    // Sample every 1 second

// Control IDs
#define ID_EDIT_ADDRESS     1001
#define ID_EDIT_PASSWORD    1002
#define ID_CHECK_CPU        1003
#define ID_CHECK_GPU        1004
#define ID_SLIDER_CPU       1005
#define ID_SLIDER_GPU       1006
#define ID_LABEL_CPU_PCT    1007
#define ID_LABEL_GPU_PCT    1008
#define ID_BTN_START        1009
#define ID_BTN_STOP         1010
#define ID_BTN_LINK         1011
#define ID_EDIT_LOG         1012
#define ID_STATIC_STATS     1013
#define ID_GPU_GRAPH        1014
#define ID_CPU_GRAPH        1015
#define ID_TIMER_UPDATE     2001
#define ID_TIMER_GRAPH      2002
#define ID_TIMER_LOG        2003

#define LOG_UPDATE_INTERVAL_MS  100
#define LOG_BUFFER_SIZE         8192

// =============================================================================
// SECTION 3a: OpenCL Kernel Source (for AMD/Intel GPUs)
// =============================================================================

static const char* g_openclKernelSource = R"CL(
// SHA256 constants
__constant uint K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

#define ROTR(x,n) (((x)>>(n))|((x)<<(32-(n))))
#define CH(x,y,z) (((x)&(y))^(~(x)&(z)))
#define MAJ(x,y,z) (((x)&(y))^((x)&(z))^((y)&(z)))
#define EP0(x) (ROTR(x,2)^ROTR(x,13)^ROTR(x,22))
#define EP1(x) (ROTR(x,6)^ROTR(x,11)^ROTR(x,25))
#define SIG0(x) (ROTR(x,7)^ROTR(x,18)^((x)>>3))
#define SIG1(x) (ROTR(x,17)^ROTR(x,19)^((x)>>10))

inline uint bswap32_cl(uint x) {
    return ((x >> 24) & 0xFF) | ((x >> 8) & 0xFF00) | 
           ((x << 8) & 0xFF0000) | ((x << 24) & 0xFF000000);
}

__kernel void sha256d_opencl_kernel(
    __global const uint* midstate,
    __global const uint* tail,
    uint nonce_base,
    __global uint* results
) {
    uint nonce = nonce_base + get_global_id(0);
    
    // Load midstate
    uint H0 = midstate[0], H1 = midstate[1], H2 = midstate[2], H3 = midstate[3];
    uint H4 = midstate[4], H5 = midstate[5], H6 = midstate[6], H7 = midstate[7];
    
    uint W[64];
    
    // Second block: tail + nonce + padding
    W[0] = tail[0]; W[1] = tail[1]; W[2] = tail[2];
    W[3] = nonce;
    W[4] = 0x80000000;
    W[5] = 0; W[6] = 0; W[7] = 0; W[8] = 0; W[9] = 0;
    W[10] = 0; W[11] = 0; W[12] = 0; W[13] = 0; W[14] = 0;
    W[15] = 640;
    
    for (int i = 16; i < 64; i++) {
        W[i] = SIG1(W[i-2]) + W[i-7] + SIG0(W[i-15]) + W[i-16];
    }
    
    uint a = H0, b = H1, c = H2, d = H3;
    uint e = H4, f = H5, g = H6, h = H7;
    
    for (int i = 0; i < 64; i++) {
        uint t1 = h + EP1(e) + CH(e,f,g) + K[i] + W[i];
        uint t2 = EP0(a) + MAJ(a,b,c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    
    H0 += a; H1 += b; H2 += c; H3 += d;
    H4 += e; H5 += f; H6 += g; H7 += h;
    
    // Second SHA256 on the 32-byte result
    W[0] = H0; W[1] = H1; W[2] = H2; W[3] = H3;
    W[4] = H4; W[5] = H5; W[6] = H6; W[7] = H7;
    W[8] = 0x80000000;
    W[9] = 0; W[10] = 0; W[11] = 0; W[12] = 0; W[13] = 0; W[14] = 0;
    W[15] = 256;
    
    for (int i = 16; i < 64; i++) {
        W[i] = SIG1(W[i-2]) + W[i-7] + SIG0(W[i-15]) + W[i-16];
    }
    
    a = 0x6a09e667; b = 0xbb67ae85; c = 0x3c6ef372; d = 0xa54ff53a;
    e = 0x510e527f; f = 0x9b05688c; g = 0x1f83d9ab; h = 0x5be0cd19;
    
    for (int i = 0; i < 64; i++) {
        uint t1 = h + EP1(e) + CH(e,f,g) + K[i] + W[i];
        uint t2 = EP0(a) + MAJ(a,b,c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    
    uint final_h = 0x5be0cd19 + h;
    uint le_h = bswap32_cl(final_h);
    
    // Check if hash meets minimum difficulty (last 4 bytes zero)
    if (le_h == 0) {
        uint idx = atomic_add(&results[0], 1);
        if (idx < 255) {
            results[1 + idx] = nonce;
        }
    }
}
)CL";

// =============================================================================
// SECTION 3b: CUDA Kernel - Optimized SHA256d with __byte_perm (NVIDIA only)
// =============================================================================

#ifndef OPENCL_ONLY
__constant__ uint32_t d_K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

__device__ __forceinline__ uint32_t cuda_bswap32(uint32_t x) {
    return __byte_perm(x, 0, 0x0123);
}

__device__ __forceinline__ uint32_t ROTR(uint32_t x, int n) {
    return (x >> n) | (x << (32 - n));
}

__device__ __forceinline__ uint32_t CH(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) ^ (~x & z);
}

__device__ __forceinline__ uint32_t MAJ(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) ^ (x & z) ^ (y & z);
}

__device__ __forceinline__ uint32_t EP0(uint32_t x) {
    return ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22);
}

__device__ __forceinline__ uint32_t EP1(uint32_t x) {
    return ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25);
}

__device__ __forceinline__ uint32_t SIG0(uint32_t x) {
    return ROTR(x, 7) ^ ROTR(x, 18) ^ (x >> 3);
}

__device__ __forceinline__ uint32_t SIG1(uint32_t x) {
    return ROTR(x, 17) ^ ROTR(x, 19) ^ (x >> 10);
}

// Main CUDA kernel for SHA256d mining (LOOSE filter - CPU verifies exact diff)
__global__ void sha256d_cuda_kernel(
    const uint32_t* __restrict__ midstate,
    const uint32_t* __restrict__ tail,
    uint32_t nonce_base,
    uint32_t* __restrict__ results
) {
    uint32_t nonce = nonce_base + blockIdx.x * blockDim.x + threadIdx.x;
    
    uint32_t H0 = midstate[0], H1 = midstate[1], H2 = midstate[2], H3 = midstate[3];
    uint32_t H4 = midstate[4], H5 = midstate[5], H6 = midstate[6], H7 = midstate[7];
    
    uint32_t W[64];
    
    // First SHA256: Complete the second block (bytes 64-79 + padding)
    W[0] = tail[0]; W[1] = tail[1]; W[2] = tail[2]; W[3] = nonce;
    W[4] = 0x80000000;
    W[5] = 0; W[6] = 0; W[7] = 0; W[8] = 0; W[9] = 0;
    W[10] = 0; W[11] = 0; W[12] = 0; W[13] = 0; W[14] = 0;
    W[15] = 640;
    
    #pragma unroll
    for (int i = 16; i < 64; i++) {
        W[i] = SIG1(W[i-2]) + W[i-7] + SIG0(W[i-15]) + W[i-16];
    }
    
    uint32_t a = H0, b = H1, c = H2, d = H3;
    uint32_t e = H4, f = H5, g = H6, h = H7;
    
    #pragma unroll
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + EP1(e) + CH(e, f, g) + d_K[i] + W[i];
        uint32_t t2 = EP0(a) + MAJ(a, b, c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    
    H0 += a; H1 += b; H2 += c; H3 += d;
    H4 += e; H5 += f; H6 += g; H7 += h;
    
    // Second SHA256
    W[0] = H0; W[1] = H1; W[2] = H2; W[3] = H3;
    W[4] = H4; W[5] = H5; W[6] = H6; W[7] = H7;
    W[8] = 0x80000000;
    W[9] = 0; W[10] = 0; W[11] = 0; W[12] = 0; W[13] = 0; W[14] = 0;
    W[15] = 256;
    
    #pragma unroll
    for (int i = 16; i < 64; i++) {
        W[i] = SIG1(W[i-2]) + W[i-7] + SIG0(W[i-15]) + W[i-16];
    }
    
    a = 0x6a09e667; b = 0xbb67ae85; c = 0x3c6ef372; d = 0xa54ff53a;
    e = 0x510e527f; f = 0x9b05688c; g = 0x1f83d9ab; h = 0x5be0cd19;
    
    #pragma unroll
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + EP1(e) + CH(e, f, g) + d_K[i] + W[i];
        uint32_t t2 = EP0(a) + MAJ(a, b, c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    
    uint32_t final_H7 = 0x5be0cd19 + h;
    uint32_t le_H7 = cuda_bswap32(final_H7);
    
    // LOOSE FILTER: 4 zero bytes (diff >= ~1)
    if (le_H7 == 0) {
        uint32_t idx = atomicAdd(&results[0], 1);
        if (idx < 255) {
            results[1 + idx] = nonce;
        }
    }
}
#endif // OPENCL_ONLY

// =============================================================================
// SECTION 4: Host-side SHA256 Implementation
// =============================================================================

static const uint32_t sha256_k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

static const uint32_t sha256_init[8] = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
};

#define ROR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define HOST_CH(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define HOST_MAJ(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define HOST_EP0(x) (ROR32(x, 2) ^ ROR32(x, 13) ^ ROR32(x, 22))
#define HOST_EP1(x) (ROR32(x, 6) ^ ROR32(x, 11) ^ ROR32(x, 25))
#define HOST_SIG0(x) (ROR32(x, 7) ^ ROR32(x, 18) ^ ((x) >> 3))
#define HOST_SIG1(x) (ROR32(x, 17) ^ ROR32(x, 19) ^ ((x) >> 10))

static inline uint32_t be32dec(const void *pp) {
    const uint8_t *p = (const uint8_t *)pp;
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static inline void be32enc(void *pp, uint32_t x) {
    uint8_t *p = (uint8_t *)pp;
    p[0] = (x >> 24) & 0xff; p[1] = (x >> 16) & 0xff;
    p[2] = (x >> 8) & 0xff; p[3] = x & 0xff;
}

static void sha256_transform(uint32_t *state, const uint8_t *block) {
    uint32_t W[64], a, b, c, d, e, f, g, h, t1, t2;
    for (int i = 0; i < 16; i++) W[i] = be32dec(block + i * 4);
    for (int i = 16; i < 64; i++) W[i] = HOST_SIG1(W[i-2]) + W[i-7] + HOST_SIG0(W[i-15]) + W[i-16];
    a = state[0]; b = state[1]; c = state[2]; d = state[3];
    e = state[4]; f = state[5]; g = state[6]; h = state[7];
    for (int i = 0; i < 64; i++) {
        t1 = h + HOST_EP1(e) + HOST_CH(e, f, g) + sha256_k[i] + W[i];
        t2 = HOST_EP0(a) + HOST_MAJ(a, b, c);
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

static void sha256(const uint8_t *data, size_t len, uint8_t *hash) {
    uint32_t state[8];
    uint8_t block[64];
    memcpy(state, sha256_init, sizeof(state));
    const uint8_t *p = data;
    size_t rem = len;
    while (rem >= 64) { sha256_transform(state, p); p += 64; rem -= 64; }
    memset(block, 0, 64);
    memcpy(block, p, rem);
    block[rem] = 0x80;
    if (rem >= 56) { sha256_transform(state, block); memset(block, 0, 64); }
    uint64_t bits = (uint64_t)len * 8;
    for (int i = 0; i < 8; i++) block[56 + i] = (bits >> (56 - i * 8)) & 0xff;
    sha256_transform(state, block);
    for (int i = 0; i < 8; i++) be32enc(hash + i * 4, state[i]);
}

static void sha256d(const uint8_t *data, size_t len, uint8_t *hash) {
    uint8_t tmp[32];
    sha256(data, len, tmp);
    sha256(tmp, 32, hash);
}

// =============================================================================
// SECTION 5: SHA256-NI Hardware Acceleration
// =============================================================================

static int g_has_sha_ni = 0;

static void detect_cpu_features(void) {
    int cpuinfo[4] = {0};
    __cpuid(cpuinfo, 0);
    if (cpuinfo[0] >= 7) {
        __cpuidex(cpuinfo, 7, 0);
        g_has_sha_ni = (cpuinfo[1] >> 29) & 1;
    }
}

static void sha256d_80_shani(const uint8_t *input, uint8_t *hash) {
    __m128i STATE0, STATE1, MSG, TMP, MSG0, MSG1, MSG2, MSG3, ABEF_SAVE, CDGH_SAVE;
    const __m128i MASK = _mm_set_epi64x(0x0c0d0e0f08090a0bULL, 0x0405060700010203ULL);
    
    TMP = _mm_loadu_si128((const __m128i*)&sha256_init[0]);
    STATE1 = _mm_loadu_si128((const __m128i*)&sha256_init[4]);
    TMP = _mm_shuffle_epi32(TMP, 0xB1);
    STATE1 = _mm_shuffle_epi32(STATE1, 0x1B);
    STATE0 = _mm_alignr_epi8(TMP, STATE1, 8);
    STATE1 = _mm_blend_epi16(STATE1, TMP, 0xF0);
    
    MSG0 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(input + 0)), MASK);
    MSG = _mm_add_epi32(MSG0, _mm_set_epi64x(0xE9B5DBA5B5C0FBCFULL, 0x71374491428A2F98ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG1 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(input + 16)), MASK);
    MSG = _mm_add_epi32(MSG1, _mm_set_epi64x(0xAB1C5ED5923F82A4ULL, 0x59F111F13956C25BULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG0 = _mm_sha256msg1_epu32(MSG0, MSG1);
    
    MSG2 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(input + 32)), MASK);
    MSG = _mm_add_epi32(MSG2, _mm_set_epi64x(0x550C7DC3243185BEULL, 0x12835B01D807AA98ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG1 = _mm_sha256msg1_epu32(MSG1, MSG2);
    
    MSG3 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(input + 48)), MASK);
    MSG = _mm_add_epi32(MSG3, _mm_set_epi64x(0xC19BF1749BDC06A7ULL, 0x80DEB1FE72BE5D74ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG3, MSG2, 4);
    MSG0 = _mm_add_epi32(MSG0, TMP);
    MSG0 = _mm_sha256msg2_epu32(MSG0, MSG3);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG2 = _mm_sha256msg1_epu32(MSG2, MSG3);
    
    #define SHA256_SHANI_ROUND(m0,m1,m2,m3,k) { \
        MSG = _mm_add_epi32(m0, k); \
        STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG); \
        TMP = _mm_alignr_epi8(m0, m3, 4); \
        m1 = _mm_add_epi32(m1, TMP); \
        m1 = _mm_sha256msg2_epu32(m1, m0); \
        MSG = _mm_shuffle_epi32(MSG, 0x0E); \
        STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG); \
        m3 = _mm_sha256msg1_epu32(m3, m0); \
    }
    
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x240CA1CC0FC19DC6ULL, 0xEFBE4786E49B69C1ULL));
    SHA256_SHANI_ROUND(MSG1, MSG2, MSG3, MSG0, _mm_set_epi64x(0x76F988DA5CB0A9DCULL, 0x4A7484AA2DE92C6FULL));
    SHA256_SHANI_ROUND(MSG2, MSG3, MSG0, MSG1, _mm_set_epi64x(0xBF597FC7B00327C8ULL, 0xA831C66D983E5152ULL));
    SHA256_SHANI_ROUND(MSG3, MSG0, MSG1, MSG2, _mm_set_epi64x(0x1429296706CA6351ULL, 0xD5A79147C6E00BF3ULL));
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x53380D134D2C6DFCULL, 0x2E1B213827B70A85ULL));
    SHA256_SHANI_ROUND(MSG1, MSG2, MSG3, MSG0, _mm_set_epi64x(0x92722C8581C2C92EULL, 0x766A0ABB650A7354ULL));
    SHA256_SHANI_ROUND(MSG2, MSG3, MSG0, MSG1, _mm_set_epi64x(0xC76C51A3C24B8B70ULL, 0xA81A664BA2BFE8A1ULL));
    SHA256_SHANI_ROUND(MSG3, MSG0, MSG1, MSG2, _mm_set_epi64x(0x106AA070F40E3585ULL, 0xD6990624D192E819ULL));
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x34B0BCB52748774CULL, 0x1E376C0819A4C116ULL));
    
    MSG = _mm_add_epi32(MSG1, _mm_set_epi64x(0x682E6FF35B9CCA4FULL, 0x4ED8AA4A391C0CB3ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG1, MSG0, 4); MSG2 = _mm_add_epi32(MSG2, TMP);
    MSG2 = _mm_sha256msg2_epu32(MSG2, MSG1);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG = _mm_add_epi32(MSG2, _mm_set_epi64x(0x8CC7020884C87814ULL, 0x78A5636F748F82EEULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG2, MSG1, 4); MSG3 = _mm_add_epi32(MSG3, TMP);
    MSG3 = _mm_sha256msg2_epu32(MSG3, MSG2);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG = _mm_add_epi32(MSG3, _mm_set_epi64x(0xC67178F2BEF9A3F7ULL, 0xA4506CEB90BEFFFAULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    TMP = _mm_loadu_si128((const __m128i*)&sha256_init[0]);
    __m128i TMP_STATE1 = _mm_loadu_si128((const __m128i*)&sha256_init[4]);
    TMP = _mm_shuffle_epi32(TMP, 0xB1);
    TMP_STATE1 = _mm_shuffle_epi32(TMP_STATE1, 0x1B);
    __m128i TMP2 = _mm_alignr_epi8(TMP, TMP_STATE1, 8);
    TMP_STATE1 = _mm_blend_epi16(TMP_STATE1, TMP, 0xF0);
    STATE0 = _mm_add_epi32(STATE0, TMP2);
    STATE1 = _mm_add_epi32(STATE1, TMP_STATE1);
    
    ABEF_SAVE = STATE0;
    CDGH_SAVE = STATE1;
    
    uint8_t block2[64] = {0};
    memcpy(block2, input + 64, 16);
    block2[16] = 0x80;
    block2[62] = 0x02;
    block2[63] = 0x80;
    
    MSG0 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(block2 + 0)), MASK);
    MSG = _mm_add_epi32(MSG0, _mm_set_epi64x(0xE9B5DBA5B5C0FBCFULL, 0x71374491428A2F98ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG1 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(block2 + 16)), MASK);
    MSG = _mm_add_epi32(MSG1, _mm_set_epi64x(0xAB1C5ED5923F82A4ULL, 0x59F111F13956C25BULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG0 = _mm_sha256msg1_epu32(MSG0, MSG1);
    
    MSG2 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(block2 + 32)), MASK);
    MSG = _mm_add_epi32(MSG2, _mm_set_epi64x(0x550C7DC3243185BEULL, 0x12835B01D807AA98ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG1 = _mm_sha256msg1_epu32(MSG1, MSG2);
    
    MSG3 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(block2 + 48)), MASK);
    MSG = _mm_add_epi32(MSG3, _mm_set_epi64x(0xC19BF1749BDC06A7ULL, 0x80DEB1FE72BE5D74ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG3, MSG2, 4); MSG0 = _mm_add_epi32(MSG0, TMP);
    MSG0 = _mm_sha256msg2_epu32(MSG0, MSG3);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG2 = _mm_sha256msg1_epu32(MSG2, MSG3);
    
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x240CA1CC0FC19DC6ULL, 0xEFBE4786E49B69C1ULL));
    SHA256_SHANI_ROUND(MSG1, MSG2, MSG3, MSG0, _mm_set_epi64x(0x76F988DA5CB0A9DCULL, 0x4A7484AA2DE92C6FULL));
    SHA256_SHANI_ROUND(MSG2, MSG3, MSG0, MSG1, _mm_set_epi64x(0xBF597FC7B00327C8ULL, 0xA831C66D983E5152ULL));
    SHA256_SHANI_ROUND(MSG3, MSG0, MSG1, MSG2, _mm_set_epi64x(0x1429296706CA6351ULL, 0xD5A79147C6E00BF3ULL));
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x53380D134D2C6DFCULL, 0x2E1B213827B70A85ULL));
    SHA256_SHANI_ROUND(MSG1, MSG2, MSG3, MSG0, _mm_set_epi64x(0x92722C8581C2C92EULL, 0x766A0ABB650A7354ULL));
    SHA256_SHANI_ROUND(MSG2, MSG3, MSG0, MSG1, _mm_set_epi64x(0xC76C51A3C24B8B70ULL, 0xA81A664BA2BFE8A1ULL));
    SHA256_SHANI_ROUND(MSG3, MSG0, MSG1, MSG2, _mm_set_epi64x(0x106AA070F40E3585ULL, 0xD6990624D192E819ULL));
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x34B0BCB52748774CULL, 0x1E376C0819A4C116ULL));
    
    MSG = _mm_add_epi32(MSG1, _mm_set_epi64x(0x682E6FF35B9CCA4FULL, 0x4ED8AA4A391C0CB3ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG1, MSG0, 4); MSG2 = _mm_add_epi32(MSG2, TMP);
    MSG2 = _mm_sha256msg2_epu32(MSG2, MSG1);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG = _mm_add_epi32(MSG2, _mm_set_epi64x(0x8CC7020884C87814ULL, 0x78A5636F748F82EEULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG2, MSG1, 4); MSG3 = _mm_add_epi32(MSG3, TMP);
    MSG3 = _mm_sha256msg2_epu32(MSG3, MSG2);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG = _mm_add_epi32(MSG3, _mm_set_epi64x(0xC67178F2BEF9A3F7ULL, 0xA4506CEB90BEFFFAULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    STATE0 = _mm_add_epi32(STATE0, ABEF_SAVE);
    STATE1 = _mm_add_epi32(STATE1, CDGH_SAVE);
    ABEF_SAVE = STATE0;
    CDGH_SAVE = STATE1;
    
    uint8_t first_hash[64] = {0};
    TMP = _mm_shuffle_epi32(STATE0, 0x1B);
    STATE1 = _mm_shuffle_epi32(STATE1, 0xB1);
    STATE0 = _mm_blend_epi16(TMP, STATE1, 0xF0);
    STATE1 = _mm_alignr_epi8(STATE1, TMP, 8);
    _mm_storeu_si128((__m128i*)first_hash, _mm_shuffle_epi8(STATE0, MASK));
    _mm_storeu_si128((__m128i*)(first_hash + 16), _mm_shuffle_epi8(STATE1, MASK));
    first_hash[32] = 0x80;
    first_hash[62] = 0x01;
    first_hash[63] = 0x00;
    
    TMP = _mm_loadu_si128((const __m128i*)&sha256_init[0]);
    STATE1 = _mm_loadu_si128((const __m128i*)&sha256_init[4]);
    TMP = _mm_shuffle_epi32(TMP, 0xB1);
    STATE1 = _mm_shuffle_epi32(STATE1, 0x1B);
    STATE0 = _mm_alignr_epi8(TMP, STATE1, 8);
    STATE1 = _mm_blend_epi16(STATE1, TMP, 0xF0);
    
    MSG0 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(first_hash + 0)), MASK);
    MSG = _mm_add_epi32(MSG0, _mm_set_epi64x(0xE9B5DBA5B5C0FBCFULL, 0x71374491428A2F98ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG1 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(first_hash + 16)), MASK);
    MSG = _mm_add_epi32(MSG1, _mm_set_epi64x(0xAB1C5ED5923F82A4ULL, 0x59F111F13956C25BULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG0 = _mm_sha256msg1_epu32(MSG0, MSG1);
    
    MSG2 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(first_hash + 32)), MASK);
    MSG = _mm_add_epi32(MSG2, _mm_set_epi64x(0x550C7DC3243185BEULL, 0x12835B01D807AA98ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG1 = _mm_sha256msg1_epu32(MSG1, MSG2);
    
    MSG3 = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i*)(first_hash + 48)), MASK);
    MSG = _mm_add_epi32(MSG3, _mm_set_epi64x(0xC19BF1749BDC06A7ULL, 0x80DEB1FE72BE5D74ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG3, MSG2, 4); MSG0 = _mm_add_epi32(MSG0, TMP);
    MSG0 = _mm_sha256msg2_epu32(MSG0, MSG3);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    MSG2 = _mm_sha256msg1_epu32(MSG2, MSG3);
    
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x240CA1CC0FC19DC6ULL, 0xEFBE4786E49B69C1ULL));
    SHA256_SHANI_ROUND(MSG1, MSG2, MSG3, MSG0, _mm_set_epi64x(0x76F988DA5CB0A9DCULL, 0x4A7484AA2DE92C6FULL));
    SHA256_SHANI_ROUND(MSG2, MSG3, MSG0, MSG1, _mm_set_epi64x(0xBF597FC7B00327C8ULL, 0xA831C66D983E5152ULL));
    SHA256_SHANI_ROUND(MSG3, MSG0, MSG1, MSG2, _mm_set_epi64x(0x1429296706CA6351ULL, 0xD5A79147C6E00BF3ULL));
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x53380D134D2C6DFCULL, 0x2E1B213827B70A85ULL));
    SHA256_SHANI_ROUND(MSG1, MSG2, MSG3, MSG0, _mm_set_epi64x(0x92722C8581C2C92EULL, 0x766A0ABB650A7354ULL));
    SHA256_SHANI_ROUND(MSG2, MSG3, MSG0, MSG1, _mm_set_epi64x(0xC76C51A3C24B8B70ULL, 0xA81A664BA2BFE8A1ULL));
    SHA256_SHANI_ROUND(MSG3, MSG0, MSG1, MSG2, _mm_set_epi64x(0x106AA070F40E3585ULL, 0xD6990624D192E819ULL));
    SHA256_SHANI_ROUND(MSG0, MSG1, MSG2, MSG3, _mm_set_epi64x(0x34B0BCB52748774CULL, 0x1E376C0819A4C116ULL));
    
    MSG = _mm_add_epi32(MSG1, _mm_set_epi64x(0x682E6FF35B9CCA4FULL, 0x4ED8AA4A391C0CB3ULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG1, MSG0, 4); MSG2 = _mm_add_epi32(MSG2, TMP);
    MSG2 = _mm_sha256msg2_epu32(MSG2, MSG1);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG = _mm_add_epi32(MSG2, _mm_set_epi64x(0x8CC7020884C87814ULL, 0x78A5636F748F82EEULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    TMP = _mm_alignr_epi8(MSG2, MSG1, 4); MSG3 = _mm_add_epi32(MSG3, TMP);
    MSG3 = _mm_sha256msg2_epu32(MSG3, MSG2);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    MSG = _mm_add_epi32(MSG3, _mm_set_epi64x(0xC67178F2BEF9A3F7ULL, 0xA4506CEB90BEFFFAULL));
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);
    MSG = _mm_shuffle_epi32(MSG, 0x0E);
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);
    
    TMP = _mm_loadu_si128((const __m128i*)&sha256_init[0]);
    TMP_STATE1 = _mm_loadu_si128((const __m128i*)&sha256_init[4]);
    TMP = _mm_shuffle_epi32(TMP, 0xB1);
    TMP_STATE1 = _mm_shuffle_epi32(TMP_STATE1, 0x1B);
    TMP2 = _mm_alignr_epi8(TMP, TMP_STATE1, 8);
    TMP_STATE1 = _mm_blend_epi16(TMP_STATE1, TMP, 0xF0);
    STATE0 = _mm_add_epi32(STATE0, TMP2);
    STATE1 = _mm_add_epi32(STATE1, TMP_STATE1);
    
    TMP = _mm_shuffle_epi32(STATE0, 0x1B);
    STATE1 = _mm_shuffle_epi32(STATE1, 0xB1);
    STATE0 = _mm_blend_epi16(TMP, STATE1, 0xF0);
    STATE1 = _mm_alignr_epi8(STATE1, TMP, 8);
    _mm_storeu_si128((__m128i*)hash, _mm_shuffle_epi8(STATE0, MASK));
    _mm_storeu_si128((__m128i*)(hash + 16), _mm_shuffle_epi8(STATE1, MASK));
    
    #undef SHA256_SHANI_ROUND
}

static void sha256d_80_soft(const uint8_t *input, uint8_t *hash) {
    sha256d(input, 80, hash);
}

typedef void (*sha256d_80_func)(const uint8_t *data, uint8_t *hash);
static sha256d_80_func sha256d_80 = NULL;

// =============================================================================
// SECTION 6: Utility Functions
// =============================================================================

static inline void flip_32(uint32_t *dest, const uint32_t *src) {
    for (int i = 0; i < 8; i++) dest[i] = bswap_32(src[i]);
}

static inline void flip_80(uint32_t *dest, const uint32_t *src) {
    for (int i = 0; i < 20; i++) dest[i] = bswap_32(src[i]);
}

static int hex2bin(uint8_t *out, const char *hex, size_t len) {
    for (size_t i = 0; i < len; i++) {
        char c1 = hex[i * 2], c2 = hex[i * 2 + 1];
        uint8_t v1 = (c1 >= '0' && c1 <= '9') ? c1 - '0' :
                     (c1 >= 'a' && c1 <= 'f') ? c1 - 'a' + 10 :
                     (c1 >= 'A' && c1 <= 'F') ? c1 - 'A' + 10 : 0;
        uint8_t v2 = (c2 >= '0' && c2 <= '9') ? c2 - '0' :
                     (c2 >= 'a' && c2 <= 'f') ? c2 - 'a' + 10 :
                     (c2 >= 'A' && c2 <= 'F') ? c2 - 'A' + 10 : 0;
        out[i] = (v1 << 4) | v2;
    }
    return (int)len;
}

// =============================================================================
// SECTION 7: Global State
// =============================================================================

typedef struct {
    char job_id[128];
    char prevhash[65];
    char coinb1[1024];
    char coinb2[1024];
    char merkle_branches[32][65];
    int merkle_count;
    char version[9];
    char nbits[9];
    char ntime[9];
    int clean;
    uint8_t header[80];
    double job_difficulty;
} stratum_job_t;

typedef struct {
    SOCKET sock;
    char host[256];
    int port;
    char user[256];
    char pass[64];
    char extranonce1[32];
    int extranonce2_size;
    uint32_t extranonce2;
    stratum_job_t job;
    double difficulty;
    volatile int connected;
    volatile int subscribed;
    volatile int authorized;
    volatile int has_job;
    volatile int ready_to_submit;
    CRITICAL_SECTION cs;
} stratum_ctx_t;

// GPU types
typedef enum {
    GPU_TYPE_NONE = 0,
    GPU_TYPE_CUDA,
    GPU_TYPE_OPENCL
} gpu_type_t;

typedef struct {
    gpu_type_t type;            // CUDA or OpenCL
    char name[256];
    int device_id;
    int enabled;
    size_t max_threads;
    int multiprocessor_count;
    
    // CUDA resources (only used if type == GPU_TYPE_CUDA)
#ifndef OPENCL_ONLY
    uint32_t *d_midstate;
    uint32_t *d_tail;
    uint32_t *d_results;
#endif
    
    // OpenCL resources (only used if type == GPU_TYPE_OPENCL)
    cl_device_id cl_device;
    cl_context cl_ctx;
    cl_command_queue cl_queue;
    cl_program cl_program;
    cl_kernel cl_kernel;
    cl_mem cl_midstate;
    cl_mem cl_tail;
    cl_mem cl_results;
} gpu_device_t;

typedef struct {
    volatile int running;
    volatile uint64_t cpu_hashes;
    volatile uint64_t gpu_hashes;
    volatile uint32_t accepted;
    volatile uint32_t rejected;
    volatile uint32_t submitted;
    volatile uint32_t cpu_accepted;
    volatile uint32_t cpu_rejected;
    volatile uint32_t gpu_accepted;
    volatile uint32_t gpu_rejected;
    int cpu_threads;
    int cpu_threads_active;  // Actually running based on slider
    gpu_device_t gpus[MAX_GPU_DEVICES];
    int gpu_count;
    volatile double best_share_session;
    volatile double best_share_ever;
    char best_share_session_source[8];
    char best_share_ever_source[8];
    DWORD start_time;
    volatile uint32_t shares_last_minute[60];
    volatile int spm_index;
    volatile uint32_t accepted_at_last_adjust;
    DWORD last_diff_adjust_time;
    DWORD last_spm_react_time;
    volatile int current_suggested_diff;
    
    // GUI-controlled settings
    volatile int cpu_enabled;
    volatile int gpu_enabled;
    volatile int cpu_power_percent;  // 10-80
    volatile int gpu_power_percent;  // 10-80
    
    #define SUBMIT_TRACK_SIZE 256
    int submit_source[SUBMIT_TRACK_SIZE];
} miner_state_t;

static stratum_ctx_t g_stratum = {0};
static miner_state_t g_miner = {0};
static CRITICAL_SECTION g_csLog;

// =============================================================================
// SECTION 8: GUI Global Variables
// =============================================================================

static HWND g_hwnd = NULL;
static HWND g_hwndAddress = NULL;
static HWND g_hwndPassword = NULL;
static HWND g_hwndCheckCPU = NULL;
static HWND g_hwndCheckGPU = NULL;
static HWND g_hwndSliderCPU = NULL;
static HWND g_hwndSliderGPU = NULL;
static HWND g_hwndLabelCPU = NULL;
static HWND g_hwndLabelGPU = NULL;
static HWND g_hwndBtnStart = NULL;
static HWND g_hwndBtnStop = NULL;
static HWND g_hwndBtnLink = NULL;
static HWND g_hwndLog = NULL;
static HWND g_hwndStats = NULL;
static HWND g_hwndGpuGraph = NULL;
static HWND g_hwndCpuGraph = NULL;
static HFONT g_hFont = NULL;
static HFONT g_hFontBold = NULL;
static HFONT g_hFontMono = NULL;
static int g_nSystemCpuCount = 1;
static int g_nGpuCount = 0;

// v1.0.0: Red Zone tracking done via static locals in WM_HSCROLL handler

// GPU/CPU utilization history for graphs
static unsigned int g_gpuHistory[GRAPH_HISTORY_SIZE] = {0};
static unsigned int g_cpuHistory[GRAPH_HISTORY_SIZE] = {0};
static int g_historyIndex = 0;
static nvmlDevice_t g_nvmlDevice = NULL;
static int g_nvmlInitialized = 0;

// CPU usage tracking
static ULARGE_INTEGER g_lastCpuIdle = {0};
static ULARGE_INTEGER g_lastCpuKernel = {0};
static ULARGE_INTEGER g_lastCpuUser = {0};

static HANDLE g_hStratumThread = NULL;
static HANDLE g_hCPUThreads[MAX_CPU_THREADS] = {NULL};
static HANDLE g_hGPUThreads[MAX_GPU_DEVICES] = {NULL};

static char g_logBuffer[LOG_BUFFER_SIZE];
static int g_logBufferLen = 0;
static CRITICAL_SECTION g_csLogBuffer;

// =============================================================================
// SECTION 9: Best Share Persistence
// =============================================================================

static void load_best_share(void) {
    FILE *f = fopen(BEST_SHARE_FILE, "r");
    if (f) {
        char source[8] = "???";
        if (fscanf(f, "%lf %7s", &g_miner.best_share_ever, source) >= 1) {
            strncpy(g_miner.best_share_ever_source, source, 7);
            g_miner.best_share_ever_source[7] = '\0';
        }
        fclose(f);
    }
}

static void save_best_share(double diff, const char *source) {
    FILE *f = fopen(BEST_SHARE_FILE, "w");
    if (f) {
        fprintf(f, "%.2f %s\n", diff, source);
        fclose(f);
    }
}

static void update_best_share(double diff, const char *source) {
    if (diff > g_miner.best_share_session) {
        g_miner.best_share_session = diff;
        strncpy((char*)g_miner.best_share_session_source, source, 7);
    }
    if (diff > g_miner.best_share_ever) {
        g_miner.best_share_ever = diff;
        strncpy((char*)g_miner.best_share_ever_source, source, 7);
        save_best_share(diff, source);
    }
}

static void track_share_for_spm(void) {
    int idx = g_miner.spm_index % 60;
    g_miner.shares_last_minute[idx]++;
}

static double calculate_spm(void) {
    uint32_t total = 0;
    for (int i = 0; i < 60; i++) {
        total += g_miner.shares_last_minute[i];
    }
    return (double)total;
}

static void advance_spm_window(void) {
    g_miner.spm_index++;
    int idx = g_miner.spm_index % 60;
    g_miner.shares_last_minute[idx] = 0;
}

// =============================================================================
// SECTION 9a: Address Persistence
// =============================================================================

static void save_last_address(const char *address, const char *password) {
    FILE *f = fopen(CONFIG_FILE, "w");
    if (f) {
        fprintf(f, "address=%s\n", address);
        fprintf(f, "password=%s\n", password);
        fclose(f);
    }
}

static void load_last_address(char *address, size_t addr_size, char *password, size_t pass_size) {
    address[0] = '\0';
    strncpy(password, "x", pass_size - 1);
    password[pass_size - 1] = '\0';
    
    FILE *f = fopen(CONFIG_FILE, "r");
    if (f) {
        char line[512];
        while (fgets(line, sizeof(line), f)) {
            char *nl = strchr(line, '\n');
            if (nl) *nl = '\0';
            char *cr = strchr(line, '\r');
            if (cr) *cr = '\0';
            
            if (strncmp(line, "address=", 8) == 0) {
                strncpy(address, line + 8, addr_size - 1);
                address[addr_size - 1] = '\0';
            } else if (strncmp(line, "password=", 9) == 0) {
                strncpy(password, line + 9, pass_size - 1);
                password[pass_size - 1] = '\0';
            }
        }
        fclose(f);
    }
}

// =============================================================================
// SECTION 9b: GPU/CPU Utilization Monitoring for Graphs
// =============================================================================

static void init_nvml(void) {
    nvmlReturn_t result = nvmlInit();
    if (result == NVML_SUCCESS) {
        result = nvmlDeviceGetHandleByIndex(0, &g_nvmlDevice);
        if (result == NVML_SUCCESS) {
            g_nvmlInitialized = 1;
        }
    }
}

static void shutdown_nvml(void) {
    if (g_nvmlInitialized) {
        nvmlShutdown();
        g_nvmlInitialized = 0;
    }
}

static unsigned int get_gpu_utilization(void) {
    if (!g_nvmlInitialized || !g_nvmlDevice) return 0;
    
    nvmlUtilization_t util;
    nvmlReturn_t result = nvmlDeviceGetUtilizationRates(g_nvmlDevice, &util);
    if (result == NVML_SUCCESS) {
        return util.gpu;  // Returns 0-100
    }
    return 0;
}

static unsigned int get_cpu_utilization(void) {
    FILETIME idleTime, kernelTime, userTime;
    
    if (!GetSystemTimes(&idleTime, &kernelTime, &userTime)) {
        return 0;
    }
    
    ULARGE_INTEGER idle, kernel, user;
    idle.LowPart = idleTime.dwLowDateTime;
    idle.HighPart = idleTime.dwHighDateTime;
    kernel.LowPart = kernelTime.dwLowDateTime;
    kernel.HighPart = kernelTime.dwHighDateTime;
    user.LowPart = userTime.dwLowDateTime;
    user.HighPart = userTime.dwHighDateTime;
    
    // First call - just store values
    if (g_lastCpuIdle.QuadPart == 0) {
        g_lastCpuIdle = idle;
        g_lastCpuKernel = kernel;
        g_lastCpuUser = user;
        return 0;
    }
    
    ULONGLONG idleDiff = idle.QuadPart - g_lastCpuIdle.QuadPart;
    ULONGLONG kernelDiff = kernel.QuadPart - g_lastCpuKernel.QuadPart;
    ULONGLONG userDiff = user.QuadPart - g_lastCpuUser.QuadPart;
    
    g_lastCpuIdle = idle;
    g_lastCpuKernel = kernel;
    g_lastCpuUser = user;
    
    ULONGLONG total = kernelDiff + userDiff;
    if (total == 0) return 0;
    
    // kernel time includes idle time
    ULONGLONG busy = total - idleDiff;
    return (unsigned int)((busy * 100) / total);
}

static void sample_utilization(void) {
    g_gpuHistory[g_historyIndex] = get_gpu_utilization();
    g_cpuHistory[g_historyIndex] = get_cpu_utilization();
    g_historyIndex = (g_historyIndex + 1) % GRAPH_HISTORY_SIZE;
}

static void draw_utilization_graph(HDC hdc, RECT *rect, unsigned int *history, COLORREF lineColor, const char *label) {
    // Background - dark gray
    HBRUSH hBrushBg = CreateSolidBrush(RGB(30, 30, 30));
    FillRect(hdc, rect, hBrushBg);
    DeleteObject(hBrushBg);
    
    // Border
    HPEN hPenBorder = CreatePen(PS_SOLID, 1, RGB(100, 100, 100));
    HPEN hOldPen = (HPEN)SelectObject(hdc, hPenBorder);
    Rectangle(hdc, rect->left, rect->top, rect->right, rect->bottom);
    
    // Grid lines (25%, 50%, 75%)
    HPEN hPenGrid = CreatePen(PS_DOT, 1, RGB(60, 60, 60));
    SelectObject(hdc, hPenGrid);
    int height = rect->bottom - rect->top - 2;
    int width = rect->right - rect->left - 2;
    for (int i = 1; i < 4; i++) {
        int y = rect->top + 1 + (height * i / 4);
        MoveToEx(hdc, rect->left + 1, y, NULL);
        LineTo(hdc, rect->right - 1, y);
    }
    DeleteObject(hPenGrid);
    
    // Draw utilization line
    HPEN hPenLine = CreatePen(PS_SOLID, 2, lineColor);
    SelectObject(hdc, hPenLine);
    
    int startIdx = g_historyIndex;  // Oldest sample
    int x = rect->left + 1;
    int xStep = width / (GRAPH_HISTORY_SIZE - 1);
    if (xStep < 1) xStep = 1;
    
    int firstY = rect->bottom - 1 - (history[startIdx] * height / 100);
    MoveToEx(hdc, x, firstY, NULL);
    
    for (int i = 1; i < GRAPH_HISTORY_SIZE; i++) {
        int idx = (startIdx + i) % GRAPH_HISTORY_SIZE;
        int y = rect->bottom - 1 - (history[idx] * height / 100);
        x = rect->left + 1 + (i * width / (GRAPH_HISTORY_SIZE - 1));
        LineTo(hdc, x, y);
    }
    
    DeleteObject(hPenLine);
    SelectObject(hdc, hOldPen);
    DeleteObject(hPenBorder);
    
    // Draw current value text
    int currentIdx = (g_historyIndex + GRAPH_HISTORY_SIZE - 1) % GRAPH_HISTORY_SIZE;
    char valBuf[32];
    snprintf(valBuf, sizeof(valBuf), "%s: %u%%", label, history[currentIdx]);
    
    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, RGB(255, 255, 255));
    HFONT hSmallFont = CreateFont(12, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                                   DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                   DEFAULT_QUALITY, DEFAULT_PITCH | FF_SWISS, "Segoe UI");
    HFONT hOldFont = (HFONT)SelectObject(hdc, hSmallFont);
    TextOut(hdc, rect->left + 3, rect->top + 2, valBuf, (int)strlen(valBuf));
    SelectObject(hdc, hOldFont);
    DeleteObject(hSmallFont);
}

// =============================================================================
// SECTION 10: GUI Logging Function
// =============================================================================

#define LOG_FILE_NAME "solopool_miner.log"
static FILE *g_logFile = NULL;

static void OpenLogFile(void) {
    if (!g_logFile) {
        g_logFile = fopen(LOG_FILE_NAME, "a");  // Append mode
        if (g_logFile) {
            SYSTEMTIME st;
            GetLocalTime(&st);
            fprintf(g_logFile, "\n========== SoloPool Miner v1.0.4 Started %04d-%02d-%02d %02d:%02d:%02d ==========\n",
                    st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
            fflush(g_logFile);
        }
    }
}

static void CloseLogFile(void) {
    if (g_logFile) {
        SYSTEMTIME st;
        GetLocalTime(&st);
        fprintf(g_logFile, "========== SoloPool Miner Stopped %04d-%02d-%02d %02d:%02d:%02d ==========\n\n",
                st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
        fclose(g_logFile);
        g_logFile = NULL;
    }
}

// v1.0.4: Flush log buffer to GUI (call from UI thread only)
static void FlushLogBuffer(void) {
    if (g_logBufferLen == 0 || !g_hwndLog || !IsWindow(g_hwndLog)) return;
    
    EnterCriticalSection(&g_csLogBuffer);
    if (g_logBufferLen > 0) {
        char localBuf[LOG_BUFFER_SIZE];
        memcpy(localBuf, g_logBuffer, g_logBufferLen + 1);
        g_logBufferLen = 0;
        g_logBuffer[0] = '\0';
        LeaveCriticalSection(&g_csLogBuffer);
        
        // Get current text length
        int len = GetWindowTextLength(g_hwndLog);
        
        // v1.0.4: AGGRESSIVE trim - keep only last 30 lines (about 3000 chars)
        // This prevents the Edit control from slowing down
        if (len > 3000) {
            char *fullText = (char*)malloc(len + 2);
            if (fullText) {
                GetWindowText(g_hwndLog, fullText, len + 1);
                int lineCount = 0;
                char *cutPoint = fullText + len;
                while (cutPoint > fullText && lineCount < 30) {
                    cutPoint--;
                    if (*cutPoint == '\n') lineCount++;
                }
                if (cutPoint > fullText) cutPoint++;
                SetWindowText(g_hwndLog, cutPoint);
                free(fullText);
                len = GetWindowTextLength(g_hwndLog);
            }
        }
        
        // Append new text
        SendMessage(g_hwndLog, EM_SETSEL, len, len);
        SendMessage(g_hwndLog, EM_REPLACESEL, FALSE, (LPARAM)localBuf);
        
        // Scroll to bottom
        len = GetWindowTextLength(g_hwndLog);
        SendMessage(g_hwndLog, EM_SETSEL, len, len);
        SendMessage(g_hwndLog, EM_SCROLLCARET, 0, 0);
    } else {
        LeaveCriticalSection(&g_csLogBuffer);
    }
}

static void LogToGUI(const char *fmt, ...) {
    char buf[2048];
    
    SYSTEMTIME st;
    GetLocalTime(&st);
    int prefix_len = sprintf(buf, "[%02d:%02d:%02d] ", st.wHour, st.wMinute, st.wSecond);
    
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf + prefix_len, sizeof(buf) - prefix_len - 3, fmt, args);
    va_end(args);
    strcat(buf, "\r\n");
    
    // Buffer for batched GUI update - simple overwrite if full
    EnterCriticalSection(&g_csLogBuffer);
    int msg_len = (int)strlen(buf);
    if (g_logBufferLen + msg_len >= LOG_BUFFER_SIZE - 1) {
        // Buffer full - clear it (timer will catch up)
        g_logBufferLen = 0;
        g_logBuffer[0] = '\0';
    }
    strcpy(g_logBuffer + g_logBufferLen, buf);
    g_logBufferLen += msg_len;
    LeaveCriticalSection(&g_csLogBuffer);
    
    // Write to log file immediately (with error recovery)
    if (g_logFile) {
        char fileBuf[2048];
        strcpy(fileBuf, buf);
        char *p = strstr(fileBuf, "\r\n");
        if (p) { *p = '\n'; *(p+1) = '\0'; }
        if (fprintf(g_logFile, "%s", fileBuf) < 0 || fflush(g_logFile) != 0) {
            // File error - try to reopen
            fclose(g_logFile);
            g_logFile = fopen(LOG_FILE_NAME, "a");
        }
    } else {
        // Try to open if not open
        g_logFile = fopen(LOG_FILE_NAME, "a");
    }
}

// =============================================================================
// SECTION 11: Difficulty Calculation
// =============================================================================

static const double TRUEDIFFONE = 26959535291011309493156476344723991336010898738574164086137773096960.0;

static double hash_to_diff(const uint8_t *hash) {
    double val = 0.0;
    double mult = 1.0;
    for (int i = 0; i < 32; i++) {
        val += hash[i] * mult;
        mult *= 256.0;
    }
    if (val == 0.0) return TRUEDIFFONE;
    return TRUEDIFFONE / val;
}

static int quick_diff_check(const uint8_t *hash) {
    return (hash[31] == 0 && hash[30] == 0 && hash[29] == 0 && hash[28] == 0);
}

// =============================================================================
// SECTION 12: GPU Initialization (CUDA + OpenCL)
// =============================================================================

// Initialize OpenCL for a single device
static int init_opencl_device(gpu_device_t *gpu, cl_device_id device, cl_context ctx) {
    cl_int err;
    
    gpu->type = GPU_TYPE_OPENCL;
    gpu->cl_device = device;
    gpu->cl_ctx = ctx;
    
    // Get device name
    clGetDeviceInfo(device, CL_DEVICE_NAME, sizeof(gpu->name), gpu->name, NULL);
    
    // Create command queue
    gpu->cl_queue = clCreateCommandQueue(ctx, device, 0, &err);
    if (err != CL_SUCCESS) return -1;
    
    // Build program from source
    gpu->cl_program = clCreateProgramWithSource(ctx, 1, &g_openclKernelSource, NULL, &err);
    if (err != CL_SUCCESS) {
        clReleaseCommandQueue(gpu->cl_queue);
        return -1;
    }
    
    err = clBuildProgram(gpu->cl_program, 1, &device, "-cl-mad-enable -cl-fast-relaxed-math", NULL, NULL);
    if (err != CL_SUCCESS) {
        char log[4096];
        clGetProgramBuildInfo(gpu->cl_program, device, CL_PROGRAM_BUILD_LOG, sizeof(log), log, NULL);
        LogToGUI("OpenCL build error: %s", log);
        clReleaseProgram(gpu->cl_program);
        clReleaseCommandQueue(gpu->cl_queue);
        return -1;
    }
    
    // Create kernel
    gpu->cl_kernel = clCreateKernel(gpu->cl_program, "sha256d_opencl_kernel", &err);
    if (err != CL_SUCCESS) {
        clReleaseProgram(gpu->cl_program);
        clReleaseCommandQueue(gpu->cl_queue);
        return -1;
    }
    
    // Allocate buffers
    gpu->cl_midstate = clCreateBuffer(ctx, CL_MEM_READ_ONLY, 32, NULL, &err);
    gpu->cl_tail = clCreateBuffer(ctx, CL_MEM_READ_ONLY, 16, NULL, &err);
    gpu->cl_results = clCreateBuffer(ctx, CL_MEM_READ_WRITE, sizeof(uint32_t) * (MAX_RESULTS + 1), NULL, &err);
    
    if (!gpu->cl_midstate || !gpu->cl_tail || !gpu->cl_results) {
        if (gpu->cl_midstate) clReleaseMemObject(gpu->cl_midstate);
        if (gpu->cl_tail) clReleaseMemObject(gpu->cl_tail);
        if (gpu->cl_results) clReleaseMemObject(gpu->cl_results);
        clReleaseKernel(gpu->cl_kernel);
        clReleaseProgram(gpu->cl_program);
        clReleaseCommandQueue(gpu->cl_queue);
        return -1;
    }
    
    gpu->enabled = 1;
    return 0;
}

// Try to initialize CUDA devices (NVIDIA)
static int init_cuda_devices(void) {
#ifndef OPENCL_ONLY
    int device_count = 0;
    cudaError_t err = cudaGetDeviceCount(&device_count);
    if (err != cudaSuccess || device_count == 0) {
        return 0;
    }
    
    int cuda_count = 0;
    for (int d = 0; d < device_count && g_miner.gpu_count < MAX_GPU_DEVICES; d++) {
        cudaDeviceProp prop;
        if (cudaGetDeviceProperties(&prop, d) != cudaSuccess) continue;
        
        gpu_device_t *gpu = &g_miner.gpus[g_miner.gpu_count];
        memset(gpu, 0, sizeof(gpu_device_t));
        gpu->type = GPU_TYPE_CUDA;
        gpu->device_id = d;
        strncpy(gpu->name, prop.name, sizeof(gpu->name) - 1);
        gpu->multiprocessor_count = prop.multiProcessorCount;
        gpu->max_threads = prop.maxThreadsPerBlock;
        
        cudaSetDevice(d);
        
        if (cudaMalloc(&gpu->d_midstate, 32) != cudaSuccess) continue;
        if (cudaMalloc(&gpu->d_tail, 16) != cudaSuccess) {
            cudaFree(gpu->d_midstate);
            continue;
        }
        if (cudaMalloc(&gpu->d_results, sizeof(uint32_t) * (MAX_RESULTS + 1)) != cudaSuccess) {
            cudaFree(gpu->d_midstate);
            cudaFree(gpu->d_tail);
            continue;
        }
        
        gpu->enabled = 1;
        LogToGUI("CUDA GPU %d: %s (%d SMs)", g_miner.gpu_count, gpu->name, gpu->multiprocessor_count);
        g_miner.gpu_count++;
        cuda_count++;
    }
    
    return cuda_count;
#else
    return 0;
#endif
}

// Try to initialize OpenCL devices (AMD/Intel)
static int init_opencl_devices(void) {
    cl_uint num_platforms = 0;
    cl_platform_id platforms[8];
    
    if (clGetPlatformIDs(8, platforms, &num_platforms) != CL_SUCCESS || num_platforms == 0) {
        return 0;
    }
    
    int opencl_count = 0;
    
    for (cl_uint p = 0; p < num_platforms && g_miner.gpu_count < MAX_GPU_DEVICES; p++) {
        char platform_name[256] = {0};
        clGetPlatformInfo(platforms[p], CL_PLATFORM_NAME, sizeof(platform_name), platform_name, NULL);
        
        // Skip NVIDIA platform if we already have CUDA devices
        // (CUDA is faster than OpenCL for NVIDIA)
        if (strstr(platform_name, "NVIDIA") != NULL) {
            int have_cuda = 0;
            for (int i = 0; i < g_miner.gpu_count; i++) {
                if (g_miner.gpus[i].type == GPU_TYPE_CUDA) {
                    have_cuda = 1;
                    break;
                }
            }
            if (have_cuda) continue;
        }
        
        cl_uint num_devices = 0;
        cl_device_id devices[8];
        
        if (clGetDeviceIDs(platforms[p], CL_DEVICE_TYPE_GPU, 8, devices, &num_devices) != CL_SUCCESS) {
            continue;
        }
        
        for (cl_uint d = 0; d < num_devices && g_miner.gpu_count < MAX_GPU_DEVICES; d++) {
            // Create context for this device
            cl_int err;
            cl_context ctx = clCreateContext(NULL, 1, &devices[d], NULL, NULL, &err);
            if (err != CL_SUCCESS) continue;
            
            gpu_device_t *gpu = &g_miner.gpus[g_miner.gpu_count];
            memset(gpu, 0, sizeof(gpu_device_t));
            gpu->device_id = g_miner.gpu_count;
            
            if (init_opencl_device(gpu, devices[d], ctx) == 0) {
                LogToGUI("OpenCL GPU %d: %s", g_miner.gpu_count, gpu->name);
                g_miner.gpu_count++;
                opencl_count++;
            } else {
                clReleaseContext(ctx);
            }
        }
    }
    
    return opencl_count;
}

// Main GPU initialization - tries CUDA first, then OpenCL
static int init_gpus(void) {
    g_miner.gpu_count = 0;
    
    // Try CUDA first (preferred for NVIDIA)
    int cuda_count = init_cuda_devices();
    
    // Then try OpenCL (for AMD/Intel, or NVIDIA without CUDA)
    int opencl_count = init_opencl_devices();
    
    g_nGpuCount = g_miner.gpu_count;
    
    if (cuda_count > 0 && opencl_count > 0) {
        LogToGUI("GPU: %d CUDA + %d OpenCL devices", cuda_count, opencl_count);
    } else if (cuda_count > 0) {
        LogToGUI("GPU: %d CUDA device(s)", cuda_count);
    } else if (opencl_count > 0) {
        LogToGUI("GPU: %d OpenCL device(s)", opencl_count);
    } else {
        LogToGUI("No GPU devices found");
    }
    
    return g_miner.gpu_count;
}

// =============================================================================
// SECTION 13: Network Functions
// =============================================================================

static int stratum_connect(stratum_ctx_t *ctx) {
    struct addrinfo hints = {0}, *res;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", ctx->port);
    
    if (getaddrinfo(ctx->host, port_str, &hints, &res) != 0) return -1;
    
    ctx->sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (ctx->sock == INVALID_SOCKET) { freeaddrinfo(res); return -1; }
    
    DWORD timeout = 10000;
    setsockopt(ctx->sock, SOL_SOCKET, SO_RCVTIMEO, (char*)&timeout, sizeof(timeout));
    setsockopt(ctx->sock, SOL_SOCKET, SO_SNDTIMEO, (char*)&timeout, sizeof(timeout));
    
    if (connect(ctx->sock, res->ai_addr, (int)res->ai_addrlen) != 0) {
        closesocket(ctx->sock);
        ctx->sock = INVALID_SOCKET;
        freeaddrinfo(res);
        return -1;
    }
    freeaddrinfo(res);
    ctx->connected = 1;
    LogToGUI("Connected to %s:%d", ctx->host, ctx->port);
    return 0;
}

static int stratum_send(stratum_ctx_t *ctx, const char *msg) {
    if (strstr(msg, "mining.submit") || strstr(msg, "mining.suggest_difficulty")) {
        LogToGUI("TX: %s", msg);
    }
    return (send(ctx->sock, msg, (int)strlen(msg), 0) > 0) ? 0 : -1;
}

// -----------------------------------------------------------------------------
// SECTION 13b: Variable Difficulty (Vardiff) - Auto-adjustment based on SPM
// -----------------------------------------------------------------------------

static int suggest_difficulty(stratum_ctx_t *ctx, int new_diff) {
    if (new_diff < MIN_DIFF) new_diff = MIN_DIFF;
    if (new_diff > MAX_DIFF) new_diff = MAX_DIFF;
    
    int current_pool_diff = (int)(ctx->difficulty + 0.5);
    if (current_pool_diff < 1) current_pool_diff = 1;
    
    if (new_diff == current_pool_diff) {
        return 0;
    }
    
    char msg[256];
    snprintf(msg, sizeof(msg), "{\"id\":99,\"method\":\"mining.suggest_difficulty\",\"params\":[%d]}\n", new_diff);
    stratum_send(ctx, msg);
    
    g_miner.current_suggested_diff = new_diff;
    LogToGUI(">>> Suggested new difficulty: %d (was pool diff: %d)", new_diff, current_pool_diff);
    
    return new_diff;
}

static void auto_adjust_difficulty(stratum_ctx_t *ctx, double spm) {
    DWORD now = GetTickCount();
    
    if (g_miner.last_diff_adjust_time == 0) {
        g_miner.last_diff_adjust_time = now;
        g_miner.last_spm_react_time = now;
        g_miner.accepted_at_last_adjust = g_miner.accepted;
        return;
    }
    
    DWORD elapsed_sec = (now - g_miner.start_time) / 1000;
    if (elapsed_sec < SPM_REACT_DELAY) {
        return;
    }
    
    int current_suggested = g_miner.current_suggested_diff;
    if (current_suggested < 1) current_suggested = 3;
    
    int new_diff = current_suggested;
    int reason = 0;
    
    DWORD since_react = (now - g_miner.last_spm_react_time) / 1000;
    if (since_react >= SPM_REACT_COOLDOWN) {
        if (spm > SPM_HIGH_THRESHOLD) {
            new_diff = current_suggested * 2;
            if (new_diff > MAX_DIFF) new_diff = MAX_DIFF;
            reason = 2;
            g_miner.last_spm_react_time = now;
        } else if (spm < SPM_LOW_THRESHOLD && spm > 0) {
            new_diff = (int)(current_suggested * 0.67);  // Gradual drop
            if (new_diff < MIN_DIFF) new_diff = MIN_DIFF;
            if (new_diff == current_suggested && current_suggested > MIN_DIFF) {
                new_diff = current_suggested - 1;
            }
            reason = 3;
            g_miner.last_spm_react_time = now;
        }
    }
    
    if (reason == 0) {
        DWORD since_adjust = (now - g_miner.last_diff_adjust_time) / 1000;
        if (since_adjust >= DIFF_ADJUST_INTERVAL) {
            if (spm > TARGET_SPM + 3.0) {
                new_diff = (int)(current_suggested * 1.25);
                reason = 1;
            } else if (spm < TARGET_SPM - 5.0 && spm > 0) {
                new_diff = (int)(current_suggested * 0.75);
                reason = 1;
            }
            g_miner.last_diff_adjust_time = now;
            g_miner.accepted_at_last_adjust = g_miner.accepted;
        }
    }
    
    if (reason > 0 && new_diff != current_suggested) {
        suggest_difficulty(ctx, new_diff);
    }
}

static int stratum_recv_line(stratum_ctx_t *ctx, char *buf, size_t buflen) {
    size_t pos = 0;
    while (pos < buflen - 1 && g_miner.running) {
        fd_set fds; FD_ZERO(&fds); FD_SET(ctx->sock, &fds);
        struct timeval tv = {1, 0};
        int sel = select(0, &fds, NULL, NULL, &tv);
        if (sel < 0) return -1;
        if (sel == 0) continue;
        char c;
        int n = recv(ctx->sock, &c, 1, 0);
        if (n <= 0) return -1;
        if (c == '\n') break;
        if (c != '\r') buf[pos++] = c;
    }
    buf[pos] = '\0';
    return g_miner.running ? (int)pos : -1;
}

// =============================================================================
// SECTION 14: Header Building
// =============================================================================

static void build_block_header(stratum_ctx_t *ctx) {
    stratum_job_t *job = &ctx->job;
    
    char coinbase_hex[2048];
    char extranonce2_hex[32];
    uint8_t en2_bytes[8] = {0};
    uint32_t en2 = ctx->extranonce2;
    for (int i = 0; i < ctx->extranonce2_size; i++) {
        en2_bytes[i] = en2 & 0xFF;
        en2 >>= 8;
    }
    char *p = extranonce2_hex;
    for (int i = 0; i < ctx->extranonce2_size; i++) p += sprintf(p, "%02x", en2_bytes[i]);
    
    snprintf(coinbase_hex, sizeof(coinbase_hex), "%s%s%s%s",
             job->coinb1, ctx->extranonce1, extranonce2_hex, job->coinb2);
    
    uint8_t coinbase[1024];
    size_t coinbase_len = strlen(coinbase_hex) / 2;
    hex2bin(coinbase, coinbase_hex, coinbase_len);
    uint8_t merkle_root[32];
    sha256d(coinbase, coinbase_len, merkle_root);
    
    uint8_t merkle_sha[64];
    memcpy(merkle_sha, merkle_root, 32);
    for (int i = 0; i < job->merkle_count; i++) {
        uint8_t branch[32];
        hex2bin(branch, job->merkle_branches[i], 32);
        memcpy(merkle_sha + 32, branch, 32);
        sha256d(merkle_sha, 64, merkle_root);
        memcpy(merkle_sha, merkle_root, 32);
    }
    
    uint8_t merkle_flipped[32];
    flip_32((uint32_t*)merkle_flipped, (uint32_t*)merkle_sha);
    
    char header_hex[168];
    snprintf(header_hex, sizeof(header_hex), "%s%s%s%s%s%s",
             job->version,
             job->prevhash,
             "0000000000000000000000000000000000000000000000000000000000000000",
             job->ntime,
             job->nbits,
             "00000000");
    
    hex2bin(job->header, header_hex, 80);
    memcpy(job->header + 36, merkle_flipped, 32);
    
    job->job_difficulty = ctx->difficulty > 0 ? ctx->difficulty : 1.0;
}

// =============================================================================
// SECTION 15: Stratum Protocol
// =============================================================================

static int parse_mining_notify(stratum_ctx_t *ctx, const char *json) {
    stratum_job_t *job = &ctx->job;
    const char *params = strstr(json, "\"params\"");
    if (!params) return -1;
    params = strchr(params, '[');
    if (!params) return -1;
    params++;
    
    #define PARSE_STRING(dest, maxlen) do { \
        while (*params && *params != '"') params++; \
        if (!*params) return -1; \
        params++; \
        const char *end = strchr(params, '"'); \
        if (!end) return -1; \
        size_t len = end - params; \
        if (len >= maxlen) len = maxlen - 1; \
        strncpy(dest, params, len); \
        dest[len] = '\0'; \
        params = end + 1; \
    } while(0)
    
    PARSE_STRING(job->job_id, 128);
    PARSE_STRING(job->prevhash, 65);
    PARSE_STRING(job->coinb1, 1024);
    PARSE_STRING(job->coinb2, 1024);
    
    const char *merkle_start = strchr(params, '[');
    if (!merkle_start) return -1;
    merkle_start++;
    job->merkle_count = 0;
    while (*merkle_start && *merkle_start != ']' && job->merkle_count < 32) {
        while (*merkle_start && *merkle_start != '"' && *merkle_start != ']') merkle_start++;
        if (*merkle_start == ']') break;
        if (*merkle_start != '"') break;
        merkle_start++;
        const char *end = strchr(merkle_start, '"');
        if (!end) break;
        size_t len = end - merkle_start;
        if (len > 64) len = 64;
        strncpy(job->merkle_branches[job->merkle_count], merkle_start, len);
        job->merkle_branches[job->merkle_count][len] = '\0';
        job->merkle_count++;
        merkle_start = end + 1;
    }
    
    params = strchr(merkle_start, ']');
    if (!params) return -1;
    params++;
    
    PARSE_STRING(job->version, 9);
    PARSE_STRING(job->nbits, 9);
    PARSE_STRING(job->ntime, 9);
    
    #undef PARSE_STRING
    
    job->clean = strstr(params, "true") ? 1 : 0;
    build_block_header(ctx);
    ctx->has_job = 1;
    
    if (ctx->difficulty <= 100 && !ctx->ready_to_submit) {
        ctx->ready_to_submit = 1;
        LogToGUI("Ready to submit shares");
    }
    
    LogToGUI("New job: %s diff=%.0f %s", job->job_id, job->job_difficulty, job->clean ? "[CLEAN]" : "");
    return 0;
}

static int parse_set_difficulty(stratum_ctx_t *ctx, const char *json) {
    const char *params = strstr(json, "\"params\"");
    if (!params) return -1;
    params = strchr(params, '[');
    if (!params) return -1;
    params++;
    while (*params && (*params == ' ' || *params == '\t')) params++;
    double new_diff = atof(params);
    if (new_diff != ctx->difficulty) {
        ctx->difficulty = new_diff;
        LogToGUI("Pool difficulty: %.0f", ctx->difficulty);
        if (ctx->has_job) {
            build_block_header(ctx);
        }
    }
    return 0;
}

static int stratum_subscribe(stratum_ctx_t *ctx) {
    char msg[512];
    snprintf(msg, sizeof(msg), "{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"SoloPoolMiner/44.3-GUI\"]}\n");
    if (send(ctx->sock, msg, (int)strlen(msg), 0) <= 0) return -1;
    
    char resp[4096];
    if (stratum_recv_line(ctx, resp, sizeof(resp)) < 0) return -1;
    
    char *p = strstr(resp, "]],\"");
    if (!p) p = strstr(resp, "]], \"");
    if (!p) p = strstr(resp, ",\"");
    if (p) {
        while (*p && *p != '"') p++;
        if (*p == '"') {
            p++;
            char *end = strchr(p, '"');
            if (end) {
                size_t len = end - p;
                if (len < sizeof(ctx->extranonce1)) {
                    strncpy(ctx->extranonce1, p, len);
                    ctx->extranonce1[len] = '\0';
                }
                p = end + 1;
                while (*p && (*p < '0' || *p > '9')) p++;
                if (*p) ctx->extranonce2_size = atoi(p);
            }
        }
    }
    
    if (strlen(ctx->extranonce1) == 0 || ctx->extranonce2_size == 0) return -1;
    LogToGUI("Subscribed: extranonce1=%s, size=%d", ctx->extranonce1, ctx->extranonce2_size);
    ctx->subscribed = 1;
    return 0;
}

static int stratum_authorize(stratum_ctx_t *ctx) {
    char msg[512];
    snprintf(msg, sizeof(msg), "{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"%s\",\"%s\"]}\n",
             ctx->user, ctx->pass);
    if (send(ctx->sock, msg, (int)strlen(msg), 0) <= 0) return -1;
    
    int initial_diff = 3;
    g_miner.current_suggested_diff = initial_diff;
    snprintf(msg, sizeof(msg), "{\"id\":3,\"method\":\"mining.suggest_difficulty\",\"params\":[%d]}\n", initial_diff);
    send(ctx->sock, msg, (int)strlen(msg), 0);
    LogToGUI("Suggested initial difficulty: %d", initial_diff);
    return 0;
}

static int extract_response_id(const char *json) {
    const char *id_str = strstr(json, "\"id\"");
    if (!id_str) return -1;
    id_str += 4;
    while (*id_str && (*id_str == ' ' || *id_str == ':' || *id_str == '\t')) id_str++;
    if (!*id_str) return -1;
    return atoi(id_str);
}

static void handle_stratum_message(stratum_ctx_t *ctx, const char *json) {
    if (strstr(json, "mining.notify")) {
        parse_mining_notify(ctx, json);
    } else if (strstr(json, "mining.set_difficulty")) {
        parse_set_difficulty(ctx, json);
    } else if (strstr(json, "\"id\":2") || strstr(json, "\"id\": 2")) {
        if (strstr(json, "true") && !ctx->authorized) {
            ctx->authorized = 1;
            LogToGUI("Authorized OK");
        }
    } else if (strstr(json, "\"result\":true")) {
        if (!strstr(json, "\"id\":2") && !strstr(json, "\"id\": 2")) {
            int resp_id = extract_response_id(json);
            g_miner.accepted++;
            if (resp_id >= 4) {
                int is_gpu = g_miner.submit_source[resp_id % SUBMIT_TRACK_SIZE];
                if (is_gpu) g_miner.gpu_accepted++;
                else g_miner.cpu_accepted++;
            }
            LogToGUI("Share ACCEPTED [%u/%u]", g_miner.accepted, g_miner.accepted + g_miner.rejected);
        }
    } else if (strstr(json, "\"result\":false") || strstr(json, "reject")) {
        int resp_id = extract_response_id(json);
        g_miner.rejected++;
        if (resp_id >= 4) {
            int is_gpu = g_miner.submit_source[resp_id % SUBMIT_TRACK_SIZE];
            if (is_gpu) g_miner.gpu_rejected++;
            else g_miner.cpu_rejected++;
        }
        LogToGUI("Share REJECTED [%u/%u]", g_miner.accepted, g_miner.accepted + g_miner.rejected);
    }
}

// =============================================================================
// SECTION 16: Share Submission
// =============================================================================

static int submit_share(stratum_ctx_t *ctx, uint32_t nonce, uint8_t *data_before_flip, uint8_t *hash, 
                        double share_diff, double job_diff, const char *source) {
    if (!ctx->ready_to_submit) return 0;
    
    char msg[512];
    
    char nonce_hex[9];
    snprintf(nonce_hex, sizeof(nonce_hex), "%02x%02x%02x%02x",
             data_before_flip[76], data_before_flip[77], 
             data_before_flip[78], data_before_flip[79]);
    
    char extranonce2_hex[32];
    uint8_t en2_bytes[8] = {0};
    uint32_t en2 = ctx->extranonce2;
    for (int i = 0; i < ctx->extranonce2_size; i++) {
        en2_bytes[i] = en2 & 0xFF;
        en2 >>= 8;
    }
    char *p = extranonce2_hex;
    for (int i = 0; i < ctx->extranonce2_size; i++) p += sprintf(p, "%02x", en2_bytes[i]);
    
    char ntime_hex[9];
    strncpy(ntime_hex, ctx->job.ntime, 8);
    ntime_hex[8] = '\0';
    
    static int submit_id = 4;
    int current_id = submit_id++;
    
    int is_gpu = (strcmp(source, "GPU") == 0) ? 1 : 0;
    g_miner.submit_source[current_id % SUBMIT_TRACK_SIZE] = is_gpu;
    
    snprintf(msg, sizeof(msg),
        "{\"id\":%d,\"method\":\"mining.submit\",\"params\":[\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"]}\n",
        current_id, ctx->user, ctx->job.job_id, extranonce2_hex, ntime_hex, nonce_hex);
    
    update_best_share(share_diff, source);
    track_share_for_spm();
    g_miner.submitted++;
    
    LogToGUI("[%s] Share diff=%.1f (pool=%.0f)", source, share_diff, job_diff);
    
    return stratum_send(ctx, msg);
}

// =============================================================================
// SECTION 17: Stratum Thread
// =============================================================================

static unsigned __stdcall stratum_thread(void *arg) {
    stratum_ctx_t *ctx = (stratum_ctx_t *)arg;
    char buf[4096];
    
    while (g_miner.running) {
        if (!ctx->connected) {
            if (stratum_connect(ctx) < 0) { Sleep(5000); continue; }
            if (stratum_subscribe(ctx) < 0) { closesocket(ctx->sock); ctx->connected = 0; Sleep(5000); continue; }
            if (stratum_authorize(ctx) < 0) { closesocket(ctx->sock); ctx->connected = 0; Sleep(5000); continue; }
        }
        
        int ret = stratum_recv_line(ctx, buf, sizeof(buf));
        if (ret > 0) {
            handle_stratum_message(ctx, buf);
        } else if (ret < 0 && g_miner.running) {
            LogToGUI("Connection lost, reconnecting...");
            closesocket(ctx->sock);
            ctx->connected = ctx->subscribed = ctx->authorized = 0;
            Sleep(2000);
        }
    }
    return 0;
}

// =============================================================================
// SECTION 18: CPU Mining Thread
// =============================================================================

static unsigned __stdcall cpu_mining_thread(void *arg) {
    int thread_id = (int)(intptr_t)arg;
    stratum_ctx_t *ctx = &g_stratum;
    
    uint64_t cpu_range_size = (uint64_t)CPU_NONCE_END - CPU_NONCE_START + 1;
    uint64_t partition_size = cpu_range_size / g_miner.cpu_threads;
    uint32_t nonce_min = CPU_NONCE_START + (uint32_t)(thread_id * partition_size);
    uint32_t nonce_max = (thread_id == g_miner.cpu_threads - 1) ? CPU_NONCE_END : (uint32_t)(nonce_min + partition_size - 1);
    uint32_t nonce = nonce_min;
    
    uint8_t header[80], data[80], swap[80], hash[32];
    uint64_t local_hashes = 0;
    DWORD last_report = GetTickCount();
    char last_job[128] = {0};
    double pool_diff = 1.0;
    
    while (g_miner.running) {
        // CPU power throttling via thread limiting AND delay
        // Use CPU_THREAD_SCALE to reduce thread count
        // At 10%: 10 * 16 * 0.5 / 100 = 0.8 â†’ 1 thread
        // At 80%: 80 * 16 * 0.5 / 100 = 6.4 â†’ 6 threads
        int active_threads = (int)((g_miner.cpu_power_percent * g_nSystemCpuCount * CPU_THREAD_SCALE) / 100.0);
        if (active_threads < 1) active_threads = 1;
        
        if (!g_miner.cpu_enabled || thread_id >= active_threads) {
            Sleep(1000);
            continue;
        }
        
        // v1.0.4: Skip-based throttling for 80-99% - MUST BE BEFORE WORK
        int power = g_miner.cpu_power_percent;
        if (power >= 80 && power < 100) {
            static int cpu_skip_counter = 0;
            cpu_skip_counter++;
            if (cpu_skip_counter > 100) cpu_skip_counter = 1;
            if (cpu_skip_counter <= 3 * (100 - power)) {
                Sleep(1);  // Brief yield
                continue;  // Skip BEFORE doing work
            }
        }
        
        if (!ctx->has_job || !ctx->authorized) { Sleep(100); continue; }
        
        EnterCriticalSection(&ctx->cs);
        memcpy(header, ctx->job.header, 80);
        pool_diff = ctx->job.job_difficulty;
        char ntime_str[9];
        strncpy(ntime_str, ctx->job.ntime, 8);
        ntime_str[8] = '\0';
        int new_job = (strcmp(last_job, ctx->job.job_id) != 0);
        if (new_job) {
            strncpy(last_job, ctx->job.job_id, 127);
            nonce = nonce_min;
        }
        LeaveCriticalSection(&ctx->cs);
        
        uint32_t ntime32;
        sscanf(ntime_str, "%x", &ntime32);
        
        // Smaller batch size at lower power for finer control
        int batch_size = 8192 + (g_miner.cpu_power_percent * 512);  // 8K to 49K per batch
        
        for (int i = 0; i < batch_size && g_miner.running; i++) {
            memcpy(data, header, 80);
            *(uint32_t*)(data + 68) = bswap_32(ntime32);
            *(uint32_t*)(data + 76) = nonce;
            
            flip_80((uint32_t*)swap, (uint32_t*)data);
            sha256d_80(swap, hash);
            local_hashes++;
            
            if (quick_diff_check(hash)) {
                double share_diff = hash_to_diff(hash);
                if (share_diff >= pool_diff) {
                    EnterCriticalSection(&ctx->cs);
                    submit_share(ctx, nonce, data, hash, share_diff, pool_diff, "CPU");
                    LeaveCriticalSection(&ctx->cs);
                }
            }
            
            nonce++;
            if (nonce > nonce_max) nonce = nonce_min;
        }
        
        // v1.0.4: Delay for power < 80%
        if (power < 80) {
            int delay_ms;
            if (power <= REDZONE_THRESHOLD) {
                delay_ms = CPU_DELAY_AT_MIN - 
                           ((CPU_DELAY_AT_MIN - CPU_DELAY_AT_80) * (power - MIN_UTILIZATION_PERCENT)) / 
                           (REDZONE_THRESHOLD - MIN_UTILIZATION_PERCENT);
            } else {
                delay_ms = CPU_DELAY_AT_80 - 
                           ((CPU_DELAY_AT_80 - 2) * (power - REDZONE_THRESHOLD)) / 
                           (89 - REDZONE_THRESHOLD);
            }
            if (delay_ms > 0) Sleep(delay_ms);
        }
        
        DWORD now = GetTickCount();
        if (now - last_report >= 1000) {
            EnterCriticalSection(&ctx->cs);
            g_miner.cpu_hashes += local_hashes;
            LeaveCriticalSection(&ctx->cs);
            local_hashes = 0;
            last_report = now;
        }
    }
    
    return 0;
}

// =============================================================================
// SECTION 19: Midstate Computation for GPU
// =============================================================================

static void compute_midstate_for_gpu(const uint8_t *header, uint32_t ntime32, 
                                     uint32_t *midstate_out, uint32_t *tail_out) {
    uint8_t data[80], swap[80];
    
    memcpy(data, header, 80);
    *(uint32_t*)(data + 68) = bswap_32(ntime32);
    
    flip_80((uint32_t*)swap, (uint32_t*)data);
    
    uint32_t state[8];
    memcpy(state, sha256_init, sizeof(state));
    sha256_transform(state, swap);
    
    memcpy(midstate_out, state, 32);
    
    tail_out[0] = be32dec(swap + 64);
    tail_out[1] = be32dec(swap + 68);
    tail_out[2] = be32dec(swap + 72);
    tail_out[3] = 0;
}

// =============================================================================
// SECTION 20: GPU Mining Thread
// =============================================================================

static unsigned __stdcall gpu_mining_thread(void *arg) {
    int gid = (int)(intptr_t)arg;
    gpu_device_t *gpu = &g_miner.gpus[gid];
    stratum_ctx_t *ctx = &g_stratum;
    
    // Set up device based on type
    if (gpu->type == GPU_TYPE_CUDA) {
#ifndef OPENCL_ONLY
        cudaSetDevice(gpu->device_id);
#endif
    }
    // OpenCL doesn't need explicit device selection - it's in the command queue
    
    uint64_t gpu_range_size = (uint64_t)GPU_NONCE_END - GPU_NONCE_START + 1;
    uint64_t gpu_partition = gpu_range_size / g_miner.gpu_count;
    uint32_t nonce_min = GPU_NONCE_START + (uint32_t)(gid * gpu_partition);
    uint32_t nonce_max = (gid == g_miner.gpu_count - 1) ? GPU_NONCE_END : (uint32_t)(nonce_min + gpu_partition - 1);
    uint32_t nonce_base = nonce_min;
    
    uint32_t h_results[MAX_RESULTS + 1];
    char last_job[128] = {0};
    double pool_diff = 1.0;
    
    int threads_per_block = 256;
    
    #define SUBMITTED_SIZE 1024
    uint32_t submitted_nonces[SUBMITTED_SIZE];
    int submitted_count = 0;
    
    while (g_miner.running) {
        if (!g_miner.gpu_enabled || !ctx->has_job || !ctx->authorized || !gpu->enabled) { 
            Sleep(100); 
            continue; 
        }
        
        int power = g_miner.gpu_power_percent;
        
        // v1.0.4: Skip-based throttling for 80-99% - MUST BE BEFORE WORK
        if (power >= 80 && power < 100) {
            static int gpu_skip_counter = 0;
            gpu_skip_counter++;
            if (gpu_skip_counter > 100) gpu_skip_counter = 1;
            if (gpu_skip_counter <= 3 * (100 - power)) {
                Sleep(1);  // Brief yield
                continue;  // Skip BEFORE doing work
            }
        }
        
        // v1.0.0: GPU batch scaling with RED ZONE support
        double batch_scale;
        
        if (power <= REDZONE_THRESHOLD) {
            // Safe zone: 10% to 80%
            batch_scale = GPU_BATCH_SCALE_MIN + 
                         (GPU_BATCH_SCALE_80 - GPU_BATCH_SCALE_MIN) * 
                         (power - MIN_UTILIZATION_PERCENT) / 
                         (double)(REDZONE_THRESHOLD - MIN_UTILIZATION_PERCENT);
        } else {
            // RED ZONE: 80% to 100% - ramp up to full power!
            batch_scale = GPU_BATCH_SCALE_80 + 
                         (GPU_BATCH_SCALE_MAX - GPU_BATCH_SCALE_80) * 
                         (power - REDZONE_THRESHOLD) / 
                         (double)(MAX_UTILIZATION_PERCENT - REDZONE_THRESHOLD);
        }
        
        size_t batch = (size_t)(GPU_BATCH_SIZE * batch_scale);
        if (batch > GPU_BATCH_SIZE) batch = GPU_BATCH_SIZE;  // Cap at max
        if (batch < (1 << 20)) batch = (1 << 20);  // Minimum 1M hashes
        
        EnterCriticalSection(&ctx->cs);
        uint8_t header[80];
        memcpy(header, ctx->job.header, 80);
        pool_diff = ctx->job.job_difficulty;
        char ntime_str[9];
        strncpy(ntime_str, ctx->job.ntime, 8);
        ntime_str[8] = '\0';
        int new_job = (strcmp(last_job, ctx->job.job_id) != 0);
        if (new_job) {
            strncpy(last_job, ctx->job.job_id, 127);
            nonce_base = nonce_min;
            submitted_count = 0;
        }
        LeaveCriticalSection(&ctx->cs);
        
        uint32_t ntime32;
        sscanf(ntime_str, "%x", &ntime32);
        
        uint32_t midstate[8], tail[4];
        compute_midstate_for_gpu(header, ntime32, midstate, tail);
        
        if ((uint64_t)nonce_base + batch - 1 > nonce_max) {
            batch = (size_t)(nonce_max - nonce_base + 1);
        }
        
        // Execute on GPU based on type (CUDA or OpenCL)
        if (gpu->type == GPU_TYPE_CUDA) {
#ifndef OPENCL_ONLY
            cudaMemcpy(gpu->d_midstate, midstate, 32, cudaMemcpyHostToDevice);
            cudaMemcpy(gpu->d_tail, tail, 16, cudaMemcpyHostToDevice);
            cudaMemset(gpu->d_results, 0, sizeof(uint32_t) * (MAX_RESULTS + 1));
            
            int actual_blocks = ((int)batch + threads_per_block - 1) / threads_per_block;
            
            sha256d_cuda_kernel<<<actual_blocks, threads_per_block>>>(
                gpu->d_midstate, gpu->d_tail, nonce_base, gpu->d_results
            );
            
            cudaDeviceSynchronize();
            cudaMemcpy(h_results, gpu->d_results, sizeof(uint32_t) * (MAX_RESULTS + 1), cudaMemcpyDeviceToHost);
#endif
        } else if (gpu->type == GPU_TYPE_OPENCL) {
            // OpenCL execution path
            
            // Write data to GPU
            clEnqueueWriteBuffer(gpu->cl_queue, gpu->cl_midstate, CL_FALSE, 0, 32, midstate, 0, NULL, NULL);
            clEnqueueWriteBuffer(gpu->cl_queue, gpu->cl_tail, CL_FALSE, 0, 16, tail, 0, NULL, NULL);
            
            // Clear results
            uint32_t zero = 0;
            clEnqueueFillBuffer(gpu->cl_queue, gpu->cl_results, &zero, sizeof(uint32_t), 0, sizeof(uint32_t) * (MAX_RESULTS + 1), 0, NULL, NULL);
            
            // Set kernel arguments
            uint32_t nonce_arg = nonce_base;
            clSetKernelArg(gpu->cl_kernel, 0, sizeof(cl_mem), &gpu->cl_midstate);
            clSetKernelArg(gpu->cl_kernel, 1, sizeof(cl_mem), &gpu->cl_tail);
            clSetKernelArg(gpu->cl_kernel, 2, sizeof(uint32_t), &nonce_arg);
            clSetKernelArg(gpu->cl_kernel, 3, sizeof(cl_mem), &gpu->cl_results);
            
            // Execute kernel
            size_t global_size = batch;
            size_t local_size = 256;
            // Round up global size to multiple of local size
            global_size = ((global_size + local_size - 1) / local_size) * local_size;
            
            clEnqueueNDRangeKernel(gpu->cl_queue, gpu->cl_kernel, 1, NULL, &global_size, &local_size, 0, NULL, NULL);
            clFinish(gpu->cl_queue);
            
            // Read results
            clEnqueueReadBuffer(gpu->cl_queue, gpu->cl_results, CL_TRUE, 0, sizeof(uint32_t) * (MAX_RESULTS + 1), h_results, 0, NULL, NULL);
        }
        
        uint32_t found = h_results[0];
        if (found > MAX_RESULTS) found = MAX_RESULTS;
        
        for (uint32_t i = 0; i < found; i++) {
            uint32_t nonce = h_results[1 + i];
            
            if (nonce < GPU_NONCE_START || nonce > GPU_NONCE_END) continue;
            
            int is_already_submitted = 0;
            for (int j = 0; j < submitted_count; j++) {
                if (submitted_nonces[j] == nonce) { is_already_submitted = 1; break; }
            }
            if (is_already_submitted) continue;
            
            uint8_t vdata[80], vswap[80], vhash[32];
            memcpy(vdata, header, 80);
            *(uint32_t*)(vdata + 68) = bswap_32(ntime32);
            *(uint32_t*)(vdata + 76) = nonce;
            flip_80((uint32_t*)vswap, (uint32_t*)vdata);
            sha256d_80(vswap, vhash);
            
            double share_diff = hash_to_diff(vhash);
            
            if (share_diff >= pool_diff) {
                EnterCriticalSection(&ctx->cs);
                submit_share(ctx, nonce, vdata, vhash, share_diff, pool_diff, "GPU");
                LeaveCriticalSection(&ctx->cs);
                
                if (submitted_count < SUBMITTED_SIZE) {
                    submitted_nonces[submitted_count++] = nonce;
                }
            }
        }
        
        EnterCriticalSection(&ctx->cs);
        g_miner.gpu_hashes += batch;
        LeaveCriticalSection(&ctx->cs);
        
        nonce_base += (uint32_t)batch;
        if (nonce_base < GPU_NONCE_START || nonce_base > nonce_max) {
            nonce_base = nonce_min;
            submitted_count = 0;
            
            EnterCriticalSection(&ctx->cs);
            ctx->extranonce2++;
            build_block_header(ctx);
            LeaveCriticalSection(&ctx->cs);
        }
        
        // v1.0.4: Delay for power < 80%
        if (power < 80) {
            int delay_ms;
            if (power <= REDZONE_THRESHOLD) {
                delay_ms = GPU_DELAY_AT_MIN - 
                           ((GPU_DELAY_AT_MIN - GPU_DELAY_AT_80) * (power - MIN_UTILIZATION_PERCENT)) / 
                           (REDZONE_THRESHOLD - MIN_UTILIZATION_PERCENT);
            } else {
                delay_ms = GPU_DELAY_AT_80 - 
                           ((GPU_DELAY_AT_80 - 2) * (power - REDZONE_THRESHOLD)) / 
                           (89 - REDZONE_THRESHOLD);
            }
            if (delay_ms > 0) Sleep(delay_ms);
        }
    }
    
    return 0;
    
    #undef SUBMITTED_SIZE
}

// =============================================================================
// SECTION 21: Mining Control Functions
// =============================================================================

static void StartMining(void) {
    if (g_miner.running) return;
    
    // Get address from GUI
    char address[256] = {0};
    char password[64] = {0};
    GetWindowText(g_hwndAddress, address, sizeof(address));
    GetWindowText(g_hwndPassword, password, sizeof(password));
    
    if (strlen(address) < 10) {
        MessageBox(g_hwnd, "Please enter a valid Bitcoin address", "Error", MB_OK | MB_ICONERROR);
        return;
    }
    
    if (strlen(password) == 0) {
        strcpy(password, "x");
    }
    
    // Save address for next time
    save_last_address(address, password);
    
    // Setup stratum
    strncpy(g_stratum.host, POOL_HOST, sizeof(g_stratum.host) - 1);
    g_stratum.port = POOL_PORT;
    strncpy(g_stratum.user, address, sizeof(g_stratum.user) - 1);
    strncpy(g_stratum.pass, password, sizeof(g_stratum.pass) - 1);
    
    // Get power settings from sliders
    g_miner.cpu_power_percent = (int)SendMessage(g_hwndSliderCPU, TBM_GETPOS, 0, 0);
    g_miner.gpu_power_percent = (int)SendMessage(g_hwndSliderGPU, TBM_GETPOS, 0, 0);
    g_miner.cpu_enabled = (SendMessage(g_hwndCheckCPU, BM_GETCHECK, 0, 0) == BST_CHECKED);
    g_miner.gpu_enabled = (SendMessage(g_hwndCheckGPU, BM_GETCHECK, 0, 0) == BST_CHECKED);
    
    // Calculate threads based on power setting (with scale factor)
    g_miner.cpu_threads = g_nSystemCpuCount;
    g_miner.cpu_threads_active = (int)((g_miner.cpu_power_percent * g_nSystemCpuCount * CPU_THREAD_SCALE) / 100.0);
    if (g_miner.cpu_threads_active < 1) g_miner.cpu_threads_active = 1;
    
    g_miner.running = 1;
    g_miner.start_time = GetTickCount();
    g_miner.last_diff_adjust_time = GetTickCount();
    g_miner.accepted_at_last_adjust = 0;
    g_miner.current_suggested_diff = 3;
    memset((void*)g_miner.shares_last_minute, 0, sizeof(g_miner.shares_last_minute));
    
    LogToGUI("================================================================================");
    LogToGUI("SoloPool Miner v1.0.4 - GUI Edition");
    LogToGUI("Pool: %s", POOL_DISPLAY);
    LogToGUI("Worker: %s", address);
    LogToGUI("CPU: %d threads @ %d%% power | GPU: %d device(s) @ %d%% power", 
             g_miner.cpu_threads_active, g_miner.cpu_power_percent,
             g_nGpuCount, g_miner.gpu_power_percent);
    LogToGUI("================================================================================");
    
    // Force immediate flush so startup messages appear
    FlushLogBuffer();
    
    // Start stratum thread
    g_hStratumThread = (HANDLE)_beginthreadex(NULL, 0, stratum_thread, &g_stratum, 0, NULL);
    
    // Start CPU threads
    for (int i = 0; i < g_miner.cpu_threads; i++) {
        g_hCPUThreads[i] = (HANDLE)_beginthreadex(NULL, 0, cpu_mining_thread, (void*)(intptr_t)i, 0, NULL);
    }
    
    // Start GPU threads
    for (int i = 0; i < g_miner.gpu_count; i++) {
        g_hGPUThreads[i] = (HANDLE)_beginthreadex(NULL, 0, gpu_mining_thread, (void*)(intptr_t)i, 0, NULL);
    }
    
    // Update UI
    EnableWindow(g_hwndBtnStart, FALSE);
    EnableWindow(g_hwndBtnStop, TRUE);
    EnableWindow(g_hwndAddress, FALSE);
    EnableWindow(g_hwndPassword, FALSE);
    
    // Start update timer
    SetTimer(g_hwnd, ID_TIMER_UPDATE, 1000, NULL);
    SetTimer(g_hwnd, ID_TIMER_LOG, LOG_UPDATE_INTERVAL_MS, NULL);
    
    // Clear log buffer for fresh start
    EnterCriticalSection(&g_csLogBuffer);
    g_logBufferLen = 0;
    g_logBuffer[0] = '\0';
    LeaveCriticalSection(&g_csLogBuffer);
}

static void StopMining(void) {
    if (!g_miner.running) return;
    
    LogToGUI("Stopping miner...");
    g_miner.running = 0;
    
    // Close socket to unblock recv
    if (g_stratum.sock != INVALID_SOCKET) {
        closesocket(g_stratum.sock);
        g_stratum.sock = INVALID_SOCKET;
    }
    g_stratum.connected = 0;
    
    // Wait for threads
    for (int i = 0; i < g_miner.cpu_threads; i++) {
        if (g_hCPUThreads[i]) {
            WaitForSingleObject(g_hCPUThreads[i], 2000);
            CloseHandle(g_hCPUThreads[i]);
            g_hCPUThreads[i] = NULL;
        }
    }
    
    for (int i = 0; i < g_miner.gpu_count; i++) {
        if (g_hGPUThreads[i]) {
            WaitForSingleObject(g_hGPUThreads[i], 2000);
            CloseHandle(g_hGPUThreads[i]);
            g_hGPUThreads[i] = NULL;
        }
    }
    
    if (g_hStratumThread) {
        WaitForSingleObject(g_hStratumThread, 2000);
        CloseHandle(g_hStratumThread);
        g_hStratumThread = NULL;
    }
    
    // Reset state
    g_stratum.subscribed = 0;
    g_stratum.authorized = 0;
    g_stratum.has_job = 0;
    g_stratum.ready_to_submit = 0;
    
    LogToGUI("Miner stopped");
    LogToGUI("--------------------------------------------------------------------------------");
    FlushLogBuffer();  // Flush before killing timer
    
    KillTimer(g_hwnd, ID_TIMER_UPDATE);
    KillTimer(g_hwnd, ID_TIMER_LOG);
    
    // Update UI
    EnableWindow(g_hwndBtnStart, TRUE);
    EnableWindow(g_hwndBtnStop, FALSE);
    EnableWindow(g_hwndAddress, TRUE);
    EnableWindow(g_hwndPassword, TRUE);
}

// =============================================================================
// SECTION 22: GUI Update Function
// =============================================================================

static void UpdateGUIStats(void) {
    static uint64_t last_cpu = 0, last_gpu = 0;
    static DWORD last_time = 0;
    
    DWORD now = GetTickCount();
    if (last_time == 0) last_time = now;
    
    double elapsed = (now - last_time) / 1000.0;
    if (elapsed < 0.5) return;
    
    uint64_t ch = g_miner.cpu_hashes;
    uint64_t gh = g_miner.gpu_hashes;
    
    double cpu_rate = (ch - last_cpu) / elapsed;
    double gpu_rate = (gh - last_gpu) / elapsed;
    double total_rate = cpu_rate + gpu_rate;
    
    last_cpu = ch;
    last_gpu = gh;
    last_time = now;
    
    // Calculate SPM
    advance_spm_window();
    double spm = calculate_spm();
    
    // Auto-adjust difficulty based on SPM (vardiff)
    if (g_stratum.connected && g_stratum.authorized) {
        auto_adjust_difficulty(&g_stratum, spm);
    }
    
    // Calculate uptime
    DWORD elapsed_ms = now - g_miner.start_time;
    int uptime_sec = elapsed_ms / 1000;
    int hours = uptime_sec / 3600;
    int mins = (uptime_sec % 3600) / 60;
    int secs = uptime_sec % 60;
    
    // Calculate acceptance rate
    uint32_t total_submitted = g_miner.accepted + g_miner.rejected;
    double accept_rate = (total_submitted > 0) ? (100.0 * g_miner.accepted / total_submitted) : 100.0;
    
    // Format stats string (3 lines to save space)
    char stats[1024];
    snprintf(stats, sizeof(stats),
        "CPU: %.2f MH/s | GPU: %.2f MH/s | Total: %.2f MH/s\r\n"
        "CPU: %u/%u | GPU: %u/%u | Total: %u/%u (%.1f%%) | SPM: %.1f\r\n"
        "Best: %.1f / %.1f | Uptime: %02d:%02d:%02d | Diff: %.0f | Suggested: %d",
        cpu_rate / 1e6, gpu_rate / 1e6, total_rate / 1e6,
        g_miner.cpu_accepted, g_miner.cpu_rejected,
        g_miner.gpu_accepted, g_miner.gpu_rejected,
        g_miner.accepted, g_miner.rejected, accept_rate, spm,
        g_miner.best_share_session, g_miner.best_share_ever,
        hours, mins, secs, g_stratum.difficulty, g_miner.current_suggested_diff
    );
    
    SetWindowText(g_hwndStats, stats);
}

// =============================================================================
// SECTION 23: GUI Window Procedure
// =============================================================================

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE: {
            HINSTANCE hInst = ((LPCREATESTRUCT)lParam)->hInstance;
            
            // Create fonts
            g_hFont = CreateFont(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                                 DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                 CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, "Segoe UI");
            g_hFontBold = CreateFont(16, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, "Segoe UI");
            g_hFontMono = CreateFont(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY, FIXED_PITCH | FF_MODERN, "Consolas");
            
            int y = 15;
            
            // Title
            HWND hTitle = CreateWindow("STATIC", "SoloPool.Com Miner v1.0.4",
                                       WS_CHILD | WS_VISIBLE | SS_CENTER,
                                       15, y, WINDOW_WIDTH - 50, 30, hwnd, NULL, hInst, NULL);
            SendMessage(hTitle, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            y += 35;
            
            // Pool info
            HWND hPool = CreateWindow("STATIC", "Pool: stratum.solopool.com:3333",
                                      WS_CHILD | WS_VISIBLE,
                                      15, y, WINDOW_WIDTH - 50, 20, hwnd, NULL, hInst, NULL);
            SendMessage(hPool, WM_SETFONT, (WPARAM)g_hFont, TRUE);
            y += 30;
            
            // Address input - simpler label
            CreateWindow("STATIC", "Worker:",
                        WS_CHILD | WS_VISIBLE,
                        15, y, 150, 20, hwnd, NULL, hInst, NULL);
            g_hwndAddress = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "",
                                           WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                           170, y - 2, WINDOW_WIDTH - 200, 24, hwnd, (HMENU)ID_EDIT_ADDRESS, hInst, NULL);
            SendMessage(g_hwndAddress, WM_SETFONT, (WPARAM)g_hFont, TRUE);
            SendMessage(g_hwndAddress, EM_SETCUEBANNER, TRUE, (LPARAM)L"BTCADDR.workername");
            y += 32;
            
            // Password input
            CreateWindow("STATIC", "Password:",
                        WS_CHILD | WS_VISIBLE,
                        15, y, 150, 20, hwnd, NULL, hInst, NULL);
            g_hwndPassword = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "x",
                                            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                            170, y - 2, 200, 24, hwnd, (HMENU)ID_EDIT_PASSWORD, hInst, NULL);
            SendMessage(g_hwndPassword, WM_SETFONT, (WPARAM)g_hFont, TRUE);
            y += 40;
            
            // Load saved address
            {
                char saved_address[256] = {0};
                char saved_password[64] = {0};
                load_last_address(saved_address, sizeof(saved_address), saved_password, sizeof(saved_password));
                if (strlen(saved_address) > 0) {
                    SetWindowText(g_hwndAddress, saved_address);
                }
                if (strlen(saved_password) > 0) {
                    SetWindowText(g_hwndPassword, saved_password);
                }
            }
            
            // CPU Section
            HWND hCPUTitle = CreateWindow("STATIC", "=== CPU Mining ===",
                                          WS_CHILD | WS_VISIBLE,
                                          15, y, 200, 20, hwnd, NULL, hInst, NULL);
            SendMessage(hCPUTitle, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            y += 25;
            
            g_hwndCheckCPU = CreateWindow("BUTTON", "Enable CPU Mining",
                                          WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
                                          15, y, 150, 20, hwnd, (HMENU)ID_CHECK_CPU, hInst, NULL);
            SendMessage(g_hwndCheckCPU, BM_SETCHECK, BST_CHECKED, 0);
            SendMessage(g_hwndCheckCPU, WM_SETFONT, (WPARAM)g_hFont, TRUE);
            y += 28;
            
            CreateWindow("STATIC", "Power",
                        WS_CHILD | WS_VISIBLE,
                        15, y + 5, 50, 20, hwnd, NULL, hInst, NULL);
            g_hwndSliderCPU = CreateWindow(TRACKBAR_CLASS, NULL,
                                           WS_CHILD | WS_VISIBLE | TBS_AUTOTICKS | TBS_HORZ,
                                           70, y, 450, 30, hwnd, (HMENU)ID_SLIDER_CPU, hInst, NULL);
            SendMessage(g_hwndSliderCPU, TBM_SETRANGE, TRUE, MAKELPARAM(MIN_UTILIZATION_PERCENT, MAX_UTILIZATION_PERCENT));
            SendMessage(g_hwndSliderCPU, TBM_SETPOS, TRUE, DEFAULT_CPU_PERCENT);
            SendMessage(g_hwndSliderCPU, TBM_SETTICFREQ, 10, 0);
            
            char cpuLabel[32];
            snprintf(cpuLabel, sizeof(cpuLabel), "%d%%", DEFAULT_CPU_PERCENT);
            g_hwndLabelCPU = CreateWindow("STATIC", cpuLabel,
                                          WS_CHILD | WS_VISIBLE | SS_CENTER,
                                          530, y, 70, 35, hwnd, (HMENU)ID_LABEL_CPU_PCT, hInst, NULL);
            SendMessage(g_hwndLabelCPU, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            
            // CPU utilization graph (owner-drawn static control)
            g_hwndCpuGraph = CreateWindow("STATIC", NULL,
                                          WS_CHILD | WS_VISIBLE | SS_OWNERDRAW,
                                          610, y - 5, GRAPH_WIDTH, GRAPH_HEIGHT, hwnd, (HMENU)ID_CPU_GRAPH, hInst, NULL);
            y += 55;
            
            // GPU Section
            HWND hGPUTitle = CreateWindow("STATIC", "=== GPU Mining ===",
                                          WS_CHILD | WS_VISIBLE,
                                          15, y, 200, 20, hwnd, NULL, hInst, NULL);
            SendMessage(hGPUTitle, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            y += 25;
            
            g_hwndCheckGPU = CreateWindow("BUTTON", "Enable GPU Mining",
                                          WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
                                          15, y, 150, 20, hwnd, (HMENU)ID_CHECK_GPU, hInst, NULL);
            SendMessage(g_hwndCheckGPU, BM_SETCHECK, g_nGpuCount > 0 ? BST_CHECKED : BST_UNCHECKED, 0);
            EnableWindow(g_hwndCheckGPU, g_nGpuCount > 0);
            SendMessage(g_hwndCheckGPU, WM_SETFONT, (WPARAM)g_hFont, TRUE);
            y += 28;
            
            CreateWindow("STATIC", "Power",
                        WS_CHILD | WS_VISIBLE,
                        15, y + 5, 50, 20, hwnd, NULL, hInst, NULL);
            g_hwndSliderGPU = CreateWindow(TRACKBAR_CLASS, NULL,
                                           WS_CHILD | WS_VISIBLE | TBS_AUTOTICKS | TBS_HORZ,
                                           70, y, 450, 30, hwnd, (HMENU)ID_SLIDER_GPU, hInst, NULL);
            SendMessage(g_hwndSliderGPU, TBM_SETRANGE, TRUE, MAKELPARAM(MIN_UTILIZATION_PERCENT, MAX_UTILIZATION_PERCENT));
            SendMessage(g_hwndSliderGPU, TBM_SETPOS, TRUE, DEFAULT_GPU_PERCENT);
            SendMessage(g_hwndSliderGPU, TBM_SETTICFREQ, 10, 0);
            EnableWindow(g_hwndSliderGPU, g_nGpuCount > 0);
            
            char gpuLabel[32];
            snprintf(gpuLabel, sizeof(gpuLabel), "%d%%", DEFAULT_GPU_PERCENT);
            g_hwndLabelGPU = CreateWindow("STATIC", gpuLabel,
                                          WS_CHILD | WS_VISIBLE | SS_CENTER,
                                          530, y, 70, 35, hwnd, (HMENU)ID_LABEL_GPU_PCT, hInst, NULL);
            SendMessage(g_hwndLabelGPU, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            
            // GPU utilization graph (owner-drawn static control)
            g_hwndGpuGraph = CreateWindow("STATIC", NULL,
                                          WS_CHILD | WS_VISIBLE | SS_OWNERDRAW,
                                          610, y - 5, GRAPH_WIDTH, GRAPH_HEIGHT, hwnd, (HMENU)ID_GPU_GRAPH, hInst, NULL);
            y += 60;
            
            // Buttons
            g_hwndBtnStart = CreateWindow("BUTTON", "Generate Coins",
                                          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                          150, y, 150, 40, hwnd, (HMENU)ID_BTN_START, hInst, NULL);
            SendMessage(g_hwndBtnStart, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            
            g_hwndBtnStop = CreateWindow("BUTTON", "Stop Mining",
                                         WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON | WS_DISABLED,
                                         350, y, 150, 40, hwnd, (HMENU)ID_BTN_STOP, hInst, NULL);
            SendMessage(g_hwndBtnStop, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            
            g_hwndBtnLink = CreateWindow("BUTTON", "View My Stats on SoloPool",
                                         WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                         550, y, 200, 40, hwnd, (HMENU)ID_BTN_LINK, hInst, NULL);
            SendMessage(g_hwndBtnLink, WM_SETFONT, (WPARAM)g_hFont, TRUE);
            y += 55;
            
            // Statistics section
            HWND hStatsTitle = CreateWindow("STATIC", "=== Statistics ===",
                                            WS_CHILD | WS_VISIBLE,
                                            15, y, 200, 20, hwnd, NULL, hInst, NULL);
            SendMessage(hStatsTitle, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            y += 22;
            
            g_hwndStats = CreateWindow("STATIC", 
                "CPU: 0.00 MH/s | GPU: 0.00 MH/s | Total: 0.00 MH/s\r\n"
                "CPU: 0/0 | GPU: 0/0 | Total: 0/0 (100.0%) | SPM: 0.0\r\n"
                "Best: 0.0 (session) / 0.0 (ever) | Uptime: 00:00:00",
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                15, y, WINDOW_WIDTH - 50, 60, hwnd, (HMENU)ID_STATIC_STATS, hInst, NULL);
            SendMessage(g_hwndStats, WM_SETFONT, (WPARAM)g_hFontMono, TRUE);
            y += 65;
            
            // Log section
            HWND hLogTitle = CreateWindow("STATIC", "=== Live Log ===",
                                          WS_CHILD | WS_VISIBLE,
                                          15, y, 200, 20, hwnd, NULL, hInst, NULL);
            SendMessage(hLogTitle, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);
            y += 22;
            
            // Log window - calculate remaining height to fit in window
            int logHeight = WINDOW_HEIGHT - y - 50;  // 50px bottom margin
            g_hwndLog = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", "",
                                       WS_CHILD | WS_VISIBLE | WS_VSCROLL | 
                                       ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY,
                                       15, y, WINDOW_WIDTH - 45, logHeight, hwnd, (HMENU)ID_EDIT_LOG, hInst, NULL);
            SendMessage(g_hwndLog, WM_SETFONT, (WPARAM)g_hFontMono, TRUE);
            
            // Initialize NVML for GPU monitoring and start graph timer
            init_nvml();
            SetTimer(hwnd, ID_TIMER_GRAPH, GRAPH_SAMPLE_MS, NULL);
            
            return 0;
        }
        
        case WM_HSCROLL: {
            // Slider changed
            static int cpu_was_in_redzone = 0;  // Track previous state
            static int gpu_was_in_redzone = 0;
            
            if ((HWND)lParam == g_hwndSliderCPU) {
                int pos = (int)SendMessage(g_hwndSliderCPU, TBM_GETPOS, 0, 0);
                char buf[32];
                
                // v1.0.0: Red Zone - warn EVERY time crossing into red zone
                if (pos > REDZONE_THRESHOLD) {
                    snprintf(buf, sizeof(buf), "%d%%\r\nRED!", pos);
                    SetWindowText(g_hwndLabelCPU, buf);
                    // Show warning when ENTERING red zone (not while already in it)
                    if (!cpu_was_in_redzone) {
                        cpu_was_in_redzone = 1;
                        MessageBox(hwnd, 
                            "CPU RED ZONE ACTIVATED!\n\n"
                            "CPU is now running above 80% power.\n\n"
                            "WARNING:\n"
                            "- Increased heat and power consumption\n"
                            "- Higher CPU temperatures\n"
                            "- May cause system instability\n\n"
                            "Monitor your temps!",
                            "CPU Red Zone", MB_OK | MB_ICONWARNING);
                    }
                } else {
                    snprintf(buf, sizeof(buf), "%d%%", pos);
                    SetWindowText(g_hwndLabelCPU, buf);
                    cpu_was_in_redzone = 0;  // Reset when leaving red zone
                }
                g_miner.cpu_power_percent = pos;
                
            } else if ((HWND)lParam == g_hwndSliderGPU) {
                int pos = (int)SendMessage(g_hwndSliderGPU, TBM_GETPOS, 0, 0);
                char buf[32];
                
                // v1.0.0: Red Zone - warn EVERY time crossing into red zone
                if (pos > REDZONE_THRESHOLD) {
                    snprintf(buf, sizeof(buf), "%d%%\r\nRED!", pos);
                    SetWindowText(g_hwndLabelGPU, buf);
                    // Show warning when ENTERING red zone (not while already in it)
                    if (!gpu_was_in_redzone) {
                        gpu_was_in_redzone = 1;
                        MessageBox(hwnd, 
                            "GPU RED ZONE ACTIVATED!\n\n"
                            "GPU is now running above 80% power.\n\n"
                            "WARNING:\n"
                            "- Increased heat and power consumption\n"
                            "- Higher GPU temperatures\n"
                            "- Potential thermal throttling\n\n"
                            "Monitor your temps!",
                            "GPU Red Zone", MB_OK | MB_ICONWARNING);
                    }
                } else {
                    snprintf(buf, sizeof(buf), "%d%%", pos);
                    SetWindowText(g_hwndLabelGPU, buf);
                    gpu_was_in_redzone = 0;  // Reset when leaving red zone
                }
                g_miner.gpu_power_percent = pos;
            }
            return 0;
        }
        
        case WM_COMMAND: {
            int wmId = LOWORD(wParam);
            
            switch (wmId) {
                case ID_BTN_START:
                    StartMining();
                    break;
                    
                case ID_BTN_STOP:
                    StopMining();
                    break;
                    
                case ID_BTN_LINK: {
                    // Extract base address (before the dot if worker name exists)
                    char address[256] = {0};
                    GetWindowText(g_hwndAddress, address, sizeof(address));
                    
                    // Find the base address (before the worker name)
                    char base_addr[256] = {0};
                    char *dot = strchr(address, '.');
                    if (dot) {
                        size_t len = dot - address;
                        strncpy(base_addr, address, len);
                        base_addr[len] = '\0';
                    } else {
                        strncpy(base_addr, address, sizeof(base_addr) - 1);
                    }
                    
                    if (strlen(base_addr) > 10) {
                        char url[512];
                        snprintf(url, sizeof(url), 
                                 "https://www.solopool.com/user.html?network=mainnet&address=%s", 
                                 base_addr);
                        ShellExecute(NULL, "open", url, NULL, NULL, SW_SHOWNORMAL);
                    } else {
                        MessageBox(hwnd, "Please enter a valid Bitcoin address first", "Info", MB_OK | MB_ICONINFORMATION);
                    }
                    break;
                }
                
                case ID_CHECK_CPU:
                    g_miner.cpu_enabled = (SendMessage(g_hwndCheckCPU, BM_GETCHECK, 0, 0) == BST_CHECKED);
                    break;
                    
                case ID_CHECK_GPU:
                    g_miner.gpu_enabled = (SendMessage(g_hwndCheckGPU, BM_GETCHECK, 0, 0) == BST_CHECKED);
                    break;
            }
            return 0;
        }
        
        case WM_DRAWITEM: {
            LPDRAWITEMSTRUCT lpDIS = (LPDRAWITEMSTRUCT)lParam;
            if (lpDIS->CtlID == ID_GPU_GRAPH) {
                RECT rect = lpDIS->rcItem;
                draw_utilization_graph(lpDIS->hDC, &rect, g_gpuHistory, RGB(0, 200, 83), "GPU");
                return TRUE;
            } else if (lpDIS->CtlID == ID_CPU_GRAPH) {
                RECT rect = lpDIS->rcItem;
                draw_utilization_graph(lpDIS->hDC, &rect, g_cpuHistory, RGB(0, 120, 215), "CPU");
                return TRUE;
            }
            break;
        }
        
        case WM_TIMER:
            if (wParam == ID_TIMER_UPDATE) {
                UpdateGUIStats();
            } else if (wParam == ID_TIMER_GRAPH) {
                sample_utilization();
                if (g_hwndGpuGraph) InvalidateRect(g_hwndGpuGraph, NULL, FALSE);
                if (g_hwndCpuGraph) InvalidateRect(g_hwndCpuGraph, NULL, FALSE);
            } else if (wParam == ID_TIMER_LOG) {
                FlushLogBuffer();
            }
            return 0;
        
        case WM_CLOSE:
            if (g_miner.running) {
                if (MessageBox(hwnd, "Mining is in progress. Stop and exit?", 
                               "SoloPool Miner", MB_YESNO | MB_ICONQUESTION) != IDYES) {
                    return 0;
                }
                StopMining();
            }
            DestroyWindow(hwnd);
            return 0;
        
        case WM_DESTROY:
            KillTimer(hwnd, ID_TIMER_GRAPH);
            shutdown_nvml();
            if (g_hFont) DeleteObject(g_hFont);
            if (g_hFontBold) DeleteObject(g_hFontBold);
            if (g_hFontMono) DeleteObject(g_hFontMono);
            PostQuitMessage(0);
            return 0;
    }
    
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

// =============================================================================
// SECTION 24: Main Entry Point
// =============================================================================

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    (void)hPrevInstance;
    (void)lpCmdLine;
    
    // Initialize WinSock and critical sections
    WSADATA wsaData;
    WSAStartup(MAKEWORD(2, 2), &wsaData);
    InitializeCriticalSection(&g_csLog);
    InitializeCriticalSection(&g_csLogBuffer);
    InitializeCriticalSection(&g_stratum.cs);
    InitCommonControls();
    
    // Open log file for this session
    OpenLogFile();
    
    // Detect CPU features and set hash function
    detect_cpu_features();
    sha256d_80 = g_has_sha_ni ? sha256d_80_shani : sha256d_80_soft;
    
    // Get system info
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    g_nSystemCpuCount = si.dwNumberOfProcessors;
    
    // Initialize GPUs (CUDA + OpenCL)
    init_gpus();
    
    // Load best share from file
    load_best_share();
    
    // Set default power levels
    g_miner.cpu_power_percent = DEFAULT_CPU_PERCENT;
    g_miner.gpu_power_percent = DEFAULT_GPU_PERCENT;
    g_miner.cpu_enabled = 1;
    g_miner.gpu_enabled = (g_nGpuCount > 0);
    
    // Register window class
    WNDCLASSEX wc = {0};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = "SoloPoolMinerGUIClass";
    wc.hIconSm = LoadIcon(NULL, IDI_APPLICATION);
    RegisterClassEx(&wc);
    
    // Create main window
    g_hwnd = CreateWindowEx(
        0,
        "SoloPoolMinerGUIClass",
        "SoloPool.Com Miner v1.0.4 - CUDA + CPU Hybrid",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT,
        WINDOW_WIDTH, WINDOW_HEIGHT,
        NULL, NULL, hInstance, NULL
    );
    
    if (!g_hwnd) {
        MessageBox(NULL, "Failed to create window", "Error", MB_OK | MB_ICONERROR);
        return 1;
    }
    
    ShowWindow(g_hwnd, nCmdShow);
    UpdateWindow(g_hwnd);
    
    // Initial log message
    LogToGUI("SoloPool Miner v1.0.4 GUI ready");
    LogToGUI("CPU: %d cores | SHA: %s", g_nSystemCpuCount, g_has_sha_ni ? "SHA256-NI" : "Software");
    LogToGUI("GPU: %d CUDA device(s)", g_nGpuCount);
    if (g_miner.best_share_ever > 0) {
        LogToGUI("Best share ever: %.2f (%s)", g_miner.best_share_ever, g_miner.best_share_ever_source);
    }
    LogToGUI("Enter your BTCADDR.WORKERNAME and click 'Generate Coins' to start!");
    
    // Message loop
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    
    // Cleanup
    for (int i = 0; i < g_miner.gpu_count; i++) {
        if (g_miner.gpus[i].d_midstate) cudaFree(g_miner.gpus[i].d_midstate);
        if (g_miner.gpus[i].d_tail) cudaFree(g_miner.gpus[i].d_tail);
        if (g_miner.gpus[i].d_results) cudaFree(g_miner.gpus[i].d_results);
    }
    
    // Close log file
    CloseLogFile();
    
    DeleteCriticalSection(&g_csLog);
    DeleteCriticalSection(&g_csLogBuffer);
    DeleteCriticalSection(&g_stratum.cs);
    WSACleanup();
    
    return (int)msg.wParam;
}

// =============================================================================
// SECTION 25: Console Mode Main (for debugging)
// =============================================================================

#ifndef SUBSYSTEM_WINDOWS
int main(int argc, char *argv[]) {
    return WinMain(GetModuleHandle(NULL), NULL, GetCommandLine(), SW_SHOWNORMAL);
}
#endif
