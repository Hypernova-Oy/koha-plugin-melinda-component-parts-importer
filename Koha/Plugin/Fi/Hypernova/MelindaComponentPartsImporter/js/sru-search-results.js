let records_fetched = false;
let frameworks = __MCPI_PLUGIN_FRAMEWORKS__;

$(document).ready(function () {
    __MCPI_PLUGIN_TRANSLATE_FUNCTION__
    if ($("body#cat_z3950_search").length > 0) {
        $("td.actions ul.dropdown-menu").on('click', 'a.import_with_cr', function(e) {
            e.preventDefault();
            $("table#resultst").find('div#melindacpi_processing_import').show();
            $(this).closest('ul.dropdown-menu').parent().closest('ul.dropdown-menu').toggle();
            let importid = $(this).attr("data-import-record-id");
            let frameworkcode = $(this).attr("data-import-frameworkcode");
            let continue_href = $(this).attr('data-href');
            $.ajax({
                url: '/api/v1/contrib/melinda-component-parts-importer/biblio/component-parts?import_record_id='+importid+'&quickimport=true&frameworkcode=' + frameworkcode,
                type: 'POST',
                async: false,
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
                                    $("table#resultst").find('div#melindacpi_processing_import').hide();
                                    job_finished = true;
                                    opener.document.location = continue_href;
                                    window.close();
                                } else if (data_job.status === 'failed') {
                                    $("table#resultst").find('div#melindacpi_processing_import').hide();
                                    job_finished = true;
                                    alert(__mcpi("importing_records_failed") + "\n" + JSON.stringify(data_job));
                                    console.log(data_job);
                                }
                            },
                            error: function (data_job) {
                                $("table#resultst").find('div#melindacpi_processing_import').hide();
                                alert(__mcpi("importing_records_failed"));
                                console.log(data_job + "\n" + JSON.stringify(data_job));
                            }
                        });
        
                        check_job_i++;
                    }, 5000);
                },
                error: function (data) {
                    $("table#resultst").find('div#melindacpi_processing_import').hide();
                    alert(__mcpi("importing_records_failed"));
                    console.log(data + "\n" + JSON.stringify(data));
                }
            });
        });

        $("table#resultst").append(`
           <div class="dt-container"><div class="dt-processing" id="melindacpi_processing_import" role="status" style="display: none;"><div class="loading"><img src="`+interface+`/`+theme+`/img/spinner-small.gif" alt="" /></div><div><div></div><div></div><div></div><div></div></div></div></div> 
        `);
        $("table#resultst tr").each(function () {
            let osakohteet;
            let row = $(this);
            let source = row.find("td:first").html();
            if (source !== __MCPI_PLUGIN_DEFAULT_SRU_TARGET__) return;
            let importid_re = /importid=(\d+)$/;
            let importid_match = importid_re.exec(row.find('li>a[href^="/cgi-bin/koha/catalogue/showmarc.pl?importid="]').attr("href"));
            let importid = "";
            if (importid_match.length === 2) {
                importid = importid_match[1];
            }
            // enable spinner
            let title_col = row.find("td:nth-child(2)");
            title_col.append('<div class="mcpi_display"><div class="mcpi_display_loader"><div class="loading"><img src="'+interface+'/'+theme+'/img/spinner-small.gif" alt="" /></div></div><ul class="mcp_display_component_parts"></ul></div>');
            $.ajax({
                url: '/api/v1/contrib/melinda-component-parts-importer/biblio/search-component-parts?import_record_id=' + importid,
                type: 'GET',
                dataType: "json",
                headers: {
                    Accept: "application/marc-in-json"
                },
                success: function (data) {
                    let found_osakohteet = false;
                    if (data.length > 0) {
                        console.log(data);
                        if ('fields' in data[0]) {
                            // data looks okay.
                            osakohteet = data;
                            console.log(osakohteet);
                            osakohteet.forEach((osakohde) => {
                                osakohde['fields'].forEach((field) => {
                                    if ('245' in field && 'subfields' in field['245']) {
                                        field['245']['subfields'].forEach((subfield) => {
                                            if ('a' in subfield) {
                                                title_col.find('ul.mcp_display_component_parts').append("<li>" + subfield['a'] + "</li>");
                                                title_col.find('div.mcpi_display_loader').css("display", "none");
                                                found_osakohteet = true;
                                                return;
                                            }
                                        });
                                    }
                                });
                            });
                        }
                    }
                    if (!found_osakohteet) {
                        title_col.find('div.mcpi_display').css("display", "none");
                    } else {
                        let import_href = row.find('td.actions ul.dropdown-menu li a[data-action="import"]').attr("href");
                        row.find('td.actions button.dropdown-toggle').attr('data-bs-auto-close', 'outside');
                        row.find('td.actions ul.dropdown-menu').append(`
                            <li>
                                <div class="btn-group dropstart" role="group">
                                    <button type="button" class="btn btn-seconday dropdown-toggle dropdown-toggle-split" data-bs-toggle="dropdown" aria-expanded="false" data-bs-auto-close="outside">
                                            `+__mcpi("import_with_cr")+`
                                    </button>
                                    <ul class="dropdown-menu dropdown-menu-end child_frameworks">
                                    </ul>
                                </div>
                        `);                        
                        row.find('td.actions ul.dropdown-menu ul.child_frameworks').append('<li><a href="'+import_href+'" data-href="'+import_href+'" class="import_with_cr dropdown-item" data-import-record-id="'+importid+'" data-import-frameworkcode=""><i class="fa fa-download"></i> '+__mcpi("framework_default")+'</a></li>');
                        frameworks.forEach((framework) => {
                            console.log(framework);
                            row.find('td.actions ul.dropdown-menu ul.child_frameworks').append('<li><a href="'+import_href+'" data-href="'+import_href+'" class="import_with_cr dropdown-item" data-import-record-id="'+importid+'" data-import-frameworkcode="'+framework.frameworkcode+'"><i class="fa fa-download"></i> '+framework.frameworktext+'</a></li>');
                        });
                        row.find('td.actions ul.dropdown-menu').append('</ul></li>');
                    }
                },
                error: function (data) {
                    title_col.find('div.mcpi_display').css("display", "none");
                    console.log(data);
                }
            });
        });
    }
});
