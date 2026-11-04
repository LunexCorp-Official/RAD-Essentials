# RADcord

> **Discord Rich Presence for Delphi & RAD Studio** – Display your coding activity on Discord in real-time!

RADcord is a plugin for Delphi/RAD Studio that integrates Discord Rich Presence, allowing you to showcase what you're working on directly in your Discord profile. Whether you're debugging, editing, or compiling, your Discord friends will know you're coding in Delphi.

## Features

- 🎮 **Live Activity Display** – Show your current file and action in Discord
- 📝 **Real-Time Updates** – Automatically updates as you switch files or edit code
- ⏱️ **Session Tracking** – Shows how long you've been working on your current task
- 🔧 **Non-Intrusive** – Runs quietly in the background without interrupting your workflow

## Installation

1. **Clone or Download** this repository
2. **Open RADcord.dpk** in your Delphi/RAD Studio IDE
3. **Right-click the package** → **Install**
4. **Restart the IDE** to activate the plugin
5. **Verify Installation** – Look for "RADcord" in Help → About

## Configuration

### Discord Application Setup

To use RADcord, you need a Discord Application ID:

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **"New Application"** and give it a name (e.g., "Delphi Dev")
3. Copy your **Client ID** from the General Information page
4. Set `ApplicationID` in `Source/Config/RADcord.ini` to your Client ID.
5. Rebuild and reinstall the package.

The plugin checks the project-relative `Source/Config` location and nearby
executable-relative locations for this file. If it cannot find the file, it
uses the default application ID in `RADcordConfig.pas`. When no existing
configuration file is found, RADcord saves settings to
`%APPDATA%\RADcord\RADcord.ini`.

### Presence settings

RADcord initializes its IDE and Discord notifiers when the package loads.
Open **Tools → RADcord Settings...** to choose whether the presence includes
the current file name, project name, line number, or elapsed time, and whether
to show the idle activity when no file is open. Changes are saved in the
active `RADcord.ini` configuration file. Elapsed time is shared across editor
files and does not reset when switching between them.

## Usage

Once installed, RADcord works automatically:

- **Opening a File** → Immediately shows on Discord with elapsed time
- **Editing Code** → Updates your presence status
- **Switching Files** → Reflects the new file in your Discord profile

### Example Discord Presence

```
🎮 In-Game
Editing in Delphi/RAD Studio
MainForm.pas
Elapsed: 15 minutes
```

## Project Structure

```
RADcord/
├── Source/
│   ├── OTA/              # IDE notifier
│   │   ├── EditorNotifier.pas      # Tracks editor events
│   ├── Discord/
│   │   └── DiscordRPC.pas          # Discord RPC communication
│   ├── Common/
│   │   └── RADcordPresence.pas     # Shared presence construction
│   ├── Wizard/
│   │   └── DiscordPresenceWizard.pas # Main plugin interface
│   └── Config/
│       └── RADcord.ini   # Configuration file
├── Resources/            # Asset files
├── Build/                # Local compiler output (ignored)
└── README.md
```

## Architecture

### Core Components

1. **DiscordPresenceWizard** – Main plugin entry point
   - Implements `IOTAWizard` interface
   - Manages wizard lifecycle and initialization
   - Instantiates and manages notifiers

2. **EditorNotifier** – Monitors editor events
   - Tracks file activation (`ViewActivated`)
   - Monitors code changes (`ViewNotification`)
   - Updates Discord presence on file operations

3. **RADcordConfig** – Loads the Discord application ID from the INI file

4. **RADcordPresence** – Builds editor activity consistently for both update paths

5. **DiscordRPC** – Handles Discord communication
   - Connects to Discord via IPC pipes
   - Manages RPC handshake and payload delivery
   - Handles presence updates and clearing

## Development

### Building from Source

```bash
# Using Delphi command line (RAD Studio)
rsvars.bat              # Set up environment
dcc32 RADcord.dpk       # Compile package
```

### Debugging

Enable debug output in the IDE:
```pascal
OutputDebugString(PChar('Debug message'));
```

View in Debugger's Debug Output window or use **DbgView** from Sysinternals.

## Troubleshooting

### Plugin not loading
- Verify the package is installed: **Help → About → Installed Packages**
- Check that the `.bpl` file is in the correct Delphi bin directory
- Try removing from registry and reinstalling

### Discord presence not updating
- Ensure Discord is running and online
- Verify the Client ID in `Source/Config/RADcord.ini`
- Check that Discord Developer Portal shows your application
- Look for error messages in the Debug Output window

### No images showing
- Confirm you've uploaded Rich Presence assets to Discord Developer Portal
- Verify asset keys match file extensions (lowercase)
- Wait a few minutes for Discord to cache the assets

## Requirements

- **Delphi XE2** or later (tested on Delphi 11 Alexandria)
- **Windows 7** or later
- **Discord** installed and running (for presence updates)
- **Discord Application** created in Developer Portal

## API Reference

### TDiscordRichPresence

Represents rich presence data sent to Discord:

- `State` – Main activity text (e.g., "Editing in Delphi")
- `Details` – Secondary text (e.g., "MainForm.pas")
- `LargeImageKey` – Primary image asset key
- `LargeImageText` – Hover text for image
- `StartTimestamp` – Unix timestamp of activity start
- `PartySize` – Current party size
- `Instance` – Whether this is an instanced match

### TDiscordRPC Methods

```pascal
procedure Initialize;           // Connect to Discord
procedure Shutdown;             // Disconnect cleanly
procedure UpdatePresence(...);  // Update current presence
procedure ClearPresence;        // Clear presence from profile
property IsReady: Boolean;      // Check connection status
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/cool-feature`)
3. Commit changes (`git commit -am 'Add cool feature'`)
4. Push to branch (`git push origin feature/cool-feature`)
5. Create a Pull Request

## Known Limitations

- Only works on Windows
- Requires Discord to be running
- Updates may have slight delay (typically <1 second)
- Supports Delphi/RAD Studio only (not Free Pascal on Linux yet)

## License

This project is open source. See LICENSE file for details.

## Support

- 🐛 **Report Bugs** – Create an issue on GitHub
- 💡 **Suggest Features** – Open a GitHub Discussion
- 💬 **Ask Questions** – Check existing issues first

## Credits

Developed with ❤️ for the Delphi community.

Inspired by other IDE presence plugins and Discord's Rich Presence API documentation.