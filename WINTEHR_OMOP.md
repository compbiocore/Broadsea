# WintEHR OMOP source

WintEHR conversion is implemented by the separate `fhir-to-omop` repository.
The minimal deployment transfers a checksummed FHIR snapshot to the Broadsea VM
and runs that container on Broadsea's private Docker network. It resolves codes
against `omop_vocab` and writes `wintehr_cdm`; Atlas does not import FHIR or CSV
files directly.

Broadsea owns four schemas for this source:

- `omop_vocab`: full OHDSI Athena vocabulary loaded separately;
- `wintehr_cdm`: converted OMOP CDM 5.4 data;
- `wintehr_etl`: snapshot, identity, mapping, and rejection audit records;
- `wintehr_results`: Achilles results consumed by Atlas.

## Prerequisites

Verify the Athena vocabulary:

```bash
docker compose exec broadsea-atlasdb psql -U postgres -d postgres -c \
  "select vocabulary_version from omop_vocab.vocabulary where vocabulary_id='None'"
```

If it is absent, place an authorized Athena download in `omop_vocab/files`,
configure Section 9 of `.env`, and run:

```bash
docker compose --profile omop-vocab-pg-load up --abort-on-container-exit
```

Run the transferred-snapshot loader from the `fhir-to-omop` checkout. After it
succeeds, copy `.env.wintehr.example` to the untracked `.env.wintehr`, run the
`cdm-postprocessing` profile, and execute
`atlasdb/110_register_wintehr_source.sql` as described by that repository's
deployment guide.

Athena vocabulary CSVs, UMLS keys, database passwords, FHIR snapshots, and OMOP
patient-level exports must not be committed to this repository.
