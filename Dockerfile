# Use the official Ubuntu base image
FROM ubuntu:24.04 AS qt-clang-host-base

# Set build arguments
ARG QT_VERSION=6.7.2

# Take Distribution, Architecture, Compiler, JDK from https://doc.qt.io/qt-6/android.html

# sdkmanager --list | grep ndk
# Qt 6.5 LTS: 25.1.8937393
# Qt 6.7: 26.1.10909125
ARG ANDROID_NDK_VERSION=26.1.10909125

# https://developer.android.com/studio#command-line-tools-only
ARG CMDLINE_TOOLS_VERSION=11076708

# https://apilevels.com/
# sdkmanager --list | grep platforms
ARG ANDROID_PLATFORM=android-34
# sdkmanager --list | grep build-tools
ARG BUILD_TOOLS_VERSION=34.0.0

# sudo apt search openjdk-.*-jdk
# 11, 17, 21
ARG OPENJDK_VERSION=17

# Set environment variables
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_NDK_ROOT=${ANDROID_SDK_ROOT}/ndk/${ANDROID_NDK_VERSION}
ENV QT_DIR=/opt/Qt/${QT_VERSION}/android
ENV PATH=${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_NDK_ROOT}:${QT_DIR}/bin:${PATH}

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -yq \
    openjdk-${OPENJDK_VERSION}-jdk \
    wget \
    unzip \
    git \
    cmake \
    ninja-build \
    clang \
    libgl1-mesa-dev \
    xz-utils \
    && rm -rf "/var/lib/apt/lists/*"

# Download and install Android SDK
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    wget https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip -O /tmp/cmdline-tools.zip && \
    unzip /tmp/cmdline-tools.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools && \
    rm /tmp/cmdline-tools.zip && \
    mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    export PATH=${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${PATH} && \
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses && \
    sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${BUILD_TOOLS_VERSION}"

# Install Android NDK
RUN export PATH=${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${PATH} && \
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses && \
    sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "ndk;${ANDROID_NDK_VERSION}"

# Install Qt dependencies
RUN apt-get update && apt-get install -y \
    libclang-18-dev \
    build-essential \
    libssl-dev \
    libdbus-1-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libx11-dev \
    libx11-xcb-dev \
    libxext-dev \
    libxfixes-dev \
    libxi-dev \
    libxrender-dev \
    libxcb1-dev \
    libx11-xcb-dev \
    libxcb-glx0-dev \
    libxcb-keysyms1-dev \
    libxcb-image0-dev \
    libxcb-shm0-dev \
    libxcb-icccm4-dev \
    libxcb-sync-dev \
    libxcb-xfixes0-dev \
    libxcb-shape0-dev \
    libxcb-randr0-dev \
    libxcb-render-util0-dev \
    libxcb-util-dev \
    libxcb-xinerama0-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    && rm -rf "/var/lib/apt/lists/*"

FROM qt-clang-host-base AS qt-clang-host-builder

ARG QT_VERSION=6.7.2

# Download and install Qt for Android
RUN wget https://download.qt.io/archive/qt/${QT_VERSION%.*}/${QT_VERSION}/single/qt-everywhere-src-${QT_VERSION}.tar.xz -O /tmp/qt-everywhere-src.tar.xz && \
    tar -xf /tmp/qt-everywhere-src.tar.xz -C /opt && \
    rm /tmp/qt-everywhere-src.tar.xz

# Build host Qt
RUN mkdir -p /opt/build-host && cd /opt/build-host && \
    /opt/qt-everywhere-src-${QT_VERSION}/configure -nomake tests -nomake examples && \
    cmake --build . --target host_tools -- -j$(nproc)

FROM qt-clang-host-base AS qt-clang-host

ARG QT_VERSION=6.7.2

# Copy only necessary install to save storage
COPY --from=qt-clang-host-builder /opt/build-host /opt/build-host

FROM qt-clang-host-builder AS qt-clang-android-builder
ARG QT_VERSION=6.7.2

# arm64-v8a, x86_64, x86, and armeabi-v7a
ARG ANDROID_ARCH=arm64-v8a
ARG ANDROID_NDK_VERSION=26.1.10909125

# Set environment variables
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_NDK_ROOT=${ANDROID_SDK_ROOT}/ndk/${ANDROID_NDK_VERSION}
ENV QT_DIR=/opt/Qt/${QT_VERSION}/android
ENV PATH=${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_NDK_ROOT}:${QT_DIR}/bin:${PATH}

# Build Qt for Android
RUN mkdir -p /opt/build-qt-android-${ANDROID_ARCH} && cd /opt/build-qt-android-${ANDROID_ARCH} && \
    /opt/qt-everywhere-src-${QT_VERSION}/configure -qt-host-path /opt/build-host/qtbase/ -prefix ${QT_DIR} -android-abis ${ANDROID_ARCH} -android-sdk ${ANDROID_SDK_ROOT} -android-ndk ${ANDROID_NDK_ROOT}

RUN cd /opt/build-qt-android-${ANDROID_ARCH} && \
    cmake --build . --parallel -- -j$(nproc) && \
    cmake --install .

FROM qt-clang-host-base AS qt-clang-android
ARG QT_VERSION=6.7.2

COPY --from=qt-clang-host-builder /opt/build-host /opt/build-host
COPY --from=qt-clang-android-builder /opt/Qt/${QT_VERSION} /opt/Qt/${QT_VERSION}
