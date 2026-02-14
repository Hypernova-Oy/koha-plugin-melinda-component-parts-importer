package Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter;

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

use base qw(Koha::Plugins::Base);

use Encode;
use File::Basename;
use MARC::File::XML;
use MARC::Record;
use Mojo::JSON qw(decode_json);
use Try::Tiny;

use C4::Breeding;
use C4::Charset;
use C4::Matcher;
use C4::Utils::DataTables::TablesSettings;
use Koha::BackgroundJob::MARCImportCommitBatch;
use Koha::BackgroundJob::StageMARCForImport;
use Koha::BackgroundJobs;
use Koha::BiblioFrameworks;
use Koha::Caches;
use Koha::Database;
use Koha::Template::Plugin::TablesSettings;
use Koha::Uploader;
use Koha::Z3950Servers;

use Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit;
use Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer;

our $VERSION = "25.11.01.0";

our $metadata = {
    name            => 'Melinda Component Parts Importer',
    author          => 'Lari Taskula',
    date_authored   => '2025-02-13',
    date_updated    => "2025-02-13",
    minimum_version => '24.11.01.000',
    maximum_version => undef,
    version         => $VERSION,
    description     =>
        "This plugin imports component part records from the National Library of Finland's Melinda metadata repository",
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);
    $self->{cgi} = CGI->new();

    return $self;
}

sub intranet_js {
    my ($self)            = @_;
    my $cgi               = $self->{'cgi'};
    my $script_name       = $cgi->script_name;
    my $sru_js            = $self->mbf_read('js/sru-search-results.js');
    my $detail_js         = $self->mbf_read('js/detail.js');
    my $translate_func_js = $self->mbf_read('js/mcpi-translate.js');
    my $translate_json    = $self->mbf_read('translations.json');
    utf8::decode($translate_json);
    $sru_js    = '<script>' . $sru_js . '</script>';
    $detail_js = '<script>' . $detail_js . '</script>';

    # inject the translation function and translation strings
    $translate_func_js =~ s/__MCPI_PLUGIN_TRANSLATIONS__/$translate_json/g;
    $sru_js            =~ s/__MCPI_PLUGIN_TRANSLATE_FUNCTION__/$translate_func_js/g;
    $detail_js         =~ s/__MCPI_PLUGIN_TRANSLATE_FUNCTION__/$translate_func_js/g;

    if ( $script_name =~ /detail\.pl/ ) {
        my ( $module, $page, $tablename ) = $self->_search_results_table_settings;
        local *C4::Utils::DataTables::TablesSettings::get_yaml = sub { return $self->_search_results_table_columns };
        my $table_settings =
            Koha::Template::Plugin::TablesSettings->GetTableSettings( $module, $page, $tablename, 'json' );
        $detail_js =~ s/__MELINDACPI_SEARCH_RESULTS_TABLE_SETTINGS__/$table_settings/;
        return "$detail_js";
    }
    if ( $script_name =~ /z3950_search\.pl/ ) {
        my $default_sru_target_id   = $self->retrieve_data('sru_target');
        my $default_sru_target      = Koha::Z3950Servers->find($default_sru_target_id);
        my $default_sru_target_name = $default_sru_target ? $default_sru_target->servername : '""';
        $sru_js =~ s/__MCPI_PLUGIN_DEFAULT_SRU_TARGET__/"$default_sru_target_name"/g;
        my $frameworks      = Koha::BiblioFrameworks->search;
        my $frameworks_json = JSON::encode_json( $frameworks->TO_JSON );
        utf8::decode($frameworks_json);
        $sru_js =~ s/__MCPI_PLUGIN_FRAMEWORKS__/$frameworks_json/g;
        return "$sru_js";
    }
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ($self) = @_;

    return 'melinda-component-parts-importer';
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my ( $module, $page, $tablename ) = $self->_search_results_table_settings;

    local *C4::Utils::DataTables::TablesSettings::get_yaml = sub { return $self->_search_results_table_columns; };

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        my @matching_rules = C4::Matcher::GetMatcherList();

        my $table_columns = C4::Utils::DataTables::TablesSettings::get_columns( $module, $page, $tablename );

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            available_matching_rules => \@matching_rules,
            default_matcher_id       => $self->retrieve_data('default_matcher_id'),
            sru_target               => $self->retrieve_data('sru_target'),
            sru_targets              => Koha::Z3950Servers->search( { servertype => 'sru', recordtype => 'biblio' } ),
            table_columns            => $table_columns,
        );

        $self->output_html( $template->output() );
    } else {
        my $melinda_id;
        if ( $cgi->param('sru_target') == 'melinda_default_sru' ) {
            $melinda_id = $self->_add_default_melinda_sru;
            $self->store_data(
                {
                    sru_target => $melinda_id,
                }
            );
        } else {
            $self->store_data(
                {
                    sru_target => $cgi->param('sru_target'),
                }
            );
        }

        my $matcher_id;
        if ( $cgi->param('default_matcher_id') eq 'default_773w' ) {
            $matcher_id = $self->_add_default_773w_matcher;
            $self->store_data(
                {
                    default_matcher_id => $matcher_id,
                }
            );
        } else {
            $self->store_data(
                {
                    default_matcher_id => $cgi->param('default_matcher_id'),
                }
            );
        }

        my @columnids = $cgi->multi_param("columnid");
        my @columns;
        for my $columnid (@columnids) {
            next unless $columnid =~ m{^([^\|]*)\|([^\|]*)\|(.*)$};
            my $is_hidden         = $cgi->param( $columnid . '_hidden' )            // 0;
            my $cannot_be_toggled = $cgi->param( $columnid . '_cannot_be_toggled' ) // 0;
            push @columns,
                {
                module            => $module,
                page              => $page,
                tablename         => $tablename,
                columnname        => $3,
                is_hidden         => $is_hidden,
                cannot_be_toggled => $cannot_be_toggled,
                };
        }

        C4::Utils::DataTables::TablesSettings::update_columns(
            {
                columns => \@columns,
            }
        );

        my $table_id                  = $cgi->param('table_id');
        my $default_display_length    = $cgi->param( $table_id . '_default_display_length' );
        my $default_sort_order        = $cgi->param( $table_id . '_default_sort_order' );
        my $default_save_state        = $cgi->param( $table_id . '_default_save_state' );
        my $default_save_state_search = $cgi->param( $table_id . '_default_save_state_search' );

        undef $default_display_length if defined $default_display_length && $default_display_length eq "";
        undef $default_sort_order     if defined $default_sort_order     && $default_sort_order eq "";
        $default_save_state        //= 0;
        $default_save_state_search //= 0;

        if ( defined $default_display_length || defined $default_sort_order || defined $default_save_state ) {
            C4::Utils::DataTables::TablesSettings::update_table_settings(
                {
                    module                    => $module,
                    page                      => $page,
                    tablename                 => $tablename,
                    default_display_length    => $default_display_length,
                    default_sort_order        => $default_sort_order,
                    default_save_state        => $default_save_state,
                    default_save_state_search => $default_save_state_search,
                }
            );
        }

        $self->go_home();
    }
}

=head3 create_stage_file

Takes a list of MARC::Records, creates a new uploaded_file for staging MARC records.

=cut

sub create_stage_file {
    my ( $self, $params ) = @_;

    my $host_record_id = $params->{'host_record_id'};
    my @results        = @{ $params->{'results'} };

    my $filename = "MELINDA-COMPONENT-PARTS-OF-HOST-$host_record_id";
    my $upload   = Koha::Uploader->new;

    my $contents = $self->_build_marcxml_results(@results);
    my $fh       = $upload->_hook( $filename, $contents );

    $upload->_done;

    return ( $upload, $upload->_dir . "/" . $upload->{files}->{$filename}->{hash} . '_' . $filename );
}

=head3 commit_staged_marc_records

Commits staged MARC records

=cut

sub commit_staged_marc_records {
    my ( $self, $params ) = @_;

    my $stage_job_id = $params->{'stage_job_id'};

    Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit::NoStagedJob->throw(
        'job_id of staged records must be given')
        unless $stage_job_id;

    my $staged_job;

    # Wait for record staging to finish
    for ( my $i = 0 ; $i < ( $params->{'timeout'} // 60 ) ; $i++ ) {
        $staged_job = Koha::BackgroundJobs->find($stage_job_id);

        if ( $staged_job->status ne 'finished' && $staged_job->status ne 'failed' ) {
            sleep 1;
        } else {
            last;
        }
    }

    Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit::NoStagedJob->throw(
        'Staged job not found')
        unless $staged_job;

    Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::Commit::StagedJobFailed->throw(
        'Staged job failed')
        if $staged_job->status eq 'failed';

    my $staged_data     = decode_json( $staged_job->data );
    my $import_batch_id = $staged_data->{'report'}->{'import_batch_id'};

    my $commit_params = {
        overlay_framework => $params->{'overlay_framework'} // "",
        frameworkcode     => $params->{'frameworkcode'}     // "",
        import_batch_id   => $import_batch_id,
    };
    my $job_id = Koha::BackgroundJob::MARCImportCommitBatch->new->enqueue($commit_params);

    return $job_id;
}

=head3 search_melinda_for_component_parts

Connects to Melinda SRU server and performs a "melinda.partsofhost" query using host record's 001 field.

Returns a list of found MARC::Records.

Throws,

Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer::Connection
    if connection to SRU server fails

=cut

sub search_melinda_for_component_parts {
    my ( $self, $params ) = @_;

    my $host_record_id = $params->{'host_record_id'};

    my $cache = Koha::Caches->get_instance();

    if ( my $results = $cache->get_from_cache("melindacpi_$host_record_id") ) {
        return @$results;
    }

    my $melinda_sru_server = Koha::Z3950Servers->find( $self->retrieve_data('sru_target') )->unblessed;
    my $melinda            = C4::Breeding::_create_connection($melinda_sru_server);

    my $result = $melinda->search( ZOOM::Query::CQL->new("melinda.partsofhost=$host_record_id") );

    while ( ( my $k = ZOOM::event( [$melinda] ) ) != 0 ) {
        my $event = $melinda->last_event();
        last if $event == ZOOM::Event::ZEND;
    }

    my ($error) = $melinda->error_x;
    Koha::Plugin::Fi::Hypernova::MelindaComponentPartsImporter::Exceptions::SRUServer::Connection->throw(
        'Connection error ' . ref($error) eq 'HASH' ? $error->{'error_msg'} : $error )
        if $error;

    my @records;
    my $result_size = $result->size;
    my $max_results = $self->retrieve_data('max_results') // 1000;
    for ( my $i = 0 ; $i < ( $result_size > $max_results ? $max_results : $result_size ) ; $i++ ) {
        my $zoomrecord = $result->record($i);
        my $raw        = $zoomrecord->raw();
        my $marcrecord;
        $marcrecord = MARC::Record->new_from_xml(
            $raw, 'UTF-8',
            $melinda_sru_server->{'syntax'}
        );
        $marcrecord->encoding('UTF-8');
        C4::Charset::SetUTF8Flag($marcrecord);

        push( @records, $marcrecord );
    }

    $cache->set_in_cache( "melindacpi_$host_record_id", \@records, { expiry => 300 } );

    return @records;
}

=head3 stage_marc_for_import

Stages MARCXML file for import.

Sets some default matching settings.

=cut

sub stage_marc_for_import {
    my ( $self, $params ) = @_;

    $params->{'item_action'}                //= 'ignore';
    $params->{'marc_modification_template'} //= '';
    $params->{'matcher_id'}                 //= $self->retrieve_data('default_matcher_id') || "";
    $params->{'nomatch_action'}             //= 'create_new';
    $params->{'overlay_action'}             //= 'replace';

    my $stage_params = {
        record_type                => 'biblio',
        encoding                   => 'UTF-8',
        format                     => 'MARCXML',
        filepath                   => $params->{filepath},
        filename                   => File::Basename::basename( $params->{filepath} ),
        marc_modification_template => $params->{'marc_modification_template_id'},
        comments                   => 'Melinda Component Parts Importer plugin',
        parse_items                => $params->{'item_action'} eq 'ignore' ? 0 : 1,
        matcher_id                 => $params->{'matcher_id'},
        overlay_action             => $params->{'overlay_action'},
        nomatch_action             => $params->{'nomatch_action'},
        item_action                => $params->{'item_action'},
    };
    my $job_id = Koha::BackgroundJob::StageMARCForImport->new->enqueue($stage_params);

    return $job_id;
}

sub install {
    my ($self) = @_;

    my ( $module, $page, $tablename ) = $self->_search_results_table_settings;

    my $schema = Koha::Database->new->schema;
    $schema->resultset('TablesSetting')->update_or_create(
        {
            module    => $module,
            page      => $page,
            tablename => $tablename,
        }
    );

    my $columns = $self->_search_results_table_columns()->{modules}->{$module}->{$page}->{$tablename}->{columns};

    for my $c (@$columns) {
        $c->{is_hidden}         //= 0;
        $c->{cannot_be_toggled} //= 0;

        $schema->resultset('ColumnsSetting')->update_or_create(
            {
                module            => $module,
                page              => $page,
                tablename         => $tablename,
                columnname        => $c->{columnname},
                is_hidden         => $c->{is_hidden},
                cannot_be_toggled => $c->{cannot_be_toggled},
            }
        );
    }

    return 1;
}

sub uninstall {
    my ($self) = @_;

    my ( $module, $page, $tablename ) = $self->_search_results_table_settings;

    my $schema           = Koha::Database->new->schema;
    my $columns_settings = $schema->resultset('ColumnsSetting')->search(
        {
            module    => $module,
            page      => $page,
            tablename => $tablename,
        }
    );
    $columns_settings->delete if $columns_settings;
    my $table_settings = $schema->resultset('TablesSetting')->find(
        {
            module    => $module,
            page      => $page,
            tablename => $tablename,
        }
    );
    $table_settings->delete if $table_settings;
    return 1;
}

sub _add_default_773w_matcher {
    my $matcher_id = C4::Matcher::GetMatcherId('MELIND773w');
    return $matcher_id if $matcher_id;

    my $matcher = C4::Matcher->new( 'biblio', 1000 );
    $matcher->code('MELIND773w');
    $matcher->description('773$w');
    $matcher->threshold(1000);
    $matcher->add_matchpoint(
        'record-control-number',
        1000,
        [
            {
                tag       => 773,
                subfields => 'w',
                offset    => 0,
                length    => 0,
                norms     => ['remove_spaces']
            }
        ]
    );

    return $matcher->store();
}

sub _add_default_melinda_sru {
    my $melinda_id = Koha::Z3950Servers->search( { host => 'https://sru.api.melinda.kansalliskirjasto.fi' } );
    if ( $melinda_id->count == 0 ) {
        $melinda_id = Koha::Z3950Server->new(
            {
                host       => 'https://sru.api.melinda.kansalliskirjasto.fi',
                port       => 443,
                db         => 'bib',
                servername => 'MELINDA SRU',
                checked    => 1,
                syntax     => 'USMARC',
                servertype => 'sru',
                encoding   => 'utf8',
                recordtype => 'biblio',
                sru_fields =>
                    'title=dc.title,isbn=bath.isbn,controlnumber=rec.id,author=dc.author,issn=bath.issn,subject=dc.subject',
            }
        )->store->id;
    } else {
        $melinda_id = $melinda_id->next->id;
    }

    return $melinda_id;
}

sub _build_marcxml_results {
    my ( $self, @results ) = @_;
    my $contents = "";
    $contents .= MARC::File::XML::header();
    foreach my $record (@results) {
        $contents .= MARC::File::XML::record($record);
    }
    $contents .= MARC::File::XML::footer();

    return Encode::encode_utf8($contents);
}

sub _build_mij_results {
    my ( $self, @results ) = @_;
    my @mij;

    foreach my $record (@results) {
        push( @mij, $record->to_mij_structure() );
    }

    return @mij;
}

sub _search_results_table_settings {
    return ( 'catalogue', 'detail', 'melindacpi_search_results' );
}

sub _search_results_table_columns {
    my ($self) = @_;
    my ( $module, $page, $tablename ) = _search_results_table_settings();
    return {
        modules => {
            $module => {
                $page => {
                    $tablename => {
                        columns => [
                            {
                                columnname => '130a',
                                is_hidden  => 1
                            },
                            {
                                columnname => '240a',
                                is_hidden  => 1
                            },
                            {
                                columnname => '245a',
                            },
                            {
                                columnname => 'Melinda',
                            },
                        ]
                    }
                }
            }
        }
    };
}

1;
