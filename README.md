# Koha plugin - Melinda Component Part Records Importer

This plugin searches Melinda for component part records and stages them
for import in Koha.

Melinda search is performed using host record's 001 field and Melinda's
melinda.partsofhost search index.

## How it looks

### Z39.50/SRU import

Import component part records together with the host record

https://github.com/user-attachments/assets/9062e844-1e94-4abd-80ff-4d0e8204b064

### Quick import

Quick import using selected MARC framework and the default matcher configured
in plugin settings.

https://github.com/user-attachments/assets/76a900ba-b7ea-4e28-9c40-8769aead2d60

### Staged MARC records and manual batch import

Staging lets you use Koha's "Manage staged MARC records" tool to import the records.

https://github.com/user-attachments/assets/f68ddb22-8703-4463-a365-b9a24c728741

## Install

Download the latest _.kpz_ file from the _Project / Releases_ page

## Configuration

1. Go to staff client /cgi-bin/koha/plugins/plugins-home.pl
2. Click Actions -> Configure
3. Select Melinda's SRU server. If it does not exist, use the option
to automatically generate it.
4. Select default matcher for quick import
