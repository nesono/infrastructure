#!/usr/bin env python3

import base64
import sys

# Check if both username and password were provided as command line arguments
if len(sys.argv) != 3:
    print("Usage: python script.py <username> <password>")
    sys.exit(1)

# Get username and password from command line arguments
username = sys.argv[1]
password = sys.argv[2]

# Create the userpass string with null bytes and concatenate username and password
userpass = '\x00' + username + '\x00' + password

# Encode the userpass using base64
encoded_userpass = base64.b64encode(userpass.encode()).decode()

# Remove leading and trailing whitespaces
encoded_userpass = encoded_userpass.strip()

# Print the PLAIN authentication string
print(f'AUTHENTICATE "PLAIN" "{encoded_userpass}"')

userenc = base64.b64encode(username.encode()).decode()
print(f"Username encoded: {userenc}")

passenc = base64.b64encode(password.encode()).decode()
print(f"Password encoded: {passenc}")
