# RAD Essentials

RAD Essentials is a beta Windows design-time package for RAD Studio. It adds **Format X**, the **Search Palette** (Search Everywhere), a searchable code snippets manager, Discord Rich Presence, and Git/GitHub project publishing tools. The package also registers its icon on the RAD Studio splash screen and exposes the Git integration from the Help menu.

**Beta status:** Code Snippets Manager has known bugs and is still being stabilized. PDF Viewer also has known integration and shutdown bugs, so its **RADEssentials > PDF Viewer** menu item is currently grayed out and its shortcut is inactive. This is a known plugin issue, not a missing WebView2 Runtime issue.

## IDE Menu

- **Git** opens the Git integration for repository access, project publishing, and release uploads.
- **Search** opens the Search Palette for IDE actions, project declarations, files, text, and snippets.
- **Code Snippets Manager** manages searchable, categorized snippets shared across projects.
- **Format Code** runs Format X on the selection, or on the whole editor buffer when nothing is selected.
- **PDF Viewer** is currently disabled.
- **Settings** configures the Format X, Search, and PDF Viewer shortcuts, plus Discord Rich Presence. The PDF Viewer shortcut is inactive while the feature is disabled.

## Requirements

- Windows and Embarcadero RAD Studio. The package is built and verified with RAD Studio 12 (Win32); the project targets Win32.
- The package dependencies included with RAD Studio: `rtl`, `vcl`, `designide`, `vclie`, and `vcledge`.
- Git for Windows, installed and discoverable on `PATH`, to use the Git integration.
- Discord desktop, to use Discord Rich Presence.
- Microsoft Edge WebView2 Runtime will be required when PDF Viewer is re-enabled.
- Internet access and a GitHub personal access token for GitHub operations.

## Build and Install

1. Open `RADEssentials.dproj` in RAD Studio.
2. The package embeds `Assets\Icons.res`. If you change the icon resource script or bitmap, regenerate it from this directory with `brcc32.exe Assets\Icons.rc`.
3. Select the **Win32** platform and build the `RADEssentials` package. From a RAD Studio command prompt, you can also build it from this directory with:

   ```powershell
   dcc32.exe -B RADEssentials.dpk
   ```

4. Find `RADEssentials.bpl` in the package's configured BPL output directory. Check **Project > Options > Delphi Compiler > Output** if you are unsure where RAD Studio wrote it. If the IDE reports a missing required package, make sure the package dependencies listed above are installed and available to the selected RAD Studio version.
5. In RAD Studio, open **Component > Install Packages**, choose **Add**, and select `RADEssentials.bpl` from that output directory.
6. Restart RAD Studio if prompted. The **RADEssentials** menu should appear in the IDE.

To remove the plugin, open **Component > Install Packages**, select RAD Essentials, and remove it. This does not delete your GitHub token or settings from your user profile.

## Format X

1. Open a Delphi source file in the editor.
2. Select a portion of source to format, or leave the selection empty to format the whole editor buffer.
3. Choose **RADEssentials > Format Code** or use the default shortcut **Ctrl+Alt+F**. The shortcut can be changed in **RADEssentials > Settings**.

Format X normalizes indentation and spacing while preserving the existing line structure. The operation is a single undo step and restores the editor position and selection state.

## Search Palette

Open the Search Palette with **RADEssentials > Search** or **Ctrl+Shift+A** by default. Change its shortcut under **RADEssentials > Settings**. When a source editor is open, type normally to search IDE menu actions and declarations in the open project or project group. Action icons are used when available; symbols have type-specific icons. A single click or **Enter** opens the selected result. When no source editor is open, the palette searches IDE actions only. With a source editor open, typing `file=`, `text=`, or `snippets=` switches the input to that search mode and displays a mode chip. Backspace on an empty query, or clicking the chip, returns to action search.

- `file=abc` finds project filenames containing the letters in `abc` in that order, even when other letters appear between them.
- `text=abc` finds the exact text `abc` in project text files. Selecting a result opens the file at the matching line and selects the matching text in the editor.
- `snippets=abc` searches snippet names, categories, locations, and code. Selecting a result inserts that snippet at the current editor cursor.
- Press **Enter** to open the selected result, **Esc** to close the popup, and use the arrow keys to move through results.

## Code Snippets Manager

Code Snippets Manager is a beta feature with known bugs. Select code in the RAD Studio editor and open **RADEssentials > Code Snippets Manager** to start a new snippet with the selection prefilled. To add more editor code while editing, choose **Pick lines...**, select code in the RAD Studio editor, and release the selection; it is inserted at the code template's current caret or selection. Choose **Use current selection** to add code that was already selected before opening the picker. In the manager, create categories with the **+** button and drag snippets onto a category to move them. The category list and folders are shared with the library. Use the shortcut field to set a key combination; at most three snippets in the library can have keyboard shortcuts, which are refreshed in the IDE when a snippet is saved. The code editor colorizes Pascal keywords, strings, comments, and numbers with a dark IDE-style palette. The manager also lets you search the library, preview code, and insert a selected snippet. The library is shared across projects and stored in `%USERPROFILE%\RADECodeSnippets.json`. Use **Import** and **Export** to share a library. The JSON file has a `formatVersion` of `1`, an optional `categories` array, and a `snippets` array with `id`, `name`, `category`, `location`, `code`, and `shortcut` fields.

Code templates can contain `{{DATE}}`, `{{TIME}}`, and `{{YEAR}}`, which update when the snippet is inserted, or `{{SELECTION}}`, which expands to the text currently selected in the editor. Click the field buttons above the code template to add a token at the current caret or selection. The preview shows the expanded template.

## Discord Rich Presence

RAD Essentials includes RADcord, originally created by [JancoNel](https://github.com/JancoNel) and fully adapted and integrated into this package. When Discord is running, RADcord can show the active file, project, line, and elapsed editing time. Presence options, including idle activity, are available under **RADEssentials > Settings**.

### Configure Discord Art Assets

The Discord application ID is built into RAD Essentials and is not editable in Settings. Use the existing Discord application associated with that ID; creating a separate application will not work unless the ID is changed in the source.

In that application's **Rich Presence > Art Assets** page, upload:

- The `bds_MAINICON.ico` from each RAD Studio version folder you want to support, using an asset key derived from the folder version. For example, `Studio\23.0\bds_MAINICON.ico` uses `radstudio_23_0`.
- `Assets\Icon.png` as `rade_essentials`, for the fallback image.

At runtime, RADcord checks the version folder inferred from the running IDE and looks for `bds_MAINICON.ico`. If found, it requests the matching `radstudio_<version>` asset; otherwise it requests `rade_essentials`. Discord cannot display the local `.ico` directly, so each image must be uploaded to the application once under the matching key. If you do not have access to that application, its owner must upload the assets.

## Connect GitHub

1. Install Git for Windows if it is not already installed, then restart RAD Studio.
2. Open a project in the IDE and choose **RADEssentials > Git**.
3. Select **Sign in to GitHub**, then choose **Create token on GitHub...**.
4. Create a personal access token and paste it into the sign-in form. Do not enter your GitHub password.
   For a classic token, select the `repo` scope. For a fine-grained token, grant **Contents: Read and write** and **Metadata: Read-only** for the repositories you need.
5. Return to RAD Studio and select **Sign in**. RAD Essentials validates the token and loads the repositories it can access.

The token is encrypted with Windows DPAPI for the current Windows user and stored at `%USERPROFILE%\RadeEssentials\git_token.dat`. Use **Sign out** to remove it. A token can be valid but still lack write access to a particular repository; the Git window reports the selected repository's push permission before upload. Branch protection rules can still reject a push.

## Publish a Project

1. Open the project you want to publish, then open **RADEssentials > Git**. Press **Reload files** if the file tree does not reflect the current project.
2. Sign in if needed. Choose a GitHub repository and branch. The window reports whether your token has push access to that repository.
3. Check the files and folders to include. Folder checkboxes update their contents recursively. **Select all**, **Select none**, and the Space key are available for quick selection. Unchecked entries are added to `.gitignore`; RAD Essentials does not add a set of default ignore patterns. If an older `.gitignore` contains the RAD Essentials-generated defaults, those marked entries are removed when you next confirm an upload. Other existing rules are preserved.
4. Press **Upload to GitHub**. Review and edit the `.gitignore` entries in the confirmation window, then continue. RAD Essentials initializes the local Git repository if needed, stages and commits changes, verifies the target push with Git, and displays progress during the push.
5. To overwrite remote history, select **Force push** before uploading. This can discard commits on GitHub that are not present locally; use it only when you intend to replace that remote history.

The local project's Git metadata is stored in its `.git` folder. Repository credentials are passed to Git for the push and are not written into the Git remote URL or `.git/config`.

## Build Releases

The Git window can upload build files as assets in a GitHub release after the source push succeeds.

- Enable **Upload build folder as a GitHub release** before uploading.
- RAD Essentials searches for a build directory named `build`, `Build`, `Release`, `Win32\Release`, `Win64\Release`, `Output`, or `bin`.
- To use another directory, open **Settings**, enter a relative or absolute path, or choose **Browse...**. Leave the path empty to use automatic detection.
- The same settings dialog lets you change the filename masks excluded from release assets. The default masks exclude common Delphi compiler outputs such as `.dcu`, `.map`, `.obj`, and related files.

## Settings and Data

- **RADEssentials > Settings** changes the Format X, PDF Viewer, and Search keyboard shortcuts and configures Discord Rich Presence options. Click a shortcut field and press the desired key combination to record it. The PDF Viewer shortcut is currently inactive while that feature is disabled.
- The **Settings** button in the Git window opens Git settings for sign-in, release folder, and release asset masks.
- Git settings are stored in `%USERPROFILE%\RadeEssentials\git.ini`.
- RADcord settings share `%USERPROFILE%\RADE_Essentials_Settings.ini` with the other RAD Essentials preferences.
- The Git integration and its dockable window are also available from the IDE's **Help** menu.

## Troubleshooting

- **PDF Viewer is grayed out:** this feature is temporarily disabled because the current viewer integration is not working. It will remain unavailable until a repaired version is released.
- **Git is disabled or not found:** install Git for Windows, confirm `git.exe` is on `PATH`, and restart RAD Studio.
- **No repositories appear:** press **Refresh**, check the internet connection, and verify that the token grants access to the repositories.
- **Push access is missing:** create a token with the required repository permissions. Organization access may also require organization approval or SSO authorization.
- **Push is rejected:** check the reported Git error and the repository's branch protection rules. If the remote contains commits absent locally, integrate them before retrying; force push only when it is safe to replace remote history.
- **The package does not compile:** use the RAD Studio command prompt for the installed compiler and confirm that `$(BDS)\source\ToolsAPI` is on the library and project search paths.
