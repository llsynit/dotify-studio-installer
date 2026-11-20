[![Build Status](https://travis-ci.com/brailleapps/dotify-studio-installer.svg?branch=master)](https://travis-ci.com/brailleapps/dotify-studio-installer)

# Dotify Studio Installer #
Provides an installer för Dotify Studio, a graphical user interface for creating, managing and embossing PEF-files.

## Download ##
Download the installer for your computer from the [latest release](../../releases/latest): a .dmg for macOS (one for Apple Silicon and one for Intel Macs) or a .msi for Windows. Java is included.

## Building ##
Build an installer on the target platform with the corresponding command.
  
| Platform  | Command                          |
| :---------| :------------------------------- |
| Windows  (x64) | `gradlew msi`                |
| Linux     | `./gradlew rpm`              |
| Linux     | `./gradlew deb`              |
| macOS (Apple Silicon) | `./gradlew dmg` on an Apple Silicon Mac |
| macOS (Intel) | `./gradlew dmg -PtargetArch=x64` (on any Mac) |

The installers are written to `build/distributions`. Each macOS installer bundles a Java runtime for one architecture, so there is one for Apple Silicon and one for Intel Macs.

### Testing ###
`scripts/test-dmg.sh <dmg>` and `scripts/test-msi.ps1 <msi>` check that an installer contains what it should and that the app starts. An Intel installer can be tested on an Apple Silicon Mac with Rosetta.

### Signing for distribution ###
Without signing, macOS blocks the app once it has been downloaded. To sign and notarize the macOS installer, you need a "Developer ID Application" certificate in the keychain and a notarization profile (`xcrun notarytool store-credentials <profile>`):

    ./gradlew dmg -PmacSigningIdentity="Developer ID Application: <name> (<team id>)" -PmacNotaryProfile=<profile>

### Continuous integration ###
`.github/workflows/installers.yml` builds and tests all three installers on GitHub Actions on every push. Pushing a tag `v<version>` that matches `version` in `gradle.properties` also publishes a GitHub release with the installers attached, once they have all passed their tests. The workflow file lists the secrets that turn on signing.

## Requirements & Compatibility ##
Building requires Java 21 or later. The macOS and Windows installers download and bundle a Java 21 runtime that includes JavaFX ([Azul Zulu FX](https://www.azul.com/downloads/?package=jdk-fx)). The Linux packages don't bundle one, so a Java 21 runtime with JavaFX must be installed.

Until the Java 21 version of dotify-studio is released, publish it locally first: run `./gradlew publishToMavenLocal` in the dotify-studio repo. The version that gets packaged is set by `dotifyStudioVersion` in `gradle.properties`.

| Platform  | Requirement                                                          |
| :---------| :------------------------------------------------------------------- |
| Windows   | Wix Toolset or WixEdit must be installed                             |
| Linux     | Lintian, FakeRoot <br> on Ubuntu: `apt-get install lintian fakeroot` |
| Linux     | rpm for creating RPM packages: `apt-get install rpm`              |