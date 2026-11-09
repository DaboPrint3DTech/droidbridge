# DroidBridge

A native macOS app (SwiftUI) to browse an Android phone's storage and transfer files to and from your Mac.

## Requirements

- macOS 13 or later
- Xcode or the Command Line Tools (`xcode-select --install`)
- adb: `brew install android-platform-tools` (or Google's Platform-Tools, with `adb` copied to `/usr/local/bin`)
- On the phone: Developer options → **USB debugging** turned on

## Build and run

```bash
git clone https://github.com/DaboPrint3DTech/droidbridge.git
cd droidbridge
chmod +x build.sh
./build.sh
open DroidBridge.app
```

Alternatively: `swift run` from the project folder.

## Install the app (Launchpad, Dock, Spotlight)

`build.sh` creates `DroidBridge.app` in the project folder. To have it in Launchpad like any other app, copy it to `/Applications`:

```bash
./build.sh
rm -rf /Applications/DroidBridge.app
ditto DroidBridge.app /Applications/DroidBridge.app
```

After a few seconds DroidBridge shows up in Launchpad; you can also find it with Spotlight (⌘-Space, "DroidBridge"). To keep it in the Dock: open it, right-click its Dock icon → Options → Keep in Dock.

If the icon does not appear right away, force the app to register:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/DroidBridge.app
```

**Updating:** the copy in `/Applications` does not change on its own after you edit the code. Run the three commands above again (build, remove the old copy, copy the new one).

**Uninstalling:** `rm -rf /Applications/DroidBridge.app` (cached thumbnails stay in `~/Library/Caches/DroidBridge` and can be deleted by hand).

The app is ad-hoc signed, so it is meant for the Mac you build it on. If you copy it to another Mac, macOS may block it on first launch: right-click the app → Open, or System Settings → Privacy & Security → Open Anyway.

## Usage

1. Connect the phone over USB and accept the USB debugging prompt.
2. The device appears in the sidebar.
3. Double-click a folder to open it. Double-click an image to view it in the gallery, or any other file to download it to Downloads.
4. Drag files into the window to send them to the phone; the toolbar lets you download, create folders and delete, and the context menu (right-click) lets you rename.

### Folder tree

Under the phone's name in the sidebar there is the tree of the internal storage. Clicking a folder opens it in the main pane. The arrow on the left expands or collapses a branch: subfolders are read from the phone only when needed. When you navigate from the main pane (double-click, "Enclosing folder"), the tree opens by itself down to the folder you are in, which stays highlighted.

### About the app

At the bottom of the sidebar there is "About DroidBridge", also available from the app menu. It shows the version, creator, adb version and path, and the operating system. The app's details (creator, year, description) are all in `Sources/DroidBridge/AppInfo.swift`; the version is set in `build.sh`.

### Logo and icon

The logo (a smartphone connecting to an iMac, with the orange DaboPrint3D thumbs-up badge in the bottom-right corner, the same one used by GoPro Connector) is in `Resources/AppIcon.png` (1024×1024). The vector source of the artwork without the badge is `Resources/AppIcon.svg`; the badge is drawn on top by `swift tools/add_badge.swift <icon-without-badge.png> Resources/AppIcon.png`. `build.sh` turns it into `AppIcon.icns` and puts it in the bundle, so it shows in the Dock, in Finder, in the About window and on the "Connect your Android phone" screen. To change it, replace `AppIcon.png` with another 1024 px square image and run `./build.sh` again. With `swift run` the app is not a bundle and shows the generic icon.

### Views

The picker in the toolbar switches the view:

- **List**: a table with Name, Size, Kind, Modified. Images get a small thumbnail next to the name.
- **Grid**: large icons with image previews. The slider at the bottom sets the size. ⌘-click adds to or removes from the selection, ⇧-click selects a range.
- **Gallery**: a large image in the middle with a thumbnail strip below. Use the ← → arrows (or the buttons on the sides) to move between images; click a thumbnail to jump to it.

The "Previews" switch at the bottom turns off thumbnails in the list and grid.

### Filtering and sorting

- The search field in the toolbar filters by name.
- The "Filter by Kind" menu shows only folders, images, videos, audio, documents or other files.
- In the list, clicking a column header sorts by that column; clicking again reverses the order.
- The "Sort" menu does the same in every view and lets you choose whether folders come first.
- Actions (download, delete, rename) only affect visible items: anything hidden by a filter is left untouched.

### Previews and cache

To make a preview, the app downloads the image from the phone, resizes it and keeps only the thumbnail in `~/Library/Caches/DroidBridge`. Previews are generated only for what is visible on screen. You can clear the cache from the menu at the bottom right (⋯).

## Limitations

- Uses ADB, not MTP: USB debugging must be on.
- Does not mount the phone as a drive in Finder.
- Dragging from the window to Finder is not implemented: use "Download".
- Transfer progress is indeterminate (spinner).
- Previews exist only for images: videos show an icon.
- Folders with many large photos take a while the first time they open, because each photo has to be downloaded once to make its thumbnail.
