#!/bin/bash

# Some logics of this script are copied from [scripts/build_kernel]. Thanks to UtsavBalar1231.

# Ensure the script exits on error
set -e

# 确保正确设置KSU_VERSION_FULL
if [ -n "$KSU_VERSION_FULL" ]; then
    echo "使用自定义KSU版本: $KSU_VERSION_FULL"
    KSU_ZIP_STR="$KSU_VERSION_FULL"
fi

TOOLCHAIN_PATH=$(pwd)/toolchain/proton-clang/bin
GIT_COMMIT_ID=$(git rev-parse --short=13 HEAD)
TARGET_DEVICE=$1
KSU_VERSION=$2
ADDITIONAL=$3
TARGET_SYSTEM=$4
KSU_META=$5  # 新增第5个参数用于KSU_META

# 确保SukiSU-Ultra正确使用
if [[ "$KSU_VERSION" == "sukisu-ultra" && -z "$KSU_META" ]]; then
    KSU_META="susfs-main/Numbersf"
fi

if [ -z "$1" ]; then
    echo "Error: No argument provided, please specific a target device." 
    exit 1
fi

if [ ! -d $TOOLCHAIN_PATH ]; then
    echo "TOOLCHAIN_PATH [$TOOLCHAIN_PATH] does not exist."
    exit 1
fi

echo "TOOLCHAIN_PATH: [$TOOLCHAIN_PATH]"
export PATH="$TOOLCHAIN_PATH:$PATH"

if ! command -v aarch64-linux-gnu-ld >/dev/null 2>&1; then
    echo "[aarch64-linux-gnu-ld] does not exist, please check your environment."
    exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
    echo "[clang] does not exist, please check your environment."
    exit 1
fi

export CCACHE_DIR="$HOME/.cache/ccache_mikernel" 
export CC="ccache gcc"
export CXX="ccache g++"
export PATH="/usr/lib/ccache:$PATH"
echo "CCACHE_DIR: [$CCACHE_DIR]"

MAKE_ARGS="ARCH=arm64 SUBARCH=arm64 O=out CC=clang CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- CLANG_TRIPLE=aarch64-linux-gnu-"

if [ "$1" == "j1" ]; then
    make $MAKE_ARGS -j1
    exit
fi

if [ "$1" == "continue" ]; then
    make $MAKE_ARGS -j$(nproc)
    exit
fi

if [ ! -f "arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]; then
    echo "No target device [${TARGET_DEVICE}] found."
    ls arch/arm64/configs/*_defconfig
    exit 1
fi

echo "[clang --version]:"
clang --version

KERNEL_SRC=$(pwd)
SuSFS_ENABLE=0
KPM_ENABLE=0

echo "TARGET_DEVICE: $TARGET_DEVICE"

KSU_ENABLE=$([[ "$KSU_VERSION" == "ksu" || "$KSU_VERSION" == "rksu" || "$KSU_VERSION" == "sukisu" || "$KSU_VERSION" == "sukisu-ultra" ]] && echo 1 || echo 0)

if [ "$ADDITIONAL" == "susfs-kpm" ]; then
    SuSFS_ENABLE=1
    KPM_ENABLE=1
    echo "Enable SuSFS and KPM"
elif [ "$ADDITIONAL" == "susfs" ]; then
    SuSFS_ENABLE=1
    echo "Enable SuSFS"
elif [ "$ADDITIONAL" == "kpm" ]; then
    KPM_ENABLE=1
    echo "Enable KPM"
else 
    echo "The additional function is not enabled"
fi

# SukiSU-Ultra特殊处理
if [ "$KSU_VERSION" == "sukisu-ultra" ]; then
    echo "===== 处理SukiSU-Ultra ====="
    # 使用KSU_META参数
    BRANCH_NAME="${KSU_META%%/*}"
    CUSTOM_TAG="${KSU_META#*/}"
    
    echo "分支名: $BRANCH_NAME"
    echo "自定义版本标识: $CUSTOM_TAG"
    
    # 确保目录存在
    if [ ! -d "KernelSU" ]; then
        echo "下载SukiSU-Ultra: $BRANCH_NAME"
        git clone --depth=1 --branch=$BRANCH_NAME https://github.com/SukiSU-Ultra/SukiSU-Ultra.git
        mv SukiSU-Ultra KernelSU
    else
        echo "使用已有的SukiSU-Ultra目录"
    fi
    
    cd KernelSU
    KSU_API_VERSION=$(curl -fsSL "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/$BRANCH_NAME/kernel/Makefile" | \
        grep -m1 "KSU_VERSION_API :=" | awk -F'= ' '{print $2}' | tr -d '[:space:]')
    [[ -z "$KSU_API_VERSION" ]] && KSU_API_VERSION="3.1.7"
    
    echo "KSU_API_VERSION=$KSU_API_VERSION"
    
    KSU_VERSION_FULL="v$KSU_API_VERSION-$CUSTOM_TAG@$BRANCH_NAME"
    echo "KSU_VERSION_FULL=$KSU_VERSION_FULL"
    
    # 直接写入Makefile
    cat << EOF > kernel/Makefile
# SukiSU-Ultra自动配置
KSU_VERSION_API := $KSU_API_VERSION
KSU_VERSION_FULL := $KSU_VERSION_FULL
EOF
    
    cd ..
    
    if [ "$SuSFS_ENABLE" -eq 1 ]; then
        KSU_ZIP_STR="SukiSU-Ultra_SuSFS"
    else
        KSU_ZIP_STR="SukiSU-Ultra"
    fi
    echo "KSU_ZIP_STR设置为: $KSU_ZIP_STR"
fi

# 其他KSU版本处理
if [ "$KSU_VERSION" == "ksu" ]; then
    KSU_ZIP_STR=${KSU_ZIP_STR:-"KernelSU"}
    echo "KSU is enabled"
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
elif [[ "$KSU_VERSION" == "ksu" && "$SuSFS_ENABLE" -eq 1 ]]; then
    echo "Official KernelSU not supported SuSFS"
    exit 1
elif [[ "$KSU_VERSION" == "rksu" && "$SuSFS_ENABLE" -eq 1 ]]; then
    KSU_ZIP_STR=${KSU_ZIP_STR:-"RKSU_SuSFS"}
    echo "RKSU && SuSFS is enabled"
    curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s susfs-v1.5.5
elif [ "$KSU_VERSION" == "rksu" ]; then
    KSU_ZIP_STR=${KSU_ZIP_STR:-"RKSU"}
    echo "RKSU is enabled"
    curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s main
elif [[ "$KSU_VERSION" == "sukisu" && "$SuSFS_ENABLE" -eq 1 ]]; then
    KSU_ZIP_STR=${KSU_ZIP_STR:-"SukiSU_SuSFS"}
    echo "SukiSU && SuSFS is enabled"
    curl -LSs "https://raw.githubusercontent.com/ShirkNeko/KernelSU/main/kernel/setup.sh" | bash -s susfs-dev
elif [ "$KSU_VERSION" == "sukisu" ]; then
    KSU_ZIP_STR=${KSU_ZIP_STR:-"SukiSU"}
    echo "SukiSU is enabled"
    curl -LSs "https://raw.githubusercontent.com/ShirkNeko/KernelSU/main/kernel/setup.sh" | bash -s dev
fi

echo "开始构建: $TARGET_DEVICE"
rm -rf out/
rm -rf anykernel/

echo "Clone AnyKernel3 for packing kernel (repo: https://github.com/liyafe1997/AnyKernel3)"
git clone https://github.com/liyafe1997/AnyKernel3 -b kona --single-branch --depth=1 anykernel

Build_AOSP(){
# ------------- Building for AOSP -------------
    echo "Building for AOSP......"
    make $MAKE_ARGS ${TARGET_DEVICE}_defconfig

    SET_CONFIG
 
    (echo > .scmversion && scripts/config --file out/.config -d LOCALVERSION_AUTO --set-str CONFIG_LOCALVERSION "-${GIT_COMMIT_ID}" >/dev/null)
    
    export KBUILD_BUILD_TIMESTAMP="$(date '+%a %b %d %H:%M:%S CST 2023')"


    make $MAKE_ARGS -j$(nproc)
    
    Image_Repack

    echo "Build for AOSP finished."

    # ------------- End of Building for AOSP -------------
}


Build_MIUI(){
    # ------------- Building for MIUI -------------


    echo "Clearning [out/] and build for MIUI....."
    rm -rf out/

    dts_source=arch/arm64/boot/dts/vendor/qcom

    # Backup dts
    cp -a ${dts_source} .dts.bak

    # Correct panel dimensions on MIUI builds
    sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j1s*
    sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j2*
    sed -i 's/<155>/<1544>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
    sed -i 's/<155>/<1545>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j1s*
    sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j2*

    # Enable back mi smartfps while disabling qsync min refresh-rate
    sed -i 's/\/\/ mi,mdss-dsi-pan-enable-smart-fps/mi,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
    sed -i 's/\/\/ mi,mdss-dsi-smart-fps-max_framerate/mi,mdss-dsi-smart-fps-max_framerate/g' ${dts_source}/dsi-panel*
    sed -i 's/\/\/ qcom,mdss-dsi-pan-enable-smart-fps/qcom,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
    sed -i 's/qcom,mdss-dsi-qsync-min-refresh-rate/\/\/qcom,mdss-dsi-qsync-min-refresh-rate/g' ${dts_source}/dsi-panel*

    # Enable back refresh rates supported on MIUI
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-36-02-0c-dsc-video.dtsi
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0a-dsc-video.dtsi
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0b-dsc-video.dtsi
    sed -i 's/144 120 90 60/144 120 90 60 50 48 30/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi


    # Enable back brightness control from dtsi
    sed -i 's/\/\/39 00 00 00 00 00 03 51 03 FF/39 00 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 03 51 0D FF/39 00 00 00 00 00 03 51 0D FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 01 00 03 51 03 FF/39 01 00 00 01 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 11 00 03 51 03 FF/39 01 00 00 11 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi

    make $MAKE_ARGS ${TARGET_DEVICE}_defconfig

    SET_CONFIG MIUI

    (echo > .scmversion && scripts/config --file out/.config -d LOCALVERSION_AUTO --set-str CONFIG_LOCALVERSION "-${GIT_COMMIT_ID}" >/dev/null)
    
    export KBUILD_BUILD_TIMESTAMP="$(date '+%a %b %d %H:%M:%S CST 2023')"


    make $MAKE_ARGS -j$(nproc)

    Image_Repack MIUI
    # ------------- End of Building for MIUI -------------

}

SET_CONFIG(){
    if [ "$1" == "MIUI" ]; then
        scripts/config --file out/.config \
            --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
            -e PERF_CRITICAL_RT_TASK	\
            -e SF_BINDER		\
            -e OVERLAY_FS		\
            -d DEBUG_FS \
            -e MIGT \
            -e MIGT_ENERGY_MODEL \
            -e MIHW \
            -e PACKAGE_RUNTIME_INFO \
            -e BINDER_OPT \
            -e KPERFEVENTS \
            -e MILLET \
            -e PERF_HUMANTASK \
            -d LTO_CLANG \
            -d LOCALVERSION_AUTO \
            -e SF_BINDER \
            -e XIAOMI_MIUI \
            -d MI_MEMORY_SYSFS \
            -e TASK_DELAY_ACCT \
            -e MIUI_ZRAM_MEMORY_TRACKING \
            -d CONFIG_MODULE_SIG_SHA512 \
            -d CONFIG_MODULE_SIG_HASH \
            -e MI_FRAGMENTION \
            -e PERF_HELPER \
            -e BOOTUP_RECLAIM \
            -e MI_RECLAIM \
            -e RTMM
    fi
    
    if [ "$KSU_ENABLE" -eq 1 ]; then
        scripts/config --file out/.config -e KSU
    else
        scripts/config --file out/.config -d KSU
    fi
   
    # Enable the KSU_MANUAL_HOOK for sukisu-ultra
    if [ "$KSU_VERSION" == "sukisu-ultra" ];then
        scripts/config --file out/.config -e KSU_MANUAL_HOOK
    else
        scripts/config --file out/.config -e KSU_MANUAL_HOOK
    fi

    # Config KPM 
    if [ "$KPM_ENABLE" -eq 1 ]; then
        scripts/config --file out/.config \
            -e KPM \
            -e KALLSYMS \
            -e KALLSYMS_ALL
    else 
        scripts/config --file out/.config \
            -d KPM \
            -d KALLSYMS \
            -d KALLSYMS_ALL
    fi

    if [ "$SuSFS_ENABLE" -eq 1 ];then
        scripts/config --file out/.config \
            -e KSU_SUSFS \
            -e KSU_SUSFS_HAS_MAGIC_MOUNT \
            -e KSU_SUSFS_SUS_PATH \
            -e KSU_SUSFS_SUS_MOUNT \
            -e KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT \
            -e KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
            -e KSU_SUSFS_SUS_KSTAT \
            -e KSU_SUSFS_TRY_UMOUNT \
            -e KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT \
            -e KSU_SUSFS_SPOOF_UNAME \
            -e KSU_SUSFS_ENABLE_LOG \
            -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
            -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
            -e KSU_SUSFS_OPEN_REDIRECT
     else
        scripts/config --file out/.config \
            -d KSU_SUSFS \
            -d KSU_SUSFS_HAS_MAGIC_MOUNT \
            -d KSU_SUSFS_SUS_PATH \
            -d KSU_SUSFS_SUS_MOUNT \
            -d KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT \
            -d KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
            -d KSU_SUSFS_SUS_KSTAT \
            -d KSU_SUSFS_TRY_UMOUNT \
            -d KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT \
            -d KSU_SUSFS_SPOOF_UNAME \
            -d KSU_SUSFS_ENABLE_LOG \
            -d KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
            -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
            -d KSU_SUSFS_OPEN_REDIRECT
    fi
}

Image_Repack(){
    if [ -f "out/arch/arm64/boot/Image" ]; then
        echo "The file [out/arch/arm64/boot/Image] exists. AOSP Build successfully."
    else
        echo "The file [out/arch/arm64/boot/Image] does not exist. Seems AOSP build failed."
        exit 1
    fi

    # KPM Patch
    if [[ "$KPM_ENABLE" -eq 1 && "$KSU_VERSION" == "sukisu-ultra" ]]; then
        Patch_KPM
    fi

    echo "Generating [out/arch/arm64/boot/dtb]......"
    find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + >out/arch/arm64/boot/dtb

    # Restore modified dts
    if [ "$1" == "MIUI" ]; then
        rm -rf ${dts_source}
        mv .dts.bak ${dts_source}
    fi

    rm -rf anykernel/kernels/

    mkdir -p anykernel/kernels/

    cp out/arch/arm64/boot/Image anykernel/kernels/
    cp out/arch/arm64/boot/dtb anykernel/kernels/

    cd anykernel 

    if [ "$1" == "MIUI" ]; then
        ZIP_FILENAME=Kernel_MIUI_${TARGET_DEVICE}_${KSU_ZIP_STR}_$(date +'%Y%m%d_%H%M%S')_anykernel3_${GIT_COMMIT_ID}.zip
    else
        ZIP_FILENAME=Kernel_AOSP_${TARGET_DEVICE}_${KSU_ZIP_STR}_$(date +'%Y%m%d_%H%M%S')_anykernel3_${GIT_COMMIT_ID}.zip
    fi

    zip -r9 $ZIP_FILENAME ./* -x .git .gitignore out/ ./*.zip

    mv $ZIP_FILENAME ../

    cd ..
}

Patch_KPM(){
    cd out/arch/arm64/boot
    curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/patch_linux" -o patch
    chmod +x patch
    ./patch
    if [ $? -eq 0 ]; then
        rm -f Image
        mv oImage Image
        echo "Image file repair complete"
    else
        echo "KPM Patch Failed, Use Original Image"
    fi
    
    cd $KERNEL_SRC

}

if [ "$TARGET_SYSTEM" == "aosp" ];then
    Build_AOSP
elif [ "$TARGET_SYSTEM" == "miui" ];then
    Build_MIUI
else
    Build_AOSP
    Build_MIUI
fi
    
echo "Done. The flashable zip is: [./$ZIP_FILENAME]"
