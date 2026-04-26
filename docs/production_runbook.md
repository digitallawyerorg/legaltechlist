# Production Runbook

This app is deployed to Heroku as `legaltech` and serves the Stanford TechIndex domain.

## Before A Production Deploy

1. Confirm the working tree only contains the intended changes.
2. Run the test suite:

   ```sh
   bin/rails test
   ```

3. Capture a Heroku Postgres backup:

   ```sh
   heroku pg:backups:capture --app legaltech
   ```

4. Check the current production release:

   ```sh
   heroku releases --app legaltech --num 5
   ```

## Deploy

Deploy the current `main` branch to Heroku:

```sh
git push heroku main
```

## Smoke Test

Run the smoke test against production:

```sh
bin/smoke
```

The script checks `/`, `/companies`, `/statistics`, and `/up` on `https://techindex.law.stanford.edu`.
To check another environment, pass `BASE_URL`:

```sh
BASE_URL=https://legaltech.herokuapp.com bin/smoke
```

## Rollback

Rollback to the prior Heroku release if smoke tests or production logs show a regression:

```sh
heroku rollback v236 --app legaltech
```

Replace `v236` with the intended target release from `heroku releases --app legaltech --num 5`.

## Read-Only Data Audit

Run the company data quality audit locally or on Heroku:

```sh
bin/rails data_quality:audit
heroku run bin/rails data_quality:audit --app legaltech
```

This task is read-only. It reports counts for visible/invisible companies, missing metadata, weak descriptions, stale records, duplicate names, duplicate domains, and spam keyword signals.
