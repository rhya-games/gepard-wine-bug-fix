#!/bin/bash
# Double-click me. Opens Terminal and shows a simple menu.
cd "$(dirname "$0")" || exit 1

keys_menu() {
    while true; do
        clear
        echo "Mac keyboard and swipe settings (optional)"
        echo "------------------------------------------"
        echo
        echo "  Turning these on makes: Command act as Ctrl, Option act as Alt,"
        echo "  the Mac Control key stay as Left Ctrl, and swipe gestures work in full screen."
        echo
        echo "  1) Turn on"
        echo "  2) Turn off (back to Wine's defaults)"
        echo "  3) Show what is set"
        echo "  4) Back"
        echo
        printf "Type a number and press Return: "
        read -r k
        echo
        case "$k" in
            1) bash install.sh keys on ;;
            2) bash install.sh keys off ;;
            3) bash install.sh keys status ;;
            4|"") return ;;
            *) echo "Please type 1, 2, 3 or 4." ;;
        esac
        echo
        printf "Press Return to continue..."
        read -r _
    done
}

while true; do
    clear
    echo "Gepard / CrossOver fix"
    echo "----------------------"
    echo
    echo "  1) Install the fix"
    echo "  2) Check that it is working"
    echo "  3) New game install only: fix the game's setup window"
    echo "  4) Uninstall the fix"
    echo "  5) Optional: Mac keyboard and swipe settings"
    echo "  6) Quit"
    echo
    printf "Type a number and press Return: "
    read -r choice
    echo
    case "$choice" in
        1) bash install.sh ;;
        2) bash install.sh check ;;
        3) bash install.sh setup ;;
        4) bash install.sh uninstall ;;
        5) keys_menu ; continue ;;
        6|q|Q|"") exit 0 ;;
        *) echo "Please type a number from 1 to 6." ;;
    esac
    echo
    printf "Press Return to go back to the menu..."
    read -r _
done
