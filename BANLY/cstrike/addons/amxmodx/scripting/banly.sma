#include <amxmodx>
#include <reapi>
#include <cromchat>
#include <easy_http>
#include <nvault>

#pragma semicolon 1

#define CACHE_TTL 2700

enum _:ReqData { RD_ID, RD_USERID, RD_AUTH[MAX_AUTHID_LENGTH] };
enum _:PlayerState { PS_USERID, PS_REQUEST, PS_RETRIED };

new g_szApiKey[64];
new g_hVault = INVALID_HANDLE;
new g_aPlayer[MAX_PLAYERS + 1][PlayerState];

public plugin_init(){
    register_plugin("Banly.pl API", "v0.2", "Boziak.", "https://banly.pl");
    CC_SetPrefix("&x04[BANLY.PL]");

    g_hVault = nvault_open("banly_cache");
    if(g_hVault == INVALID_HANDLE) set_fail_state("[BANLY] Nie mozna otworzyc nvault");
    nvault_prune(g_hVault, 0, get_systime() - CACHE_TTL);

    bind_pcvar_string(create_cvar("banly_api_key", "", FCVAR_PROTECTED, "Klucz API Banly.pl"), g_szApiKey, charsmax(g_szApiKey));
    AutoExecConfig(true, "banly");
}

public OnConfigsExecuted(){
    if(!g_szApiKey[0]) set_fail_state("[BANLY] Brak klucza API - ustaw banly_api_key w configs/plugins/banly.cfg");
}

public plugin_end() nvault_close(g_hVault);

public client_putinserver(id){
    g_aPlayer[id][PS_USERID] = get_user_userid(id);
    g_aPlayer[id][PS_REQUEST] = 0;
    g_aPlayer[id][PS_RETRIED] = 0;

    if(!g_szApiKey[0] || !g_aPlayer[id][PS_USERID] || is_user_bot(id) || is_user_hltv(id) || (has_reunion() && !is_user_steam(id))) return;

    new data[1];
    data[0] = id;
    new Float:fDelay = random_float(1.0, 7.0);
    set_task(fDelay, "TaskCheck", g_aPlayer[id][PS_USERID], data, sizeof data);
}

public client_disconnected(id){
    new userid = g_aPlayer[id][PS_USERID];
    new EzHttpRequest:req = EzHttpRequest:g_aPlayer[id][PS_REQUEST];

    if(userid) remove_task(userid);
    if(req && ezhttp_is_request_exists(req)) ezhttp_cancel_request(req);
    g_aPlayer[id][PS_REQUEST] = 0;
    g_aPlayer[id][PS_USERID] = 0;
    g_aPlayer[id][PS_RETRIED] = 0;
}

public TaskCheck(data[], userid){
    new id = data[0];
    if(!is_user_connected(id) || g_aPlayer[id][PS_USERID] != userid || get_user_userid(id) != userid) return;
    new szAuth[MAX_AUTHID_LENGTH], szVal[8], iTime;
    get_user_authid(id, szAuth, charsmax(szAuth));
    if(!szAuth[0]) return;
    new bFound = nvault_lookup(g_hVault, szAuth, szVal, charsmax(szVal), iTime);

    if(bFound && get_systime() - iTime < CACHE_TTL){
        Notify(id, str_to_num(szVal));
        return;
    }
    SendRequest(id, userid, szAuth);
}

SendRequest(id, userid, const szAuth[]){
    new EzHttpOptions:opt = ezhttp_create_options();
    ezhttp_option_set_header(opt, "X-Banly-Plugin-Key", g_szApiKey);
    ezhttp_option_set_timeout(opt, 10000);
    ezhttp_option_add_url_parameter(opt, "q", szAuth);
    new data[ReqData];
    data[RD_ID] = id;
    data[RD_USERID] = userid;
    copy(data[RD_AUTH], MAX_AUTHID_LENGTH - 1, szAuth);
    ezhttp_option_set_user_data(opt, data, sizeof data);
    g_aPlayer[id][PS_REQUEST] = _:ezhttp_get("https://banly.pl/api/v2/bans", "OnBanCheckComplete", opt);
}

public OnBanCheckComplete(EzHttpRequest:req){
    new data[ReqData];
    ezhttp_get_user_data(req, data);
    new id = data[RD_ID], userid = data[RD_USERID];

    if(!is_user_connected(id) || get_user_userid(id) != userid) return;
    if(g_aPlayer[id][PS_REQUEST] == _:req) g_aPlayer[id][PS_REQUEST] = 0;

    new code = ezhttp_get_http_code(req);
    new EzHttpErrorCode:err = ezhttp_get_error_code(req);
    if(err == EZH_REQUEST_CANCELLED) return;
    if(err != EZH_OK){
        if(err == EZH_OPERATION_TIMEDOUT && !g_aPlayer[id][PS_RETRIED]){
            g_aPlayer[id][PS_RETRIED] = 1;
            new retry_data[1];
            retry_data[0] = id;
            set_task(2.0, "TaskCheck", userid, retry_data, sizeof retry_data);
            return;
        }
        new szErr[128];
        ezhttp_get_error_message(req, szErr, charsmax(szErr));
        log_amx("[BANLY] Blad zapytania (%s): %s", data[RD_AUTH], szErr);
        return;
    }

    if(code == 401){
        set_fail_state("[BANLY] Niepoprawny klucz API! Wejdz na www.banly.pl!");
        return;
    }

    if(code != 200){
        log_amx("[BANLY] Blad API (%s): HTTP %d", data[RD_AUTH], code);
        return;
    }

    new EzJSON:json = ezhttp_parse_json_response(req);
    if(json == EzInvalid_JSON){
        log_amx("[BANLY] Niepoprawny JSON (%s)", data[RD_AUTH]);
        return;
    }
    if(!ezjson_is_object(json)){
        log_amx("[BANLY] Nieoczekiwany format odpowiedzi (%s)", data[RD_AUTH]);
        ezjson_free(json);
        return;
    }

    new total = CountActiveBans(json);
    ezjson_free(json);

    if(total < 0){
        log_amx("[BANLY] Nieoczekiwany format odpowiedzi (%s)", data[RD_AUTH]);
        return;
    }

    new szVal[8];
    num_to_str(total, szVal, charsmax(szVal));
    nvault_set(g_hVault, data[RD_AUTH], szVal);
    Notify(id, total);
}

GetBanForm(n){
    if(n == 1) return 0;
    new m10 = n % 10, m100 = n % 100;
    return (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) ? 1 : 2;
}

CountActiveBans(EzJSON:json){
    new EzJSON:nets = ezjson_object_get_value(json, "networks");
    if(nets == EzInvalid_JSON) return -1;
    if(!ezjson_is_array(nets)){
        ezjson_free(nets);
        return -1;
    }

    new total, size = ezjson_array_get_count(nets);
    for(new i = 0; i < size; i++){
        new EzJSON:item = ezjson_array_get_value(nets, i);
        if(item == EzInvalid_JSON) continue;
        if(ezjson_is_object(item) && ezjson_object_has_value(item, "activeBanCount", EzJSONNumber)){
            new cnt = ezjson_object_get_number(item, "activeBanCount");
            total += cnt;
        }
        ezjson_free(item);
    }

    ezjson_free(nets);
    return total;
}

Notify(id, total){
    static BAN_FORMS[][] = { "ban", "bany", "banow" };
    if(total > 0){
        CC_SendAdminMessage("d", true, "Gracz &x04%n &x01ma &x04%d &x01%s na sieciach cs!", id, total, BAN_FORMS[GetBanForm(total)]);
        server_print("[BANLY] Gracz %n ma %d %s na sieciach cs!", id, total, BAN_FORMS[GetBanForm(total)]);
    }
    else{
        CC_SendAdminMessage("d", true, "Gracz &x04%n &x01nie posiada banow na zadnej sieci!", id);
        server_print("[BANLY] Gracz %n nie posiada banow na zadnej sieci!", id);
    }
}
