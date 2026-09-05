# /// script
# requires-python = ">=3.11"
# dependencies = ["pyobjc-framework-EventKit"]
# ///
"""Render one day of the local EventKit calendar store.

Reading EventKit rather than talking to Microsoft is the whole point. The
Exchange account is authenticated by macOS through Apple's own registered
Entra application, so nothing here needs a token, an app registration or a
borrowed client id. Dotfiles/zsh/.zsh/functions/calendar records which direct
routes were tried first and why each is closed.

Usage:
  calendar-eventkit.py DATE [--source S] [--calendars A,B] [--json]

--source matches the EventKit source name ("Exchange" excludes the personal
iCloud calendars); --calendars narrows to exact calendar titles. Both are
needed because one Exchange account mounts several calendars: here it brought
a birthdays calendar, a US holidays calendar and three empty shared ones
alongside the real "Calendar". Filtering by source alone let Labor Day into a
Vienna work agenda.

--json emits one object per event for programmatic callers (the neobean daily
note integration). Each carries an `occurrence` key: EventKit reuses one
eventIdentifier across every instance of a recurring meeting, so the
identifier alone cannot distinguish Monday's stand-up from Tuesday's. Hashing
it together with the start time gives a key that is stable across refreshes
and unique per occurrence, which is what lets a refresh update a meeting in
place rather than duplicating it.
"""

import argparse
import hashlib
import json
import sys
import threading
from datetime import date, datetime, time, timedelta

from EventKit import EKEntityTypeEvent, EKEventStore, EKEventStatusCanceled
from Foundation import NSCalendar, NSDateComponents

# EventKit hands back events sorted by nothing in particular, and an all-day
# event starts at local midnight like any other - so all-day entries are
# forced to the top rather than interleaved by start time.
ALL_DAY_LABEL = "all day    "


def request_access(store) -> tuple[bool, object]:
    done, result = threading.Event(), [False, None]

    def completion(granted, error):
        result[0], result[1] = granted, error
        done.set()

    # requestAccessToEntityType_completion_ is the pre-Sonoma spelling; the
    # full-access variant replaced it and is the only one that returns events
    # rather than busy blocks on current macOS.
    if hasattr(store, "requestFullAccessToEventsWithCompletion_"):
        store.requestFullAccessToEventsWithCompletion_(completion)
    else:
        store.requestAccessToEntityType_completion_(EKEntityTypeEvent, completion)

    done.wait(60)
    return result[0], result[1]


def as_nsdate(moment: datetime):
    components = NSDateComponents.alloc().init()
    components.setYear_(moment.year)
    components.setMonth_(moment.month)
    components.setDay_(moment.day)
    components.setHour_(moment.hour)
    components.setMinute_(moment.minute)
    return NSCalendar.currentCalendar().dateFromComponents_(components)


def is_online(event) -> bool:
    haystack = " ".join(
        str(value or "")
        for value in (event.location(), event.notes(), event.URL())
    ).lower()
    return "teams.microsoft.com" in haystack or "zoom.us" in haystack


def local_hm(nsdate) -> str:
    return datetime.fromtimestamp(nsdate.timeIntervalSince1970()).strftime("%H:%M")


def local_iso(nsdate) -> str:
    return datetime.fromtimestamp(nsdate.timeIntervalSince1970()).isoformat(timespec="minutes")


def occurrence_key(event) -> str:
    """Stable, occurrence-unique handle for one event.

    Short on purpose: it is written into the daily note as an HTML comment, so
    it has to survive a human reading the file without being an eyesore. Eight
    hex characters over a per-day set of meetings is far from collision range.
    """
    raw = f"{event.eventIdentifier()}|{local_iso(event.startDate())}"
    return hashlib.sha1(raw.encode()).hexdigest()[:8]


def as_dict(event) -> dict:
    location = str(event.location() or "").strip().splitlines()
    return {
        "occurrence": occurrence_key(event),
        "subject": str(event.title() or ""),
        "start": local_iso(event.startDate()),
        "end": local_iso(event.endDate()),
        "start_hm": local_hm(event.startDate()),
        "end_hm": local_hm(event.endDate()),
        "location": location[0] if location else "",
        "all_day": bool(event.isAllDay()),
        "online": is_online(event),
    }


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("date")
    parser.add_argument("--source", default="")
    parser.add_argument("--calendars", default="")
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()

    day = date.fromisoformat(args.date)
    source_filter = args.source.lower() or None
    title_filter = {t.strip() for t in args.calendars.split(",") if t.strip()} or None

    store = EKEventStore.alloc().init()
    granted, error = request_access(store)
    if not granted:
        print(f"agenda: EventKit access denied ({error})", file=sys.stderr)
        print("        grant it under System Settings > Privacy & Security > Calendars", file=sys.stderr)
        return 1

    calendars = list(store.calendarsForEntityType_(EKEntityTypeEvent) or [])
    if source_filter:
        calendars = [
            c for c in calendars if source_filter in str(c.source().title()).lower()
        ]
        if not calendars:
            print(f"agenda: no calendar from a source matching '{args.source}'", file=sys.stderr)
            return 1

    if title_filter:
        calendars = [c for c in calendars if str(c.title()) in title_filter]
        if not calendars:
            print(f"agenda: no calendar titled {sorted(title_filter)}", file=sys.stderr)
            return 1

    start = as_nsdate(datetime.combine(day, time.min))
    end = as_nsdate(datetime.combine(day, time.min) + timedelta(days=1))
    predicate = store.predicateForEventsWithStartDate_endDate_calendars_(start, end, calendars)
    events = list(store.eventsMatchingPredicate_(predicate) or [])

    # A cancelled meeting stays in the store until the sync catches up, which
    # is exactly the stale-notification case worth not reprinting.
    events = [e for e in events if e.status() != EKEventStatusCanceled]

    events.sort(key=lambda e: (not e.isAllDay(), e.startDate().timeIntervalSince1970()))

    if args.as_json:
        json.dump([as_dict(e) for e in events], sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0

    print(day.strftime("%A, %d.%m.%Y"))
    if not events:
        print("  no meetings")
        return 0

    for event in events:
        when = ALL_DAY_LABEL if event.isAllDay() else f"{local_hm(event.startDate())}-{local_hm(event.endDate())}"
        marker = " * " if is_online(event) else "   "
        location = str(event.location() or "").strip().splitlines()
        suffix = f"  @ {location[0]}" if location and location[0] else ""
        print(f"  {when}{marker}{event.title()}{suffix}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
