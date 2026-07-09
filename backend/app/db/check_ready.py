import json
import sys

from app.db.readiness import readiness_report


def main() -> int:
    report = readiness_report()
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
