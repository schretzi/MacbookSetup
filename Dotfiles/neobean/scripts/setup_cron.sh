#!/bin/bash
# Setup cron job for daily M365 calendar sync

SCRIPT_PATH="$HOME/Dotfiles/neobean/scripts/m365_calendar_sync.py"
CRON_ENTRY="0 8 * * * /usr/bin/python3 $SCRIPT_PATH >> $HOME/.config/neobean/scripts/m365_sync.log 2>&1"

echo "Setting up daily cron job for M365 calendar sync..."
echo "This will run the script at 8:00 AM every day."

# Check if cron entry already exists
if crontab -l | grep -q "$SCRIPT_PATH"; then
    echo "Cron job already exists. Removing old entry..."
    (crontab -l | grep -v "$SCRIPT_PATH") | crontab -
fi

# Add new cron entry
echo "$CRON_ENTRY" | crontab -

# Verify it was added
echo "Current cron jobs:"
crontab -l

echo ""
echo "Cron job setup complete!"
echo "You can edit the schedule later by running 'crontab -e'"
