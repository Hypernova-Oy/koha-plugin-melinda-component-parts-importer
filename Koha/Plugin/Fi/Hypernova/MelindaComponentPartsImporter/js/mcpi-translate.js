function __mcpi(str) {
    let mcpi_translations = __MCPI_PLUGIN_TRANSLATIONS__;
    let mcpi_lang = $("html").attr("lang");
    if (str in mcpi_translations) {
        if (mcpi_lang in mcpi_translations[str]) {
            return mcpi_translations[str][mcpi_lang];
        } else if ('default' in mcpi_translations[str]) {
            return mcpi_translations[str]['default'];
        } else {
            alert("'"+str+"' has no default translation!");
        }
    } else {
        alert("'"+str+"' is not translated!");
    }
}