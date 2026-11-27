# Live Plugin Pin

Ableton Live hides its plug-in windows when you switch to another app.
Live Plugin Pin keeps them visible on top while another app has the focus.
For example, you can use a browser and keep a plug-in window in view, on the
same monitor or on a second monitor.

It is a VST3 audio effect. Audio passes through unchanged.

Requirements: a Mac with Apple Silicon, macOS 14 or later, and Ableton Live
with VST3 plug-ins enabled.

## Install

1. Download the zip from the latest
   [release](https://github.com/ivnvxd/live-plugin-pin/releases/latest) and open it.
2. Quit Live.
3. Move `Live Plugin Pin.vst3` to `~/Library/Audio/Plug-Ins/VST3`.
   If an older version is there, replace it.
4. The plug-in is not signed by Apple, so macOS blocks it. To allow it,
   run this command once in Terminal:

   ```sh
   xattr -dr com.apple.quarantine ~/Library/Audio/Plug-Ins/VST3/"Live Plugin Pin.vst3"
   ```

5. Start Live. The plug-in is in the browser at
   **Plug-Ins > VST3 > ivnvxd**. If it is not there, open
   **Settings > Plug-Ins**. Make sure that **Use VST3 Plug-in System Folders**
   is on, then click **Rescan**.

## Use

Add one instance to any audio track, Return track or the Main track.
Use one instance for each Live Set.

- Device on: all open plug-in windows stay visible, and plug-in windows
  that you open later also stay visible.
- Device off: Live hides plug-in windows again when you switch apps.
- If you close or hide a plug-in window, it closes as usual.

The device has one setting, **Stay Above**:

- **Live** (default): plug-in windows stay above Live, but the app that you
  use comes in front of them.
- **All Apps**: plug-in windows stay above the windows of all apps.

## Limits

- The plug-in uses internal behavior of Live. A Live update can stop it
  from working. If this happens, open an issue.
- In hosts other than Live, it does nothing.

## Build from source

You need Xcode and CMake 3.25 or later.

```sh
git clone https://github.com/steinbergmedia/vst3sdk.git ../vst3sdk
git -C ../vst3sdk checkout 3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96
git -C ../vst3sdk submodule update --init base cmake pluginterfaces public.sdk

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --target LivePluginPin --parallel
codesign --force --sign - "build/Live Plugin Pin.vst3"
```

If you have only the Command Line Tools and not Xcode, set the same Xcode version
in the environment and in CMake, for example
`XCODE_VERSION=16.0 cmake ... -DXCODE_VERSION=16.0`.

To make a release, change the version in `CMakeLists.txt`, then push a tag
with the same version, for example `v0.1.0`. GitHub Actions builds the
plug-in and makes a draft release. Test the draft, then publish it.

## Support

Thank you for using this project! If you find it helpful and want to support my work, kindly consider buying me a coffee. Your support is greatly appreciated!

<a href="https://www.buymeacoffee.com/ivnvxd" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="60" width="217"></a>

If you like the project, do not forget to give it a star! :star:

## License

MIT, see [LICENSE](LICENSE). The VST3 SDK is MIT-licensed by Steinberg, see
[STEINBERG-SDK-LICENSE.txt](STEINBERG-SDK-LICENSE.txt).
