# Security Policy

## Reporting a vulnerability

Please do not open a public issue containing exploit details, credentials,
personal data, or private recordings.

Use GitHub's private security-advisory flow for this repository when it is
available. If that flow is unavailable, contact `brasstune1@gmail.com` with a
short description and a safe way to reproduce the issue. Do not include live
tokens or other people's data.

Reports should identify the affected surface (native iOS app, web client,
backend API, Supabase policy/storage, or deployment configuration), the tested
revision, impact, and reproduction steps. We will acknowledge the report before
requesting any additional sensitive material.

## Supported code

Security fixes target the current `main` branch and the currently deployed
service. Historical builds and archived release-evidence snapshots are not
independently supported.

## Credential boundary

The web and native clients may contain Supabase publishable client keys. These
are public identifiers and do not grant privileged access by themselves;
authorization depends on Row Level Security and server-side checks. Supabase
secret/service-role keys, deployment tokens, Apple signing keys, real `.env`
files, local databases, and user recordings must never be committed.
