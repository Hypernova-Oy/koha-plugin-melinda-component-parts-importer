let frameworks;
let records_fetched = false;


$(document).ready(function () {
    __MCPI_PLUGIN_TRANSLATE_FUNCTION__
    if ($("body#catalog_detail").length > 0) {
        $("body#catalog_detail main div#bibliodetails").after(`
                    <div class="modal fade" id="searchFromMelinda" tabindex="-1" aria-labelledby="searchFromMelindaLabel" aria-hidden="true">
                        <div class="modal-dialog">
                            <div class="modal-content">
                            <div class="modal-header">
                                <h1 class="modal-title fs-5" id="searchFromMelindaLabel">`+__mcpi("melinda_search")+`</h1>
                                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="`+__mcpi("button_close")+`"></button>
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
                                <button type="button" class="btn btn-primary dropdown-toggle" id="import-melinda-button" data-bs-toggle="dropdown" disabled>`+__mcpi("quick_import")+`</button>
                                <ul id="importFromMelindaFrameworks" aria-labelledby="import-melinda-button" class="dropdown-menu">
                                </ul>
                                <form id="melinda_stage_component_records">
                                    <button type="submit" class="btn btn-primary" id="stage-melinda-button" data-bs-target="#importFromMelinda" data-bs-toggle="modal" disabled>`+__mcpi("stage_records")+`</button>
                                </form>
                                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">`+__mcpi("button_close")+`</button>
                            </div>
                            </div>
                        </div>
                    </div>
                    <div class="modal fade" id="importFromMelinda" tabindex="-1" aria-labelledby="importFromMelindaLabel" aria-hidden="true">
                        <div class="modal-dialog">
                            <div class="modal-content">
                            <div class="modal-header">
                                <h1 class="modal-title fs-5" id="importFromMelindaLabel">`+__mcpi("melinda_component_records")+`</h1>
                                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="`+__mcpi("button_close")+`"></button>
                            </div>
                            <div class="modal-body">
                                <span id="importFromMelindaResult">`+__mcpi("preparing_records")+`...</span>
                                <span id="importFromMelindaResultForStage" style="display:none;">
                                    <div class="alert alert-info">`+__mcpi("records_have_been_staged")+`</div>
                                    <p>`+__mcpi("records_can_be_imported")+`</p>
                                </span>
                                <span id="importFromMelindaResultstep2" style="display:none;"><p>`+__mcpi("koha_will_import")+`</p></span>
                                <div id="importFromMelindaResultTable" style="display:none">
                                    <h2>Results</h2>
                                    <div class="alert alert-info">`+__mcpi("completed_import")+`</div>
                                    <table>
                                        <tbody><tr>
                                            <td>`+__mcpi("no_records_added")+`</td>
                                            <td id="importFromMelindaResultTable_num_added">0</td>
                                        </tr>
                                        <tr>
                                            <td>`+__mcpi("no_records_updated")+`</td>
                                            <td id="importFromMelindaResultTable_num_updated">0</td>
                                        </tr>
                                        <tr>
                                            <td>`+__mcpi("no_records_ignored")+`</td>
                                            <td id="importFromMelindaResultTable_num_ignored">0</td>
                                        </tr>
                                    </tbody></table>
                                    <p><a href="" id="importFromMelindaBatchHref" target="_blank">`+__mcpi("manage_imported_batch")+`</a></p>
                                    <p>`+__mcpi("koha_will_index")+`</p>
                                </div>
                                <div class="dt-container"><div id="melindacpi_processing_import" class="dt-processing" role="status" style="display: none;"><div class="loading"><img src="`+interface+`/`+theme+`/img/spinner-small.gif" alt="" /></div><div><div></div><div></div><div></div><div></div></div></div></div>
                            </div>
                            <div class="modal-footer">
                                <a href="" id="importFromMelindaRefresh" class="btn btn-success" style="display:none;">`+__mcpi("button_finish")+`</a>
                                <a href="" id="importFromMelindaManageMARC" class="btn btn-success" style="display:none;">`+__mcpi("button_manage_staged_records")+`</a>
                                <a href="" id="importFromMelindaResultHref" class="btn btn-primary" style="display:none;">`+__mcpi("button_check_job_status")+`</a>
                                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">`+__mcpi("button_close")+`</button>
                            </div>
                            </div>
                        </div>
                    </div>
                `);
        $("body#catalog_detail main div#toolbar a#newsub").parent("li").after(`
                    <li>
                        <a href="#searchFromMelinda" class="dropdown-item" data-bs-toggle="modal" data-bs-target="#searchFromMelinda">`+__mcpi("fetch_components_from_melinda")+`</a>
                    </li>
                `);
        $("ul#importFromMelindaFrameworks").on("click", "li a", function (e) {
            e.preventDefault();
            melindacpi_reset_modal_defaults();
            let frameworkcode = $(this).attr('data-frameworkcode');
            $("button#stage-melinda-button").prop("disabled", true);
            $("div#melindacpi_processing_import").show();
            $.ajax({
                url: '/api/v1/contrib/melinda-component-parts-importer/biblio/component-parts?biblionumber=' + biblionumber + '&quickimport=true&frameworkcode=' + frameworkcode,
                type: 'POST',
                success: function (data) {
                    $("span#importFromMelindaResult").hide();
                    $("span#importFromMelindaResultstep2").show();
                    $("a#importFromMelindaResultHref").show();
                    $("a#importFromMelindaResultHref").attr("href", "/cgi-bin/koha/admin/background_jobs.pl?op=view&id=" + data.job_id);

                    let job_finished = false;
                    var check_job_i = 0;
                    var interval = setInterval(function () {
                        if (job_finished || check_job_i >= 12) {
                            clearInterval(interval);
                            return;
                        }

                        $.ajax({
                            url: '/api/v1/jobs/' + data.job_id,
                            type: 'GET',
                            success: function (data_job) {
                                if (data_job.status === 'finished') {
                                    job_finished = true;
                                    $("div#melindacpi_processing_import").hide();
                                    $("span#importFromMelindaResultstep2").hide();
                                    $("div#importFromMelindaResultTable").show();
                                    $("td#importFromMelindaResultTable_num_added").html(data_job.data.report.num_added);
                                    $("td#importFromMelindaResultTable_num_ignore").html(data_job.data.report.num_ignored);
                                    $("td#importFromMelindaResultTable_num_updated").html(data_job.data.report.num_updated);
                                    $("a#importFromMelindaRefresh").show();
                                    $("a#importFromMelindaBatchHref").attr("href", "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id=" + data_job.data.import_batch_id);
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
                                    $("a#importFromMelindaBatchHref").attr("href", "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id=" + data_job.data.import_batch_id);
                                    $("button#stage-melinda-button").prop("disabled", false);
                                    alert(__mcpi("failed_see_console_log"));
                                    console.log(data_job);
                                }
                            },
                            error: function (data_job) {
                                $("div#melindacpi_processing_import").hide();
                                console.log(data_job);
                            }
                        });

                        check_job_i++;
                    }, 5000);
                },
                error: function (data) {
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
                    success: function (data) {
                        frameworks = data;
                        let framework_list_els = "";
                        frameworks.forEach((framework) => {
                            framework_list_els += '<li><a class="dropdown-item" href="#" data-frameworkcode="' + framework.frameworkcode + '" data-bs-target="#importFromMelinda" data-bs-toggle="modal" >' + framework.frameworktext + '</a>';
                        });
                        $("ul#importFromMelindaFrameworks").html(framework_list_els);
                    },
                    error: function (data) {
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
                    "url": '/api/v1/contrib/melinda-component-parts-importer/biblio/search-component-parts?biblionumber=' + biblionumber,
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
                "drawCallback": function (oSettings) {
                    $("button#stage-melinda-button").prop("disabled", false);
                    $("button#import-melinda-button").prop("disabled", false);
                    records_fetched = true;
                }
            }, melindacpi_search_results_table_settings);
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

        $("form#melinda_stage_component_records").on("submit", function (e) {
            e.preventDefault();
            melindacpi_reset_modal_defaults();
            $("button#stage-melinda-button").prop("disabled", true);
            $("div#melindacpi_processing_import").show();
            $.ajax({
                url: '/api/v1/contrib/melinda-component-parts-importer/biblio/component-parts?biblionumber=' + biblionumber,
                type: 'POST',
                success: function (data) {
                    let job_finished = false;
                    var check_job_i = 0;
                    var interval = setInterval(function () {
                        if (job_finished || check_job_i >= 12) {
                            clearInterval(interval);
                            return;
                        }

                        $.ajax({
                            url: '/api/v1/jobs/' + data.job_id,
                            type: 'GET',
                            success: function (data_job) {
                                if (data_job.status === 'finished') {
                                    job_finished = true;
                                    $("div#melindacpi_processing_import").hide();
                                    $("span#importFromMelindaResult").hide();
                                    $("span#importFromMelindaResultForStage").show();
                                    $("a#importFromMelindaManageMARC").show();
                                    $("a#importFromMelindaManageMARC").attr("href", "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id=" + data_job.data.report.import_batch_id);
                                    $("a#importFromMelindaResultHref").attr("href", "/cgi-bin/koha/admin/background_jobs.pl?op=view&id=" + data.job_id);
                                    $("a#importFromMelindaResultHref").hide(); // let's just hide the status button
                                    $("button#stage-melinda-button").prop("disabled", false);
                                } else if (data_job.status === 'failed') {
                                    job_finished = true;
                                    $("div#melindacpi_processing_import").hide();
                                    $("span#importFromMelindaResult").hide();
                                    $("span#importFromMelindaResultForStage").show();
                                    $("a#importFromMelindaManageMARC").show();
                                    $("a#importFromMelindaManageMARC").attr("href", "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id=" + data_job.data.report.import_batch_id);
                                    $("a#importFromMelindaResultHref").attr("href", "/cgi-bin/koha/admin/background_jobs.pl?op=view&id=" + data.job_id);
                                    $("a#importFromMelindaResultHref").hide(); // let's just hide the status button
                                    $("button#stage-melinda-button").prop("disabled", false);
                                    alert(__mcpi("failed_see_console_log"));
                                    console.log(data_job);
                                }
                            },
                            error: function (data_job) {
                                $("div#melindacpi_processing_import").hide();
                                console.log(data_job);
                            }
                        });

                        check_job_i++;
                    }, 5000);
                },
                error: function (data) {
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