Set Shell "bash"
Set FontSize 28
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set Width 2000
Set Height 700
Set Theme { "name": "dogrun", "black": "#111219", "red": "#e58585", "green": "#7cbe8c", "yellow": "#8e8a6f", "blue": "#4c89ac", "magenta": "#6c75cb", "cyan": "#73c1a9", "white": "#9ea3c0", "brightBlack": "#545c8c", "brightRed": "#b871b8", "brightGreen": "#7cbe8c", "brightYellow": "#a8a384", "brightBlue": "#589ec6", "brightMagenta": "#929be5", "brightCyan": "#59b6b6", "brightWhite": "#9ea3c0", "background": "#222433", "foreground": "#9ea3c0", "cursor": "#9ea3c0", "selection": "#363e7f" }
Set Padding 32
Set BorderRadius 12
Set MarginFill "#f5f5f5"
Set TypingSpeed 50ms
Hide
Type "bash docs/assets/vhs/setup.sh base"
Enter
Sleep 500ms
Type "EDA_SCREENSHOT_KIND=replace EDA_SCREENSHOT_PREVIEW=1 nvim -u docs/assets/vhs/init.lua"
Enter
Sleep 5s
Show

# Expand all directories, then open a second explorer beside the first
Type "gE"
Sleep 1500ms
Ctrl+w
Type "v"
Sleep 3s
Type "gE"
Sleep 1500ms
# Different target in each explorer
Type "gg"
Sleep 300ms
Type "4j"
Sleep 1500ms
Ctrl+w
Type "w"
Sleep 800ms
Type "gg"
Sleep 300ms
Type "2j"
Sleep 2s
Screenshot docs/assets/preview-replace-dual.png
