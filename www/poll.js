/* Data retrieval attempts will first be made here. Most likely,
 * it will only work behind the firewall. */
var raspi_url = "http://"+window.location.hostname+":9001/data.json"

/* If data can't be retrieved directly, the latest ones are queried
 * from AirVantage. This is the configuration indicating
 * which system is expected, and which API key is used. */
var av_cfg = {
    system:       '55059f15026443bf89cd3a763210f5e8',
    server:       'eu.airvantage.net',
    clientId:     'cb030f34d11b40db9a5d92a1cbc3620c',
    clientSecret: '80da79f0b85247e9adb7f59ae5b34043' }

/* After the first AirVantage retrieval, the access token is kept
 * here and not queried again. */
var av_access_token

/* Update the HTML fields with newly acquired and formatted data. */
function fill(record) {
    console.log("values Update\n")
    for(var key in record) {
        var value = record[key]
        $("#"+key).text(value)
        $("."+key).text(value)
    }
}

/* How to convert raw data names and values.
 * `name` is the JavaScript name of the data;
 * `conv` is an optional function converting the value into a display-friendly one. */
var converters = {
    "boat.bmv.voltage": { name: "voltage_battery", tofixed: 1 },
    "boat.bmv.current": { name: "current_battery" },
    "boat.bmv.consumed_energy": { name: "consumed_energy" },
    "boat.bmv.state_of_charge": { name: "state_of_charge" },
    "boat.bmv.time_to_go": { name: "time_to_go" },

    "boat.mppt.power_panels":    { name: "power_panels", tofixed: 0 },
    "boat.mppt.voltage_panels":  { name: "voltage_panels", tofixed: 1 },
    "boat.mppt.current_battery": { name: "mppt_ibatt" }, // Used to compute power
    "boat.mppt.voltage_battery": { name: "mppt_vbatt" }, // Used to compute power
    "_LATITUDE": { name: "latitude" },
    "_LONGITUDE": { name: "longitude" },
    "timestamp": { name: "timestamp", conv: function(d) { return ""+new Date(1000*d) } },
    "origin": { name: "origin" }
}

/* Try to get a data record straight from the Raspberry. Upon failure,
 * tries to contact AirVantage instead. */
function refresh() {
    $.getJSON(raspi_url)
	.success(parse_raspi_data)
	.fail(refresh_av)
}

/* Got Raspi data; reformat and insert in the HTML. */
function parse_raspi_data(record) {
    record.origin = 'Raspberry'
    record.timestamp = Date.now()
    fill(reformat_data(record))
}

/* Can't get data from Raspberry.
 * If there's an AV access token, retrieve data from AV.
 * If there isn't, load the password and request one first. */
function refresh_av() {
    console.log("No direct access, trying through AirVantage")
    if( av_access_token) { get_av_data() }
    else { get_av_auth() }
}

/* Load the login and password, needed to request an access token.
 * The loaded script file should read:
 *
 *     var auth = {
 *       login:        'mail@company.com',
 *       password:     's3kr3tP455w0rd!'
 *     }
 *
 * TODO: properly handle the case when password file is not found.
 */
function get_av_auth() {
    console.log("Retrieve AirVantage credentials")
    /* Circumvent Chrome's refusal to load local files. */
    if(navigator.userAgent.match('Chrome') && location.protocol=='file:') {
        $.ajaxPrefilter( "json script", function(options) {
            options.crossDomain = true;
        });
    }
    $.getScript('auth-airvantage.js', get_av_token)
}

/* Use the login+password to request the access token. */
function get_av_token() {
    console.log("Request AirVantage access token")
    var TOKEN_URL="https://"+av_cfg.server+"/api/oauth/token?grant_type=password"+
    "&username="+auth.login+"&password="+auth.password+
    "&client_id="+av_cfg.clientId+"&client_secret="+av_cfg.clientSecret
    var record = $.getJSON(TOKEN_URL, parse_av_token)
}

/* Token received; save it and proceed to request data from AirVantage. */
function parse_av_token(record) {
    av_access_token = record.access_token
    get_av_data()
}

/* Request data from AirVantage;
 * the access token must already be in `av_access_token`. */
function get_av_data() {
    console.log("Retrieving latest data from AirVantage")
    var DATA_URL = "https://"+av_cfg.server+"/api/v1/systems/"+av_cfg.system+
	"/data?access_token="+av_access_token
    $.getJSON(DATA_URL, parse_av_data)
}

/* Reformat AirVantage data (mostly gets rid of
 *  the nested timestamp/value records, and of extra values). */
function parse_av_data(av_record) {
    var record = { }
    for(var path in av_record) { record[path] = av_record[path][0].value }
    record.timestamp = av_record['boat.bmv.voltage'][0].timestamp/1000
    record.origin = av_cfg.server
    fill(reformat_data(record))
}

/* Apply data converters found in `converters`, removes unused data. */
function reformat_data(raw_record) {
    var record = { }
    for(var path in raw_record) {
        var x = converters[path]
        if( ! x) { if( ! Number(path)) console.log("Can't parse "+path); continue; }
        var raw_value = raw_record[path]
        var key = x.name
        if( x.conv) { value = x.conv(raw_value) } else { value = raw_value; }
        if( x.tofixed != undefined) { console.log("Fixing "+x.tofixed+" decimals for "+key); value = Number.parseFloat(value).toFixed(x.tofixed); }
        record[key] = value
        console.log(key+" = "+value)
    }
    record.solar_power_battery=(record.mppt_ibatt*record.mppt_vbatt).toFixed(0)
    record.out_power_battery = (
        record.solar_power_battery - record.voltage_battery*record.current_battery
    ).toFixed(0)
    return record
}

var REFRESH_PERIOD = 5 // Refresh every `PERIOD` seconds

$(document).ready(function() {
    $("#refresh").click(refresh)
    //setInterval(refresh, REFRESH_PERIOD*1000)
    refresh()
})

