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

use File::Basename;
use MARC::File::XML;
use MARC::Record;
use Mojo::JSON qw(decode_json);
use YAML;
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

our $VERSION = "24.11.01.0";

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
    my ($self)      = @_;
    my $cgi         = $self->{'cgi'};
    my $script_name = $cgi->script_name;
    my $js          = <<'JS';
    <script>
        let frameworks;
        let records_fetched = false;

        $(document).ready(function(){
            if ($("body#catalog_detail").length > 0) {
                $("body#catalog_detail main div#bibliodetails").after(`
                    <div class="modal fade" id="searchFromMelinda" tabindex="-1" aria-labelledby="searchFromMelindaLabel" aria-hidden="true">
                        <div class="modal-dialog">
                            <div class="modal-content">
                            <div class="modal-header">
                                <h1 class="modal-title fs-5" id="searchFromMelindaLabel">Melinda Search</h1>
                                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                            </div>
                            <div class="modal-body">
                                <table id="melindacpi_search_results">
                                    <thead>
                                        <tr>
                                            <th>130a</th>
                                            <th>240a</th>
                                            <th>245a</th>
                                            <th>Melinda</th>
                                        </tr>
                                    </thead>
                                </table>
                            </div>
                            <div class="modal-footer">
                                <button type="button" class="btn btn-primary dropdown-toggle" id="import-melinda-button" data-bs-toggle="dropdown" disabled>Quick import</button>
                                <ul id="importFromMelindaFrameworks" aria-labelledby="import-melinda-button" class="dropdown-menu">
                                </ul>
                                <form id="melinda_stage_component_records">
                                    <button type="submit" class="btn btn-primary" id="stage-melinda-button" data-bs-target="#importFromMelinda" data-bs-toggle="modal" disabled>Stage records for import</button>
                                </form>
                                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                            </div>
                            </div>
                        </div>
                    </div>
                    <div class="modal fade" id="importFromMelinda" tabindex="-1" aria-labelledby="importFromMelindaLabel" aria-hidden="true">
                        <div class="modal-dialog">
                            <div class="modal-content">
                            <div class="modal-header">
                                <h1 class="modal-title fs-5" id="importFromMelindaLabel">Melinda Component Records</h1>
                                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                            </div>
                            <div class="modal-body">
                                <span id="importFromMelindaResult">Preparing records...</span>
                                <span id="importFromMelindaResultForStage" style="display:none;">
                                    <div class="alert alert-info">Records have been staged</div>
                                    <p>Records can now be imported using the Manage staged MARC records tool.</p>
                                </span>
                                <span id="importFromMelindaResultstep2" style="display:none;"><p>Koha will import component parts in a background job. This may take a moment. Please wait...</p></span>
                                <div id="importFromMelindaResultTable" style="display:none">
                                    <h2>Results</h2>
                                    <div class="alert alert-info">Completed import of component records</div>
                                    <table>
                                        <tbody><tr>
                                            <td>Number of records added</td>
                                            <td id="importFromMelindaResultTable_num_added">0</td>
                                        </tr>
                                        <tr>
                                            <td>Number of records updated</td>
                                            <td id="importFromMelindaResultTable_num_updated">0</td>
                                        </tr>
                                        <tr>
                                            <td>Number of records ignored</td>
                                            <td id="importFromMelindaResultTable_num_ignored">0</td>
                                        </tr>
                                    </tbody></table>
                                    <p><a href="" id="importFromMelindaBatchHref" target="_blank">Manage imported batch</a></p>
                                    <p>Koha will now index records in the background.</p>
                                </div>
                                <div class="dt-container"><div id="melindacpi_processing_import" class="dt-processing" role="status" style="display: none;">Processing...<div><div></div><div></div><div></div><div></div></div></div></div>
                            </div>
                            <div class="modal-footer">
                                <a href="" id="importFromMelindaRefresh" class="btn btn-success" style="display:none;">Finish (refresh page)</a>
                                <a href="" id="importFromMelindaManageMARC" class="btn btn-success" style="display:none;">Manage staged MARC records</a>
                                <a href="" id="importFromMelindaResultHref" class="btn btn-primary" style="display:none;">Check job status</a>
                                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                            </div>
                            </div>
                        </div>
                    </div>
                `);
                $("body#catalog_detail main div#toolbar a#newsub").parent("li").after(`
                    <li>
                        <a href="#searchFromMelinda" class="dropdown-item" data-bs-toggle="modal" data-bs-target="#searchFromMelinda">Fetch component parts from Melinda</a>
                    </li>
                `);
                $("ul#importFromMelindaFrameworks").on("click", "li a", function(e) {
                    e.preventDefault();
                    melindacpi_reset_modal_defaults();
                    let frameworkcode = $(this).attr('data-frameworkcode');
                    $("button#stage-melinda-button").prop("disabled", true);
                    $("div#melindacpi_processing_import").show();
                    $.ajax({
                        url: '/api/v1/contrib/melinda-component-parts-importer/biblio/'+biblionumber+'/component-parts?quickimport=true&frameworkcode='+frameworkcode,
                        type: 'POST',
                        success: function(data){
                            $("span#importFromMelindaResult").hide();
                            $("span#importFromMelindaResultstep2").show();
                            $("a#importFromMelindaResultHref").show();
                            $("a#importFromMelindaResultHref").attr("href", "/cgi-bin/koha/admin/background_jobs.pl?op=view&id="+data.job_id);

                            let job_finished = false;
                            var check_job_i = 0;
                            var interval = setInterval(function() { 
                                if (job_finished || check_job_i >= 12) {
                                    clearInterval(interval);
                                    return;
                                }
                                
                                $.ajax({
                                    url: '/api/v1/jobs/'+data.job_id,
                                    type: 'GET',
                                    success: function(data_job){
                                        if (data_job.status === 'finished') {
                                            job_finished = true;
                                            $("div#melindacpi_processing_import").hide();
                                            $("span#importFromMelindaResultstep2").hide();
                                            $("div#importFromMelindaResultTable").show();
                                            $("td#importFromMelindaResultTable_num_added").html(data_job.data.report.num_added);
                                            $("td#importFromMelindaResultTable_num_ignore").html(data_job.data.report.num_ignored);
                                            $("td#importFromMelindaResultTable_num_updated").html(data_job.data.report.num_updated);
                                            $("a#importFromMelindaRefresh").show();
                                            $("a#importFromMelindaBatchHref").attr("href", "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id="+data_job.data.import_batch_id);
                                            $("button#stage-melinda-button").prop("disabled", false);
                                        } else if (data_job.status === 'failed') {
                                            job_finished = true;
                                            $("div#melindacpi_processing_import").hide();
                                            $("span#importFromMelindaResultstep2").hide();
                                            $("div#importFromMelindaResultTable").show();
                                            $("td#importFromMelindaResultTable_num_added").html(data_job.data.report.num_added);
                                            $("td#importFromMelindaResultTable_num_ignore").html(data_job.data.report.num_ignored);
                                            $("td#importFromMelindaResultTable_num_updated").html(data_job.data.report.num_updated);
                                            $("a#importFromMelindaRefresh").show();
                                            $("a#importFromMelindaBatchHref").attr("href", "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id="+data_job.data.import_batch_id);
                                            $("button#stage-melinda-button").prop("disabled", false);
                                            alert("Failed! See console log.");
                                            console.log(data_job);
                                        }
                                    },
                                    error: function(data_job){
                                        $("div#melindacpi_processing_import").hide();
                                        console.log(data_job);
                                    }
                                });

                                check_job_i++;
                            }, 5000);
                        },
                        error: function(data){
                            console.log(data);
                        }
                    });
                });
                const searchFromMelindaModalEl = document.getElementById('searchFromMelinda');
                searchFromMelindaModalEl.addEventListener('show.bs.modal', event => {

                    if (frameworks == null || frameworks.length === 0) {
                        $.ajax({
                            url: '/api/v1/contrib/melinda-component-parts-importer/frameworks',
                            type: 'GET',
                            success: function(data){
                                frameworks = data;
                                let framework_list_els = "";
                                frameworks.forEach((framework) => {
                                    framework_list_els += '<li><a class="dropdown-item" href="#" data-frameworkcode="'+ framework.frameworkcode +'" data-bs-target="#importFromMelinda" data-bs-toggle="modal" >' + framework.frameworktext + '</a>';
                                });
                                $("ul#importFromMelindaFrameworks").html(framework_list_els);
                            },
                            error: function(data){
                                console.log(data);
                            }
                        });
                    }

                    if (records_fetched) {
                        return;
                    }

                    let melindacpi_search_results_table_settings = __MELINDACPI_SEARCH_RESULTS_TABLE_SETTINGS__;
                    var melindacpi_search_results_table = $("table#melindacpi_search_results").kohaTable({
                        "ajax": {
                            "url": '/api/v1/contrib/melinda-component-parts-importer/biblio/'+biblionumber+'/search-component-parts',
                            "headers": {
                                Accept: "application/marc-in-json",
                            }
                        },
                        "order": [],
                        "searching": false,
                        "emptyTable": '<div class="alert alert-info">' + _("No results found.") + '</div>',
                        "columns": [
                            {
                                "data": function (row, type, set, meta) {
                                    return get_field_from_mij_row(row, '130', 'a');
                                },
                                orderable: true, 
                                searchable: false
                            },
                            {
                                "data": function (row, type, set, meta) {
                                    return get_field_from_mij_row(row, '240', 'a');
                                },
                                orderable: true, 
                                searchable: false
                            },
                            {
                                "data": function (row, type, set, meta) {
                                    return get_field_from_mij_row(row, '245', 'a');
                                },
                                orderable: true, 
                                searchable: false,
                            },
                            {
                                "data": function (row, type, set, meta) {
                                    let record_id = get_field_from_mij_row(row, '001');
                                    if (record_id) {
                                        return '<a class="btn btn-default btn-xs" href="https://melinda.kansalliskirjasto.fi/byid/' + get_field_from_mij_row(row, '001') + '" target=_blank><i class="fa fa-external-link" aria-hidden="true"></i> Melinda</a>';
                                    } else {
                                        return "";
                                    }
                                },
                                orderable: false,
                                searchable: false,
                            },
                        ],
                        "drawCallback": function ( oSettings ) {
                            $("button#stage-melinda-button").prop("disabled", false);
                            $("button#import-melinda-button").prop("disabled", false);
                            records_fetched = true;
                        }
                    }, melindacpi_search_results_table_settings );
                });

                function melindacpi_reset_modal_defaults() {
                    $("div#melindacpi_processing_import").hide();
                    $("span#importFromMelindaResultstep2").hide();
                    $("div#importFromMelindaResultTable").hide();
                    $("span#importFromMelindaResult").show();
                    $("span#importFromMelindaResultForStage").hide();
                    $("a#importFromMelindaRefresh").hide();
                    $("a#importFromMelindaManageMARC").hide();
                    $("a#importFromMelindaResultHref").hide();
                    $("button#stage-melinda-button").prop("disabled", false);
                }

                $("form#melinda_stage_component_records").on("submit", function(e) {
                    e.preventDefault();
                    melindacpi_reset_modal_defaults();
                    $("button#stage-melinda-button").prop("disabled", true);
                    $("div#melindacpi_processing_import").show();
                    $.ajax({
                        url: '/api/v1/contrib/melinda-component-parts-importer/biblio/'+biblionumber+'/component-parts',
                        type: 'POST',
                        success: function(data){
                            let job_finished = false;
                            var check_job_i = 0;
                            var interval = setInterval(function() { 
                                if (job_finished || check_job_i >= 12) {
                                    clearInterval(interval);
                                    return;
                                }
                                
                                $.ajax({
                                    url: '/api/v1/jobs/'+data.job_id,
                                    type: 'GET',
                                    success: function(data_job){
                                        if (data_job.status === 'finished') {
                                            job_finished = true;
                                            $("div#melindacpi_processing_import").hide();
                                            $("span#importFromMelindaResult").hide();
                                            $("span#importFromMelindaResultForStage").show();
                                            $("a#importFromMelindaManageMARC").show();
                                            $("a#importFromMelindaManageMARC").attr("href", "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id="+data_job.data.report.import_batch_id);
                                            $("a#importFromMelindaResultHref").attr("href", "/cgi-bin/koha/admin/background_jobs.pl?op=view&id="+data.job_id);
                                            $("a#importFromMelindaResultHref").hide(); // let's just hide the status button
                                            $("button#stage-melinda-button").prop("disabled", false);
                                        } else if (data_job.status === 'failed') {
                                            job_finished = true;
                                            $("div#melindacpi_processing_import").hide();
                                            $("span#importFromMelindaResult").hide();
                                            $("span#importFromMelindaResultForStage").show();
                                            $("a#importFromMelindaManageMARC").show();
                                            $("a#importFromMelindaManageMARC").attr("href", "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id="+data_job.data.report.import_batch_id);
                                            $("a#importFromMelindaResultHref").attr("href", "/cgi-bin/koha/admin/background_jobs.pl?op=view&id="+data.job_id);
                                            $("a#importFromMelindaResultHref").hide(); // let's just hide the status button
                                            $("button#stage-melinda-button").prop("disabled", false);
                                            alert("Failed! See console log.");
                                            console.log(data_job);
                                        }
                                    },
                                    error: function(data_job){
                                        $("div#melindacpi_processing_import").hide();
                                        console.log(data_job);
                                    }
                                });

                                check_job_i++;
                            }, 5000);
                        },
                        error: function(data){
                            console.log(data);
                        }
                    });
                });
            }
        });

        function get_field_from_mij_row(row, tagfield, tagsubfield) {
            let response = "";
            if (tagsubfield == null) {
                tagsubfield = '';
            }
            row.fields.forEach((field) => {
                if (tagfield in field) {
                    if (tagsubfield.length && 'subfields' in field[tagfield]) {
                        field[tagfield]['subfields'].forEach((subfield) => {
                            if (tagsubfield in subfield) {
                                response = subfield[tagsubfield];
                                return response;
                            }
                        });
                    } else if (!tagsubfield.length) {

                        response = field[tagfield];
                        return response;
                    }
                }
                if (response.length > 0) return response;
            });
            return response;
        }
    </script>
JS

    if ( $script_name =~ /detail\.pl/ ) {
        my ( $module, $page, $tablename ) = $self->_search_results_table_settings;
        local *C4::Utils::DataTables::TablesSettings::get_yaml = sub { return $self->_search_results_table_columns };
        my $table_settings =
            Koha::Template::Plugin::TablesSettings->GetTableSettings( $module, $page, $tablename, 'json' );
        $js =~ s/__MELINDACPI_SEARCH_RESULTS_TABLE_SETTINGS__/$table_settings/;
        return "$js";
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

    return $contents;
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
