#!/bin/bash

#BUS_TYPE="--system"
#BUS_NAME="org.bluez"
#BUS_OBJECT="/org/bluez"

function select_bus_type() {

    exec 3>&1
    ret=0

    declare -a dialog_args=(1 "System" 2 "User")

    declare -a choice_to_opt=(
        [1]="--system" \
        [2]="--user" \
    )

    choice=$(
    dialog --clear --backtitle "Choose D-BUS Type" \
        --title "Options" \
        --menu "Choose one of the following options:" 15 50 2 \
        "${dialog_args[@]}" \
         2>&1 1>&3
    ) || ret=$? # show dialog and pass non zero return code to ret

    exec 3>&-

    BUS_TYPE="${choice_to_opt[$choice]}"
}


function select_bus() {

    declare -a dialog_args=()

    # Read the output directly into dialog_args
    while IFS=$'\t' read -r bus_name bus_process; do
        # Directly add bus name and process to dialog_args
        dialog_args+=("$bus_name" "$bus_process")
    done < <(busctl "$BUS_TYPE" --json=short | jq -r '.[] | [.name, (.unit // "(empty)")] | @tsv')

    # Display the dialog menu
    exec 3>&1
    BUS_NAME=$(dialog --clear --backtitle "Select a service" \
                   --title "Services and Processes" \
                   --menu "Choose a service:" 0 0 0 \
                   "${dialog_args[@]}" \
                   2>&1 1>&3)
    exec 3>&-

}

function select_object() {
    readarray -t bus_objects < <(busctl --system tree --list "$BUS_NAME")

    declare -a dialog_args=()
    for i in "${!bus_objects[@]}"; do
        dialog_args+=("$i" "${bus_objects[$i]}")
    done

    # Display the dialog menu
    exec 3>&1
    selection=$(dialog --clear --backtitle "Select a D-Bus object" \
                       --title "D-Bus Objects" \
                       --menu "Choose an object:" 0 0 0 \
                       "${dialog_args[@]}" \
                       2>&1 1>&3)
    exec 3>&-

    BUS_OBJECT="${bus_objects[$selection]}"
}

if ! command -v dialog &> /dev/null; then
    echo "Error: install dialog first" >&2
    exit 1
fi

if [ -z "$BUS_TYPE" ]; then
    select_bus_type
fi

if [ -z "$BUS_NAME" ]; then
    select_bus
fi

if [ -z "$BUS_OBJECT" ]; then
    select_object
fi

#echo BUS_TYPE=$BUS_TYPE BUS_NAME=$BUS_NAME BUS_OBJECT=$BUS_OBJECT

set -x
busctl "$BUS_TYPE" introspect "$BUS_TYPE" "$BUS_NAME" "$BUS_OBJECT"


