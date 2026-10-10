#!/bin/bash
# Double-click me. Opens Terminal and shows a simple menu.
cd "$(dirname "$0")" || exit 1

extras_menu() {
    while true; do
        clear
        echo "Optional extras (not needed for the fix)"
        echo "----------------------------------------"
        echo
        echo "  1) Fit the game window to the screen (quit the game first)"
        echo "  2) Undo the window fit"
        echo "  3) Mac keyboard: turn on (Option = Alt, Command stays Command)"
        echo "  4) Mac keyboard: turn off (back to Wine's defaults)"
        echo "  5) Mac keyboard: show what is set"
        echo "  6) AzzyAI: install the latest (uaRO pre-renewal only, asks first)"
        echo "  7) AzzyAI: remove it (puts the original AI folder back)"
        echo "  8) CrossOver launcher icons: add (game, setup, AzzyAI settings)"
        echo "  9) CrossOver launcher icons: remove"
        echo "  0) Back"
        echo
        printf "Type a number and press Return: "
        read -r k
        echo
        case "$k" in
            1) bash install.sh window ;;
            2) bash install.sh window undo ;;
            3) bash install.sh keys on ;;
            4) bash install.sh keys off ;;
            5) bash install.sh keys status ;;
            6) bash install.sh azzyai ;;
            7) bash install.sh azzyai undo ;;
            8) bash install.sh launchers ;;
            9) bash install.sh launchers remove ;;
            0|"") return ;;
            *) echo "Please type a number from 0 to 9." ;;
        esac
        echo
        printf "Press Return to continue..."
        read -r _
    done
}

while true; do
    clear
    echo "Ragnarok Online tools for CrossOver"
    echo "------------------------------------"
    echo
    echo "  1) Install the fix"
    echo "  2) Install the fix WITH the optional extras (window, keyboard, AzzyAI, icons)"
    echo "  3) Play (clears leftover processes first, then starts the game)"
    echo "  4) View optional extras"
    echo "  5) Open the game folder in Finder"
    echo "  6) Collect a report to ask for help (doctor)"
    echo "  7) Uninstall the fix"
    echo "  8) Quit"
    echo
    printf "Type a number and press Return: "
    read -r choice
    echo
    case "$choice" in
        1) bash install.sh ;;
        2) bash install.sh extras ;;
        3) bash install.sh play ;;
        4) extras_menu ; continue ;;
        5) bash install.sh open ;;
        6) bash install.sh doctor ;;
        7) bash install.sh uninstall ;;
        8|q|Q|"") exit 0 ;;
        *) echo "Please type a number from 1 to 8." ;;
    esac
    echo
    printf "Press Return to go back to the menu..."
    read -r _
done
