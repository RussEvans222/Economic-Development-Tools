# Mansfield Economic Development Demo

Salesforce DX project containing:
- Mansfield demo data loader (`MansfieldDemoCloneService`)
- Site map record component (`siteRecordMap`)
- Home dashboard component (`econDevHomeHeader`)

## Prerequisites

- Salesforce CLI (`sf`) installed
- Target org authorized (example alias: `econdev`)

## Deployable Assets

- Deploy manifest: `manifest/package.xml`
- Deploy script: `scripts/deploy-mansfield-assets.sh`

Deploy with:

```bash
./scripts/deploy-mansfield-assets.sh econdev
```

## Run Demo Loader

Dry run:

```bash
./scripts/run-mansfield-loader.sh econdev --dry-run
```

Execute insert/clone run:

```bash
./scripts/run-mansfield-loader.sh econdev
```

## Validation Queries

SOQL checks are in:
- `scripts/soql/mansfield_demo_validation.soql`

You can run ad-hoc with:

```bash
sf data query --target-org econdev --query "SELECT COUNT() FROM Opportunity WHERE analyticsdemo_batch_id__c LIKE 'MANSFIELD_DEMO_OPP_%'"
```

## Cleanup Script

Cleanup Apex script:
- `scripts/apex/mansfield_demo_cleanup.apex`

Run with:

```bash
sf apex run --target-org econdev --file scripts/apex/mansfield_demo_cleanup.apex
```

## Create A New GitHub Repo

1. Initialize local repo:
```bash
git init
git add .
git commit -m "Initial Mansfield Econ Dev demo assets"
```

2. Create an empty GitHub repo (web UI), then connect:
```bash
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
```
