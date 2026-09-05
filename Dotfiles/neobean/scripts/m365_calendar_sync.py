#!/usr/bin/env python3
"""
Microsoft 365 Calendar Sync Script

Fetches today's meetings from M365 calendar and formats them for daily notes.
Requires Microsoft Graph API access with calendar.Read permission.
"""

import os
import sys
import json
import requests
import datetime
from dateutil import parser
from pathlib import Path

# Configuration
CONFIG_DIR = Path.home() / ".config" / "neobean" / "scripts"
TOKEN_FILE = CONFIG_DIR / "m365_token.json"
CLIENT_ID = "YOUR_CLIENT_ID"  # Replace with your Azure AD app client ID
CLIENT_SECRET = "YOUR_CLIENT_SECRET"  # Replace with your client secret
TENANT_ID = "YOUR_TENANT_ID"  # Replace with your tenant ID
DAILY_NOTES_DIR = Path.home() / "Notes" / "Daily"  # Adjust to your notes directory

def get_access_token():
    """Get or refresh access token using client credentials flow"""
    token_data = None
    if TOKEN_FILE.exists():
        try:
            with open(TOKEN_FILE, 'r') as f:
                token_data = json.load(f)
        except (json.JSONDecodeError, IOError):
            token_data = None

    if token_data and 'access_token' in token_data:
        # Check if token is still valid
        now = datetime.datetime.now(datetime.timezone.utc)
        expires_at = parser.parse(token_data['expires_at'])
        if now < expires_at:
            return token_data['access_token']

    # Get new token
    token_url = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"
    data = {
        'grant_type': 'client_credentials',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'scope': 'https://graph.microsoft.com/.default'
    }

    response = requests.post(token_url, data=data)
    response.raise_for_status()
    token_info = response.json()

    # Save token with expiration time
    token_info['expires_at'] = (datetime.datetime.now(datetime.timezone.utc) +
                              datetime.timedelta(seconds=token_info['expires_in'])).isoformat()

    # Create config directory if it doesn't exist
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(TOKEN_FILE, 'w') as f:
        json.dump(token_info, f)

    return token_info['access_token']

def get_todays_meetings():
    """Fetch today's meetings from Microsoft Graph API"""
    access_token = get_access_token()
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json'
    }

    # Get today's date in ISO format
    today = datetime.date.today().isoformat()
    start_time = f"{today}T00:00:00"
    end_time = f"{today}T23:59:59"

    # Microsoft Graph API endpoint for calendar view
    url = "https://graph.microsoft.com/v1.0/me/calendarview"
    params = {
        'startdatetime': start_time,
        'enddatetime': end_time,
        '$select': 'subject,start,end,location,organizer,attendees',
        '$orderby': 'start/dateTime'
    }

    response = requests.get(url, headers=headers, params=params)
    response.raise_for_status()

    return response.json().get('value', [])

def format_meeting(meeting):
    """Format a single meeting as Markdown"""
    start = parser.parse(meeting['start']['dateTime'])
    end = parser.parse(meeting['end']['dateTime'])

    time_format = "%H:%M"
    time_str = f"{start.strftime(time_format)}-{end.strftime(time_format)}"

    # Format attendees
    attendees = []
    for attendee in meeting.get('attendees', []):
        if attendee.get('status', {}).get('response') == 'accepted':
            attendees.append(attendee['emailAddress']['name'])
        elif attendee.get('status', {}).get('response') == 'tentative':
            attendees.append(f"{attendee['emailAddress']['name']} (tentative)")
        elif attendee.get('status', {}).get('response') == 'declined':
            attendees.append(f"{attendee['emailAddress']['name']} (declined)")

    attendees_str = ", ".join(attendees) if attendees else "No attendees"

    # Format location
    location = meeting.get('location', {}).get('displayName', 'No location')

    return f"""### {time_str} {meeting['subject']}
- **Location**: {location}
- **Attendees**: {attendees_str}
- **Organizer**: {meeting.get('organizer', {}).get('emailAddress', {}).get('name', 'Unknown')}
"""

def update_daily_notes(meetings):
    """Update daily notes with meetings section"""
    today = datetime.date.today()
    notes_file = DAILY_NOTES_DIR / f"{today.year}-{today.month:02d}-{today.day:02d}.md"

    # Create daily notes directory if it doesn't exist
    DAILY_NOTES_DIR.mkdir(parents=True, exist_ok=True)

    # Read existing notes
    existing_content = ""
    if notes_file.exists():
        with open(notes_file, 'r') as f:
            existing_content = f.read()

    # Check if mail section already exists
    mail_section_start = "### Mail"
    mail_section_end = "\n\n### "  # Next section
    mail_exists = mail_section_start in existing_content

    # Prepare new mail section
    mail_content = "### Mail\n\n"
    if meetings:
        mail_content += "\n".join([format_meeting(m) for m in meetings])
    else:
        mail_content += "No meetings scheduled for today."

    # Update notes file
    if mail_exists:
        # Replace existing mail section
        new_content = existing_content.replace(
            f"{mail_section_start}\n\n{mail_section_end}",
            f"{mail_section_start}\n\n{mail_content}\n\n{mail_section_end}"
        )
    else:
        # Add mail section at the beginning
        new_content = f"{mail_content}\n\n{existing_content}"

    with open(notes_file, 'w') as f:
        f.write(new_content)

def main():
    """Main execution function"""
    try:
        print("Fetching today's meetings from M365 calendar...")
        meetings = get_todays_meetings()

        if not meetings:
            print("No meetings found for today.")
            return

        print(f"Found {len(meetings)} meeting(s). Updating daily notes...")
        update_daily_notes(meetings)
        print("Daily notes updated successfully!")

    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
