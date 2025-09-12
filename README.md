# AirSync 2.0 macOS app written in Swift

## Signing embedded CLI tools for App Store validation

This app embeds `adb` and `scrcpy`. For App Store submission, these executables must be sandboxed and code-signed with entitlements.

We include sandbox entitlements at:

- `airsync-mac/Binaries/adb_sandbox.entitlements`
- `airsync-mac/Binaries/scrcpy_sandbox.entitlements`

And a helper script:

- `airsync-mac/Scripts/sign-embedded-tools.sh`

Hook this script in Xcode:

1) Target: AirSync → Build Phases → + → New Run Script Phase
2) Place it after “Copy Files” that embeds the tools into `Contents/MacOS`.
3) Script:

```
${SRCROOT}/airsync-mac/Scripts/sign-embedded-tools.sh
```

Ensure the tools are copied into the app bundle (Contents/MacOS) during build. If not already, add a “Copy Files” phase targeting “Wrapper” and include `airsync-mac/Binaries/adb` and `airsync-mac/Binaries/scrcpy` as inputs, renaming the destination filenames to just `adb` and `scrcpy`.

The script signs them with the sandbox entitlements so validation no longer reports “App sandbox not enabled” for those executables.

Min : macOS 14.5

[![AirSync demo](https://img.youtube.com/vi/HDv0Hu9z294?si=dgycryP1T8QvPJYa/0.jpg)](https://www.youtube.com/watch?v=HDv0Hu9z294?si=dgycryP1T8QvPJYa)

### During beta testing, You can use the code `i-am-a-tester` to try out and test AirSync+ features. Also these + features are subject to change and currently they are limited because to test if the workflow works.

## [Help translating AirSync to your language on crowdin!](https://crwd.in/airsync/612ea64319db322fa1ed070574109c242534446)

<p align="center">
  <img src="https://github.com/user-attachments/assets/7c81bd2a-3799-44f2-b63a-350344f68e42" width="30%" />
  <img src="https://github.com/user-attachments/assets/58996c84-083f-4464-b0a5-bce069935898" width="30%" />
  <img src="https://github.com/user-attachments/assets/3f9d3113-1e16-4071-b1fc-f8f33a24c439" width="30%" />
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/8abdd977-6f8b-4037-b277-9457e65a6255" width="80%" />
</p>

## [Read Documentation and How-To](https://airsync.notion.site/)

## Contributors <3

<a href="https://github.com/sameerasw/airsync-mac/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=sameerasw/airsync-mac" />
</a>

<a href="https://star-history.com/#sameerasw/airsync-mac&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=sameerasw/airsync-mac&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=sameerasw/airsync-mac&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=sameerasw/airsync-mac&type=Date" />
 </picture>
</a>

## Thanks!

- To you, seriously… <3

### Libraries used

- [dagronf/QRCode](https://github.com/dagronf/QRCode)
- [httpswift/swifter](https://github.com/httpswift/swifter)
- [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle)
