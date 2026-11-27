# Live Plugin Pin

An Apple Silicon VST3 audio effect for Ableton Live on macOS 14 or later.
It keeps Live's floating plug-in editors visible when another application
has focus. Audio passes through unchanged.

## Use

Add one instance to an audio track, Return, Main, or after the instrument on
a MIDI track. Live's Device Activator controls pinning for the entire set.
Turning it on pins open editors and any editors opened later. Turning it off
releases the pins. Hiding or closing an editor releases its pin.

## Build

Use CMake 3.25 or later and Xcode. Check out the Steinberg VST3 SDK next to
this repository, or pass its path to CMake with `-DVST3_SDK_DIR=/path/to/vst3sdk`.

```sh
git clone https://github.com/steinbergmedia/vst3sdk.git ../vst3sdk
git -C ../vst3sdk checkout 3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96
git -C ../vst3sdk submodule update --init --recursive

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --target LivePluginPin --parallel
codesign --force --sign - "build/Live Plugin Pin.vst3"
```

With Command Line Tools alone, the SDK can't detect an Xcode version.
Set `XCODE_VERSION` in the environment and pass the same version to CMake
with `-DXCODE_VERSION=...`. The local release build used `27.2`.

## Install

Quit Live and copy `build/Live Plugin Pin.vst3` to
`~/Library/Audio/Plug-Ins/VST3` or `/Library/Audio/Plug-Ins/VST3`.
Replace the existing bundle if updating. Restart Live and rescan plug-ins
in **Settings > Plug-Ins** if needed.
