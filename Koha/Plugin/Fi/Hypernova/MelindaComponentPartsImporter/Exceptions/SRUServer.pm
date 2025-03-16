package Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer;

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
    'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer' => {
        isa => 'Koha::Exception',
    },
    'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer::Connection' => {
        isa         => 'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer',
        description => 'Connection failed'
    },
);

=head1 NAME

Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer - Melinda Component Parts Importer SRU server exceptions

=head1 Exceptions

=head2 Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer

Generic SRU server exception

=head2 Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer::Connection

Connection to SRU server was failed

=cut

1;
