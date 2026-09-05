#!/usr/bin/env python3
"""
Setup script for M365 Calendar Sync

This script helps you configure the Azure AD app registration and
provides instructions for setting up the required permissions.
"""

import webbrowser
import json
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "neobean" / "scripts"
SETUP_FILE = CONFIG_DIR / "m365_setup.json"

def show_setup_instructions():
    """Display setup instructions for Azure AD app registration"""
    print("""
Microsoft 365 Calendar Sync Setup Instructions

1. Register an Azure AD Application:
   - Go to https://portal.azure.com
   - Navigate to Azure Active Directory > App registrations > New registration
   - Enter a name (e.g., "Neobean Calendar Sync")
   - Select "Accounts in this organizational directory only"
   - Click Register

2. Configure API Permissions:
   - In your app registration, go to API Permissions
   - Click "Add a permission" > Microsoft Graph > Application permissions
   - Add "Calendar.Read" permission
   - Click "Grant admin consent" (requires admin privileges)

3. Create Client Secret:
   - Go to Certificates & secrets > New client secret
   - Enter description (e.g., "Neobean sync secret")
   - Select expiration period (6 months recommended)
   - Click Add
   - COPY THE SECRET VALUE NOW - you won't be able to see it again!

4. Update the script:
   - Open Dotfiles/neobean/scripts/m365_calendar_sync.py
   - Replace YOUR_CLIENT_ID with your Application (client) ID
   - Replace YOUR_CLIENT_SECRET with the secret value you copied
   - Replace YOUR_TENANT_ID with your Directory (tenant) ID
   - Adjust DAILY_NOTES_DIR if needed

5. Test the script:
   - Run: python3 m365_calendar_sync.py
   - If successful, schedule it to run daily in the morning
""")

def save_setup_data(client_id=None, tenant_id=None):
    """Save setup data for later reference"""
    setup_data = {
        "client_id": client_id,
        "tenant_id": tenant_id,
        "setup_complete": False
    }

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(SETUP_FILE, 'w') as f:
        json.dump(setup_data, f, indent=2)

def main():
    """Main setup function"""
    print("Microsoft 365 Calendar Sync Setup")
    print("=" * 50)

    if SETUP_FILE.exists():
        try:
            with open(SETUP_FILE, 'r') as f:
                setup_data = json.load(f)
            if setup_data.get("setup_complete"):
                print("Setup appears to be complete. If you need to reconfigure,")
                print("delete the setup file and run this script again.")
                return
        except (json.JSONDecodeError, IOError):
            pass

    show_setup_instructions()

    # Ask for basic info
    client_id = input("\nEnter your Application (client) ID: ").strip()
    tenant_id = input("Enter your Directory (tenant) ID: ").strip()

    if client_id and tenant_id:
        save_setup_data(client_id, tenant_id)
        print("\nSetup data saved. Please update the main script with your")
        print("client ID, tenant ID, and create a client secret.")
    else:
        print("\nSetup incomplete. Please enter the required information.")

if __name__ == "__main__":
    main()
