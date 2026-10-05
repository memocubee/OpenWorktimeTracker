# Context

OpenWorktimeTracker is a macOS menu bar app that automatically tracks how long you
work each day, so you don't have to remember to start or stop a timer.

## Language

**Workday**:
One person's tracked time for a single calendar date. It begins when the Mac is
first used that day and is either running, paused, or ended.
_Avoid_: Session, shift, day entry

**Gross Time**:
Wall-clock time from the start of the workday to now (or to its end), before
anything is deducted.
_Avoid_: Total time, elapsed time

**Pause**:
Time deliberately not counted as work — either because the user pressed pause or
because an idle period was judged to be a break.
_Avoid_: Break, stop

**Auto Break**:
Rest time the law requires but the user never took. Deducted automatically once
work passes a legal threshold, and only for the part not already covered by a Pause.
_Avoid_: Legal break, mandatory break, ArbZG break

**Auto Break Rules**:
The configured minutes of Auto Break owed at each legal threshold — by default 30
minutes past 6 hours and 45 past 9. A Workday cannot derive Net Work Time without
them, which is what stops a caller from silently using the wrong ones.
_Avoid_: Break settings, break config

**Net Work Time**:
The number that matters: Gross Time minus every Pause and any Auto Break. This is
what the menu bar shows.
_Avoid_: Actual time, real time, worked hours

**Idle Period**:
A stretch with no keyboard or mouse activity, or with the screen locked. It is not
counted either way until the user decides.
_Avoid_: Inactivity, away time

**Idle Decision**:
The user's answer about one Idle Period — either _work_ (a meeting, thinking) or
_pause_ (a break). Recorded on the workday so the same question is never asked twice.
_Avoid_: Idle choice, resolution

**Threshold**:
A configurable point in a Workday's Net Work Time that something reacts to.
Thresholds come in two independent forms — a Threshold Ladder recolours,
Notification Thresholds notify — and a Workday can be past one but not the
other.
_Avoid_: Limit, alarm

**Threshold Ladder**:
The two Thresholds that recolour a Workday, held together as one value. Deliberately
allowed to differ from Notification Thresholds, which fire at their own points.
_Avoid_: Threshold settings, colour config

**Notification Thresholds**:
The Thresholds that fire a system notification as a Workday's Net Work Time grows —
normal, critical, and the milestone that also prompts to end the day. Independent
of the Threshold Ladder; a user can set them to disagree on purpose.
_Avoid_: Notification settings, alert thresholds

**Threshold Level**:
Where a Workday's Net Work Time currently sits on the Threshold Ladder: _normal_,
_elevated_, or _critical_. Named by meaning rather than by colour, because the menu
bar, the week history and the log editor each paint it differently.
_Avoid_: Colour, severity, status

**Daily Log**:
The one JSON file per calendar date holding that day's workday, readable and
exportable by hand.
_Avoid_: Record, database entry, log file

**Public Holiday**:
A weekday off on Taiwan's official working-day calendar (行政機關辦公日曆表), or the
make-up day off (補假) given when a holiday falls on a weekend. The calendar can also
make a weekend day a working day (補行上班).
_Avoid_: Vacation, leave, day off (that is the user's own choice)

**Expected Hours**:
The daily goal times the working days in a period — Monday to Friday, minus Public
Holidays, plus any weekend made a working day. What a week's Net Work Time is
measured against.
_Avoid_: Target week, quota, Soll
