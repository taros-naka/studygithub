#!/bin/bash
# test2.sh
# This script demonstrates the use of a function to print a message
# and a variable to store a name.
# Function to print a message
function print_message() {
    echo "Hello, $1!"
}
# Main script execution
name="World"
print_message "$name"
# End of script

