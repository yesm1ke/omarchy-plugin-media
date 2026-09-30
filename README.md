# Media for the Omarchy bar, with Cliamp

The stock Omarchy media widget reworked around the Cliamp terminal player and
keyboard use.

## Changes from stock

- **Always on the bar**, even with nothing playing, so there is something to
  click to start music from cold.
- **Start Cliamp** button in the popup while Cliamp is not running
  (`cliamp -d`).
- **Right click always opens the popup**; left and middle click still control
  the active player.
- **Keyboard navigation in the popup**: arrows move over previous / play-pause
  / next, the Start Cliamp button and the player list; Enter activates, Escape
  closes. The popup grabs keyboard focus, so this also works when it is
  opened with the `SUPER+CTRL+<n>` panel hotkey.
- **Quieter bar**: the scrolling track title appears only while the pointer is
  on the widget, instead of all the time.

## Install

```sh
omarchy plugin add https://github.com/yesm1ke/omarchy-plugin-media --enable
omarchy plugin disable omarchy.media   # the stock widget and service it replaces
```

## Staying current with Omarchy

This is a copy of the stock widget with changes on top, so it would not pick
up Omarchy's own fixes by itself. The repository keeps them apart:

- branch `upstream` holds the stock files exactly as Omarchy ships them, one
  commit per Omarchy version that changed them;
- branch `main` is `upstream` plus the changes described above.

After an Omarchy update, run `./sync-upstream` in the installed plugin
(`~/.config/omarchy/plugins/<id>/`). It records the installed stock files on
`upstream` and merges them into `main`; on a conflict it aborts the merge and
leaves everything as it was, to be resolved with `git merge upstream`.
`./sync-upstream --check` only reports whether anything changed. It can be run
automatically from an Omarchy `post-update` hook.

## License

MIT, see [LICENSE](LICENSE). Based on the Omarchy media widget, © David
Heinemeier Hansson, MIT.
