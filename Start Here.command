#!/bin/bash
# Double-click me. Opens Terminal and shows a simple menu.
cd "$(dirname "$0")" || exit 1

while true; do
    clear
    echo "Gepard / CrossOver fix"
    echo "----------------------"
    echo
    echo "  1) Install the fix"
    echo "  2) Check that it is working"
    echo "  3) New game install only: fix the game's setup window"
    echo "  4) Uninstall the fix"
    echo "  5) Quit"
    echo
    printf "Type a number and press Return: "
    read -r choice
    echo
    case "$choice" in
        1) bash install.sh ;;
        2) bash install.sh check ;;
        3) bash install.sh setup ;;
        4) bash install.sh uninstall ;;
        5|q|Q|"") exit 0 ;;
        *) echo "Please type 1, 2, 3, 4 or 5." ;;
    esac
    echo
    printf "Press Return to go back to the menu..."
    read -r _
done
