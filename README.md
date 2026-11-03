# Code It!

An [Artemis](https://github.com/ls1intum/Artemis) client for tablets, built for the TU Dresden instance at `artemis-app.inf.tu-dresden.de`. The website's online editor is painful on an iPad, so this app puts the task on one side and files plus editor on the other, and submits with one button.

Not an official TU Dresden app.

- Log in with your Artemis account, not your ZIH password. You need eduVPN or the campus network, same as the website.
- Saving never submits. Only "Abgeben" does, after a confirmation.
- Edits stay on the tablet, so a dropped VPN loses nothing.
- A key row for `{ } ( ) ;` above the on-screen keyboard; with a hardware keyboard you get ⌘S, ⌘↩ and ⌘P instead.

The UI is German, and so are the identifiers in the code.

## Run

```bash
flutter run --dart-define=DEMO=true   # made-up course, no account needed
flutter run                            # real Artemis
flutter test
```

`tools/install.sh` builds a release and installs it on an iPad over USB or Wi‑Fi. Set `CODEIT_GERAET` to your iPad's UDID if more than one is around, and change `DEVELOPMENT_TEAM` in Xcode to your own team.

## Status

Tested on one iPad Pro with iPadOS 26. Android should build, but nobody has run it yet. Formulas (`$$…$$`) show as plain text.

## License

MIT, see [LICENSE](LICENSE).
