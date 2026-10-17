# Tilda for macOS

Native dropdown terminal for macOS 13 or newer. Supports tabs, split panes, scrollback search, SSH location detection, themes, and optional launch at login.

## Install

Open the DMG in `dist/` and drag Tilda to Applications. The included build is for Apple Silicon and is locally signed, without Apple notarization.

Press **Control + grave accent** to show or hide the terminal, **Command + T** for a new tab, and **Command + comma** for Settings. On first launch, choose whether to enable launch at login. Restored layouts start fresh shells; running commands and scrollback are not restored.

## Build

Requires Xcode with Swift 6 or newer. The first build downloads pinned SwiftPM dependencies.

```sh
bash scripts/package.sh
```

This creates `dist/Tilda-<version>-<architecture>.dmg`. Compilation and packaging use temporary directories that are removed on exit. To build an app bundle separately, run `bash scripts/build.sh`.

## License

[MIT](LICENSE). Uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) under its [MIT license](Resources/Licenses/SwiftTerm-LICENSE.txt). The development dependency Swift Argument Parser retains its [license](Resources/Licenses/SwiftArgumentParser-LICENSE.txt).

Inspired by [Tilda](https://github.com/lanoxx/tilda); this is an independent macOS implementation.
