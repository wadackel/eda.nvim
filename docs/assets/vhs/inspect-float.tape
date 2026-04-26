Set Shell "bash"
Set FontSize 28
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set Width 1400
Set Height 700
Set Theme { "name": "dogrun", "black": "#111219", "red": "#e58585", "green": "#7cbe8c", "yellow": "#8e8a6f", "blue": "#4c89ac", "magenta": "#6c75cb", "cyan": "#73c1a9", "white": "#9ea3c0", "brightBlack": "#545c8c", "brightRed": "#b871b8", "brightGreen": "#7cbe8c", "brightYellow": "#a8a384", "brightBlue": "#589ec6", "brightMagenta": "#929be5", "brightCyan": "#59b6b6", "brightWhite": "#9ea3c0", "background": "#222433", "foreground": "#9ea3c0", "cursor": "#9ea3c0", "selection": "#363e7f" }
Set Padding 32
Set BorderRadius 12
Set MarginFill "#f5f5f5"
Set TypingSpeed 50ms

Hide
Type "bash docs/assets/vhs/setup.sh git"
Enter
Sleep 500ms
Type "EDA_SCREENSHOT_GIT=1 nvim -u docs/assets/vhs/init.lua"
Enter
Sleep 5s
Show

# Expand all directories to reveal nested files (matches tree-basic pattern)
Type "gE"
Sleep 2s
# Move to top, then navigate down into src/components/App.tsx area
Type "gg"
Sleep 500ms
# Jump a few lines down to land on a nested file node (post-root, post-.gitignore, into src/components)
Type "7j"
Sleep 300ms
# Open the inspect float: <leader>i (default mapleader is backslash)
Type "\i"
Sleep 1s
Screenshot docs/assets/inspect-float.png
# Toggle the float closed (focus stays in the explorer, so we re-press <leader>i)
Type "\i"
Sleep 200ms
