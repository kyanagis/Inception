#!/usr/bin/python3
import re
import sys


def validate(schedule):
    if not re.fullmatch(r"[0-9*/ ,\-]+", schedule):
        raise ValueError("schedule contains unsupported characters")
    fields = schedule.split()
    if len(fields) != 5:
        raise ValueError("schedule must contain five fields")
    for field, (lower, upper) in zip(fields, ((0, 59), (0, 23), (1, 31), (1, 12), (0, 6))):
        for part in field.split(","):
            match = re.fullmatch(r"(\*|[0-9]+(?:-[0-9]+)?)(?:/([0-9]+))?", part)
            if not match:
                raise ValueError("invalid schedule field")
            base, step = match.groups()
            if step is not None and not 1 <= int(step) <= upper - lower + 1:
                raise ValueError("schedule step outside field range")
            if base == "*":
                continue
            values = [int(value) for value in base.split("-")]
            if not all(lower <= value <= upper for value in values):
                raise ValueError("schedule value outside field range")
            if len(values) == 2 and values[0] > values[1]:
                raise ValueError("schedule range is reversed")
            if len(values) == 1 and step is not None:
                raise ValueError("steps require a wildcard or range")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("usage: backup-schedule 'minute hour day month weekday'")
        validate(sys.argv[1])
    except ValueError as error:
        print(f"Invalid BACKUP_SCHEDULE: {error}", file=sys.stderr)
        sys.exit(2)
