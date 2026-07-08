## Final review fix: LWC-72 admin backend 403 denial

### What you fixed
- Added an exported `ApiError` in `src/lib/api.ts` so admin API failures preserve HTTP status.
- Updated admin JSON error handling to throw `ApiError` with backend message and status.
- Updated `AdminClient` to treat backend `403` responses from `getAdminProjects()` or `getAdminUsers()` as admin denial and render the same compact `Admin access required` `Surface` used for local role denial.
- Added coverage for preserved admin API status and the backend-403 access-denied path.

### RED/GREEN evidence
- RED: `npm test -- tests/api.test.mjs tests/lwc-72-admin-interface.test.mjs`
  - Failed because `ApiError` was not exported from `src/lib/api.ts`.
  - Failed because `AdminClient.tsx` did not include `adminDenied` handling for backend `403`.
- GREEN: `npm test -- tests/api.test.mjs tests/lwc-72-admin-interface.test.mjs`
  - Passed: 58 tests, 0 failures.

### Commands run and results
- `npm test -- tests/api.test.mjs tests/lwc-72-admin-interface.test.mjs`
  - RED first, then GREEN after the fix.
- `npm test`
  - Passed: 58 tests, 0 failures.
- `npm run lint`
  - Exit 0 with the known pre-existing warning in `src/components/MarkdownView.tsx` for `@next/next/no-img-element`.

### Files changed
- `src/lib/api.ts`
- `src/components/AdminClient.tsx`
- `tests/api.test.mjs`
- `tests/lwc-72-admin-interface.test.mjs`
- `.superpowers/sdd/final-review-fix-report.md`

### Any concerns
- No new concerns. Lint still reports the known baseline warning in `src/components/MarkdownView.tsx`.
