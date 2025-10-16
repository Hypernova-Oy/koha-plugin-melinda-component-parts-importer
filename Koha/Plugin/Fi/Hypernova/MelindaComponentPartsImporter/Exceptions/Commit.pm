package Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit;

# Copyright 2025 Hypernova Oy
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Koha::Exception;

use Exception::Class (
    'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit' => {
        isa => 'Koha::Exception',
    },
    'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit::NoStagedJob' => {
        isa         => 'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit',
        description => 'No staged job was given'
    },
    'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit::StagedJobFailed' => {
        isa         => 'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit',
        description => 'Staged job failed'
    },
);

=head1 NAME

Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit - Melinda Component Parts Importer committing exception

=head1 Exceptions

=head2 Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit

Generic Import Exception

=head2 Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit::NoStagedJob

No staged job was given

=cut

1;
