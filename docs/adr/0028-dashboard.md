# ADR-0028: The dashboard draws its charts in plain HTML, labels its two time bases, and reads a ready-made chart series

- **Status:** Accepted
- **Date:** 2026-10-08
- **Sub-phase:** P7.3
- **Code:** `web/backoffice/ReportsSection.jac`, `web/backoffice/report_parts.jac`, `web/backoffice/report_view.jac`, `web/backoffice/AuditSection.jac`, `core/reporting/aggregates.jac` (`by_day`, `chart`), `core/reporting/report_api.jac` (`today`, `currency`), `core/audit/audit_api.jac` (`timezone`), `core/theming/css.jac` (`--chart-bar`)
- **Tests:** `tests/unit/reporting_tests.jac`, `tests/integration/reporting_tests.jac`, `tests/integration/audit_tests.jac`, `e2e/dashboard_tests.jac`

## Context
Plan 7.3: a dashboard for the sales report (7.1) with charts, legible on a phone; and the audit log (7.2) needs a page. The report counts money on the day it was taken and attendance on the day the showtime starts (ADR-0026).

## Decision
1. **Two sections:** Reports (`financial_reports.read`) and Audit log (`audit.read`), in the nav only for those who hold the permission; the server checks it on every request. The Overview leads with today's figures for staff who read reports.
2. **The two time bases are labelled:** the page has a "Money taken" block (counted on the day the money came in) and a "Showtimes in this period" block (counted on the day the showtime starts), each saying so.
3. **Period presets:** Today, Last 7 days, Last 30 days, Next 7 days (advance sales for the coming week), Custom. The first request sends no dates; the server answers today's report with the cinema's `today` and `currency`, from which the presets count.
4. **Charts are plain HTML,** not SVG and not a chart library: flex columns for the takings chart, bars for top movies. An SVG `viewBox` scales its text with the chart, so axis labels would be unreadable at phone width; a library adds weight to a bundle that already strained this machine's memory. One series per chart, so no legend; values are always written next to bars or in a readout; every bar is a focusable button the full column tall (hover, tap or focus shows its day, takings and tickets); each chart has a table view.
5. **One chart colour, validated:** `--chart-bar`, the back office's action hue: `#3F35C4` on white in light; `#B8892A` on `#1D1813` in dark (the action brass `#E7B03A` is too light for a filled mark there). Both pass the dataviz palette validator (lightness band, contrast >= 3:1 against the card).
6. **The server shapes the chart:** the report's `chart` is a point a day up to 31 days, else a point a week from the period's first day (`by_day` keeps every day). The grouping is unit-tested; the client only draws.
7. **The audit log** shows when (in the cinema's time zone, from `audit_log`'s `timezone`), who, what, on what and the result in words ("Done", "Refused: not allowed"), never by colour alone; a filter by action and "Load more" on the server's cursor.

## Consequences
- **The venue filter lists the venues seen in whole-cinema reports** (finance managers and auditors can't list venues): a venue with no showtimes or money in any period viewed yet isn't offered.
- **Negative days** (refunds over takings) draw no bar; their readout and the table show the amount.
- **Resource names in the audit log** are types and details, not names (an event keeps ids, not names that change).
