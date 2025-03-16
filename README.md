# Koha plugin - Melinda Component Part Records Importer

This plugin searches Melinda for component part records and stages them
for import in Koha.

Melinda search is performed using host record's 001 field and Melinda's
melinda.partsofhost search index.

## Install

Download the latest _.kpz_ file from the _Project / Releases_ page

## Configuration

1. Go to staff client /cgi-bin/koha/plugins/plugins-home.pl
2. Click Actions -> Configure
3. Select Melinda's SRU server. If it does not exist, use the option
to automatically generate it.
