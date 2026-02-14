package Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Controller;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Scalar::Util qw( blessed );
use Try::Tiny;

use C4::Context;

=head1 Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Controller

A class implementing the controller methods for importing component part records from Melinda

=head2 Class methods

=head3 search_component_parts

Method that searches component part records from Melinda

=cut

sub search_component_parts {
    my $c = shift->openapi->valid_input or return;

    return try {
        my ( $per_page, $page ) = $c->build_query_pagination( $c->req->params->to_hash );

        my $host_record_id   = $c->validation->param('host_record_id');
        my $import_record_id = $c->validation->param('import_record_id');
        my $biblionumber     = $c->validation->param('biblionumber');
        my $host_record_xml;

        if ($host_record_id) {

            # use host record id
        } elsif ($import_record_id) {
            my $import_record = Koha::Import::Records->find($import_record_id);
            return $c->render( status => 404, openapi => { error => 'Import record not found' } ) unless $import_record;
            $host_record_xml = $import_record->get_marc_record();
            return $c->render( status => 404, openapi => { error => 'Import record MARCXML not found' } )
                unless $host_record_xml;
            return $c->render( status => 404, openapi => { error => 'Import record field 001 not found' } )
                unless $host_record_xml->field('001');
            $host_record_id = $host_record_xml->field('001')->data;
        } elsif ($biblionumber) {
            my $biblio = Koha::Biblios->find($biblionumber);
            return $c->render( status => 404, openapi => { error => 'Biblio not found' } ) unless $biblio;
            my $host_record_xml = $biblio->metadata->record;
            return $c->render( status => 404, openapi => { error => 'Biblio metadata record not found' } )
                unless $host_record_xml;
            return $c->render( status => 404, openapi => { error => 'Biblio metadata field 001 not found' } )
                unless $host_record_xml->field('001');
            $host_record_id = $host_record_xml->field('001')->data;
        } else {
            return $c->render(
                status  => 400,
                openapi => { error => 'Either host_record_id, import_record_id or biblionumber parameter is required' }
            );
        }

        # if record is already a component record, skip it
        if ( $host_record_xml && $host_record_xml->subfield( '773', 'w' ) ) {
            return $c->render(
                status  => 400,
                openapi =>
                    { error => 'This is a component record. Will not search component records for a component record' }
            );
        }

        my $melindacpi = Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter->new;

        my @results = $melindacpi->search_melinda_for_component_parts( { host_record_id => $host_record_id } );
        my @paginated_results = @results[ ( ( $page - 1 ) * $per_page ) .. ( $page * $per_page - 1 ) ];
        @paginated_results = grep defined, @paginated_results;

        $c->add_pagination_headers(
            {
                base_total => scalar(@results),
                page       => $page,
                per_page   => $per_page,
                total      => scalar(@results),
            }
        );
        if ( $c->req->headers->accept =~ m/application\/marcxml\+xml(;.*)?$/ ) {
            $c->res->headers->add( 'Content-Type', 'application/marcxml+xml' );
            return $c->render(
                status => 200,
                text   => $melindacpi->_build_marcxml_results(@paginated_results)
            );
        } elsif ( $c->req->headers->accept =~ m/application\/json/
            || $c->req->headers->accept =~ m/application\/marc-in-json(;.*)?$/ )
        {
            my @mij = $melindacpi->_build_mij_results(@paginated_results);
            $c->res->headers->add( 'Content-Type', 'application/marc-in-json' );
            return $c->render(
                status => 200,
                json   => \@mij
            );
        } else {
            return $c->render(
                status  => 406,
                openapi => [
                    "application/json",
                    "application/marcxml+xml",
                    "application/marc-in-json",
                ]
            );
        }
    } catch {
        if ( blessed $_ ) {
            if (
                $_->isa(
                    'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer::Connection')
                )
            {
                return $c->render(
                    status  => 502,
                    openapi => { error => 'Error connecting to Melinda SRU server', code => $_->error }
                );
            }
        }

        $c->unhandled_exception($_);
    };

}

=head3 import_component_parts

Method that imports component part records from Melinda.

Searches Melinda for records by host record field 001 using melinda.partsofhost query.
If results are found, stages MARC records for importing.

=cut

sub import_component_parts {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $host_record_id   = $c->validation->param('host_record_id');
        my $import_record_id = $c->validation->param('import_record_id');
        my $biblionumber     = $c->validation->param('biblionumber');
        my $host_record_xml;

        if ($host_record_id) {

            # use host record id
        } elsif ($import_record_id) {
            my $import_record = Koha::Import::Records->find($import_record_id);
            return $c->render( status => 404, openapi => { error => 'Import record not found' } ) unless $import_record;
            $host_record_xml = $import_record->get_marc_record();
            return $c->render( status => 404, openapi => { error => 'Import record MARCXML not found' } )
                unless $host_record_xml;
            return $c->render( status => 404, openapi => { error => 'Import record field 001 not found' } )
                unless $host_record_xml->field('001');
            $host_record_id = $host_record_xml->field('001')->data;
        } elsif ($biblionumber) {
            my $biblio = Koha::Biblios->find($biblionumber);
            return $c->render( status => 404, openapi => { error => 'Biblio not found' } ) unless $biblio;
            my $host_record_xml = $biblio->metadata->record;
            return $c->render( status => 404, openapi => { error => 'Biblio metadata record not found' } )
                unless $host_record_xml;
            return $c->render( status => 404, openapi => { error => 'Biblio metadata field 001 not found' } )
                unless $host_record_xml->field('001');
            $host_record_id = $host_record_xml->field('001')->data;
        } else {
            return $c->render(
                status  => 400,
                openapi => { error => 'Either host_record_id, import_record_id or biblionumber parameter is required' }
            );
        }

        # if record is already a component record, skip it
        if ( $host_record_xml && $host_record_xml->subfield( '773', 'w' ) ) {
            return $c->render(
                status  => 400,
                openapi =>
                    { error => 'This is a component record. Will not search component records for a component record' }
            );
        }

        my $melindacpi = Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter->new;
        my @results    = $melindacpi->search_melinda_for_component_parts(
            {
                host_record_id => $host_record_id,
            }
        );

        my ( $upload, $filepath ) =
            $melindacpi->create_stage_file( { host_record_id => $host_record_id, results => \@results } );

        my $job_id = $melindacpi->stage_marc_for_import(
            {
                filepath                   => $filepath,
                marc_modification_template => $c->validation->param('marc_modification_template_id'),
                matcher_id                 => $c->validation->param('matcher_id'),
                nomatch_action             => $c->validation->param('nomatch_action'),
                overlay_action             => $c->validation->param('overlay_action'),
            }
        );

        unless ($job_id) {
            return $c->render( status => 500, openapi => { error => 'Could not add background job' } );
        }

        my $quick_import = $c->validation->param('quickimport');
        if ($quick_import) {
            my $frameworkcode     = $c->validation->param('frameworkcode')     // "";
            my $overlay_framework = $c->validation->param('overlay_framework') // "";
            $job_id = $melindacpi->commit_staged_marc_records(
                {
                    stage_job_id      => $job_id,
                    frameworkcode     => $frameworkcode,
                    overlay_framework => $overlay_framework,
                }
            );

            return $c->render( status => 200, openapi => { job_id => $job_id } );
        } else {
            return $c->render( status => 200, openapi => { job_id => $job_id } );
        }
    } catch {
        if ( blessed $_ ) {
            if (
                $_->isa(
                    'Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer::Connection')
                )
            {
                return $c->render(
                    status  => 502,
                    openapi => { error => 'Error connecting to Melinda SRU server', code => $_->error }
                );
            }
        }

        $c->unhandled_exception($_);
    };
}

sub get_frameworks {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $frameworks = Koha::BiblioFrameworks->search( {}, { order_by => ['frameworktext'] } );
        return $c->render(
            status  => 200,
            openapi => $frameworks
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

sub build_query_pagination {
    my ( $c, $params ) = @_;
    my $per_page = $params->{_per_page} // C4::Context->preference('RESTdefaultPageSize') // 20;
    if ( $per_page < 0 || $per_page > 100 ) { $per_page = 100; }
    my $page = $params->{_page} || 1;

    return ( $per_page, $page );
}

1;
