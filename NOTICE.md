# Notice

**Vibe Loop** is a modified version ("fork") of **Lively Wallpaper**.

- Upstream project: Lively Wallpaper — https://github.com/rocksdanister/lively
- Upstream author: Dani John (rocksdanister) and the Lively Wallpaper contributors
- Upstream license: GNU General Public License v3.0 (see [LICENSE](LICENSE))

Vibe Loop is distributed under the same GPL-3.0 license. All upstream copyright notices, credits
and third-party license notices are kept. The upstream Git history is kept in this repository,
and it is the authoritative record of who wrote what.

## Modifications

Starting from upstream `dev/personal-screensaver` @ `25a0a5f`, Vibe Loop changes the product name,
executable name, Windows identifiers (mutex, IPC pipe, installer AppId, startup entry, storage
folders, MSIX identity), user-visible branding, and turns off upstream-operated online services
(update check, online gallery). The full list is in
[docs/vibe-loop/IDENTITY_MIGRATION.md](docs/vibe-loop/IDENTITY_MIGRATION.md), and every change can
be found in the Git history.

## Trademarks and affiliation

"Lively Wallpaper" and its logo belong to their respective owners. Vibe Loop is not affiliated with,
sponsored by, or endorsed by the Lively Wallpaper project. The Lively name is still used where it
describes the upstream project, the attribution, or the Lively wallpaper file format that Vibe Loop
stays compatible with.

## Third-party components

Third-party libraries and assets keep their own licenses. Upstream lists them at
https://livelywallpaper.net/attribution/ (also linked from the in-app About page). NuGet package
licenses are listed in each package's metadata.
