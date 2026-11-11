#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <cromchat>
#include <easy_http>
#include <nvault>

#pragma semicolon 1

#define VERSION_MAJOR 0
#define VERSION_MINOR 3
#define CACHE_TTL 2700
#define UPDATE_KEY "_update"

enum _:ReqData { RD_ID, RD_USERID, RD_ADMIN, RD_ADMIN_USERID, RD_AUTH[MAX_AUTHID_LENGTH] };
new g_szApiKey[64], g_iNotifyClean, g_hVault = INVALID_HANDLE, g_iUserid[MAX_PLAYERS + 1], EzHttpRequest:g_hRequest[MAX_PLAYERS + 1], bool:g_bRetried[MAX_PLAYERS + 1], Float:g_fNextCheck[MAX_PLAYERS + 1], g_iMenuNoData;

public plugin_init(){
    new szVersion[16];
    formatex(szVersion, charsmax(szVersion), "v%d.%d", VERSION_MAJOR, VERSION_MINOR);
    register_plugin("Banly.pl", szVersion, "Boziak.", "https://banly.pl");
    CC_SetPrefix("&x04[BANLY.PL]");

    g_hVault = nvault_open("banly_cache");
    if(g_hVault == INVALID_HANDLE) set_fail_state("[BANLY] Nie mozna otworzyc nvault");
    nvault_prune(g_hVault, 0, get_systime() - CACHE_TTL);

    bind_pcvar_string(create_cvar("banly_api_key", "", FCVAR_PROTECTED, "Klucz API Banly.pl"), g_szApiKey, charsmax(g_szApiKey));
    bind_pcvar_num(create_cvar("banly_notify_clean", "1", FCVAR_NONE, "Informuj adminow takze o graczach bez banow (0 - nie, 1 - tak)", true, 0.0, true, 1.0), g_iNotifyClean);
    AutoExecConfig(true, "banly");

    register_concmd("amx_banly", "CmdBanly", ADMIN_BAN, "<nick | #userid | STEAM_ID> - wyswietla raport z banly.pl");
    register_clcmd("say /banly", "CmdMenu");
    register_clcmd("say_team /banly", "CmdMenu");
    g_iMenuNoData = menu_makecallback("MenuNoData");
}

public OnConfigsExecuted(){
    if(!g_szApiKey[0]) set_fail_state("[BANLY] Brak klucza API - ustaw banly_api_key w configs/plugins/banly.cfg");
    CheckUpdate();
}
public plugin_end() nvault_close(g_hVault);

public client_putinserver(id){
    g_iUserid[id] = get_user_userid(id);
    g_hRequest[id] = EzHttpRequest:0;
    g_bRetried[id] = false;
    g_fNextCheck[id] = 0.0;

    if(!g_szApiKey[0] || !g_iUserid[id] || is_user_bot(id) || is_user_hltv(id) || (has_reunion() && !is_user_steam(id))) return;

    new data[1];
    data[0] = id;
    new Float:fDelay = random_float(1.0, 7.0);
    set_task(fDelay, "TaskCheck", g_iUserid[id], data, sizeof data);
}

public client_disconnected(id){
    new userid = g_iUserid[id];
    new EzHttpRequest:req = g_hRequest[id];

    if(userid) remove_task(userid);
    if(req && ezhttp_is_request_exists(req)) ezhttp_cancel_request(req);
    g_hRequest[id] = EzHttpRequest:0;
    g_iUserid[id] = 0;
    g_bRetried[id] = false;
}

public TaskCheck(data[], userid){
    new id = data[0];
    if(!is_user_connected(id) || g_iUserid[id] != userid || get_user_userid(id) != userid) return;
    new szAuth[MAX_AUTHID_LENGTH], szVal[160];
    get_user_authid(id, szAuth, charsmax(szAuth));
    if(!szAuth[0]) return;

    if(GetCache(szAuth, szVal, charsmax(szVal))){
        Notify(id, str_to_num(szVal));
        return;
    }
    g_hRequest[id] = SendRequest(id, userid, szAuth);
}

EzHttpRequest:SendRequest(id, userid, const szAuth[], admin = 0){
    new EzHttpOptions:opt = ezhttp_create_options();
    ezhttp_option_set_header(opt, "X-Banly-Plugin-Key", g_szApiKey);
    ezhttp_option_set_timeout(opt, 10000);
    ezhttp_option_add_url_parameter(opt, "q", szAuth);
    new data[ReqData];
    data[RD_ID] = id;
    data[RD_USERID] = userid;
    data[RD_ADMIN] = admin;
    data[RD_ADMIN_USERID] = admin ? get_user_userid(admin) : 0;
    copy(data[RD_AUTH], MAX_AUTHID_LENGTH - 1, szAuth);
    ezhttp_option_set_user_data(opt, data, sizeof data);
    return ezhttp_get("https://banly.pl/api/v2/bans", "OnBanCheckComplete", opt);
}

public OnBanCheckComplete(EzHttpRequest:req){
    new data[ReqData];
    ezhttp_get_user_data(req, data);
    new id = data[RD_ID], userid = data[RD_USERID], admin = data[RD_ADMIN];

    if(id && (!is_user_connected(id) || get_user_userid(id) != userid)) id = 0;
    if(admin && (!is_user_connected(admin) || get_user_userid(admin) != data[RD_ADMIN_USERID])) admin = 0;
    if(id && g_hRequest[id] == req) g_hRequest[id] = EzHttpRequest:0;
    if(!id && !admin) return;

    new EzHttpErrorCode:err = ezhttp_get_error_code(req);
    if(err == EZH_REQUEST_CANCELLED) return;
    if(err == EZH_OPERATION_TIMEDOUT && id && !admin && !g_bRetried[id]){
        g_bRetried[id] = true;
        new retry_data[1];
        retry_data[0] = id;
        set_task(2.0, "TaskCheck", userid, retry_data, sizeof retry_data);
        return;
    }

    new total, szUrl[128];
    if(!ReadResponse(req, data[RD_AUTH], total, szUrl, charsmax(szUrl))){
        if(!admin) return;
        if(err == EZH_OPERATION_TIMEDOUT) console_print(admin, "[BANLY] Banly.pl nie odpowiada, sprobuj za chwile.");
        else console_print(admin, "[BANLY] Nie udalo sie pobrac danych %s.", data[RD_AUTH]);
        return;
    }

    new szVal[160];
    formatex(szVal, charsmax(szVal), "%d %s", total, szUrl);
    nvault_set(g_hVault, data[RD_AUTH], szVal);

    if(id) Notify(id, total);
    if(admin) ShowMotdUrl(admin, szUrl, data[RD_AUTH]);
}

ReadResponse(EzHttpRequest:req, const szAuth[], &total, szUrl[], len){
    if(ezhttp_get_error_code(req) != EZH_OK){
        new szErr[128];
        ezhttp_get_error_message(req, szErr, charsmax(szErr));
        log_amx("[BANLY] Blad zapytania (%s): %s", szAuth, szErr);
        return false;
    }

    new code = ezhttp_get_http_code(req);
    if(code == 401) set_fail_state("[BANLY] Niepoprawny klucz API! Wejdz na www.banly.pl!");
    if(code != 200){
        log_amx("[BANLY] Blad API (%s): HTTP %d", szAuth, code);
        return false;
    }

    new EzJSON:json = ezhttp_parse_json_response(req);
    if(json == EzInvalid_JSON){
        log_amx("[BANLY] Niepoprawny JSON (%s)", szAuth);
        return false;
    }

    total = ezjson_is_object(json) ? CountActiveBans(json) : -1;
    if(total >= 0) ezjson_object_get_string(json, "detailsUrl", szUrl, len);
    ezjson_free(json);

    if(total < 0 || !IsSafeBanlyUrl(szUrl)){
        log_amx("[BANLY] Nieoczekiwany format odpowiedzi (%s)", szAuth);
        return false;
    }
    return true;
}

stock IsSafeBanlyUrl(const szUrl[]) return equal(szUrl, "https://banly.pl/", 17) && contain(szUrl, "^"") == -1 && contain(szUrl, " ") == -1;

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
    static const BAN_FORMS[][] = { "ban", "bany", "banow" };
    if(total > 0){
        new idx = GetBanForm(total);
        CC_SendAdminMessage("d", true, "Gracz &x04%n &x01ma &x04%d &x01%s na sieciach cs!", id, total, BAN_FORMS[idx]);
        server_print("[BANLY] Gracz %n ma %d %s na sieciach cs!", id, total, BAN_FORMS[idx]);
    }
    else if(g_iNotifyClean){
        CC_SendAdminMessage("d", true, "Gracz &x04%n &x01nie posiada banow na zadnej sieci!", id);
        server_print("[BANLY] Gracz %n nie posiada banow na zadnej sieci!", id);
    }
}

GetBanForm(n){
    if(n == 1) return 0;
    new m10 = n % 10, m100 = n % 100;
    return (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) ? 1 : 2;
}

public CmdBanly(id, level, cid){
    if(!id || !cmd_access(id, level, cid, 2)) return PLUGIN_HANDLED;
    new szArg[MAX_AUTHID_LENGTH];
    read_argv(1, szArg, charsmax(szArg));

    new target = 0;
    if(equali(szArg, "STEAM_", 6)){
        strtoupper(szArg);
        target = find_player_ex(FindPlayer_MatchAuthId | FindPlayer_ExcludeBots, szArg);
    }
    else{
        target = cmd_target(id, szArg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
        if(!target) return PLUGIN_HANDLED;
        if(is_user_hltv(target)){
            console_print(id, "[BANLY] Nie mozna sprawdzic HLTV.");
            return PLUGIN_HANDLED;
        }
        get_user_authid(target, szArg, charsmax(szArg));
    }

    if(target && has_reunion() && !is_user_steam(target)){
        console_print(id, "[BANLY] Gracz %n nie korzysta ze Steam.", target);
        return PLUGIN_HANDLED;
    }

    new szVal[160];
    if(GetCache(szArg, szVal, charsmax(szVal))){
        new pos = contain(szVal, " ");
        if(pos != -1){
            ShowMotdUrl(id, szVal[pos + 1], szArg);
            return PLUGIN_HANDLED;
        }
    }

    new Float:fNow = get_gametime();
    if(fNow < g_fNextCheck[id]){
        console_print(id, "[BANLY] Poczekaj %d s przed kolejnym sprawdzeniem.", floatround(g_fNextCheck[id] - fNow, floatround_ceil));
        return PLUGIN_HANDLED;
    }
    g_fNextCheck[id] = fNow + 5.0;

    new userid = target ? get_user_userid(target) : 0;
    console_print(id, "[BANLY] Pobieram dane %s...", szArg);
    SendRequest(target, userid, szArg, id);
    return PLUGIN_HANDLED;
}

public CmdMenu(id){
    if(!(get_user_flags(id) & ADMIN_BAN)) return PLUGIN_CONTINUE;

    new players[MAX_PLAYERS], num;
    get_players_ex(players, num, GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV);

    new menu = menu_create("\rBanly.pl \w- raport gracza", "MenuHandler");
    new szAuth[MAX_AUTHID_LENGTH], szVal[160], szItem[64], szInfo[12];

    for(new i = 0; i < num; i++){
        new player = players[i];
        if(has_reunion() && !is_user_steam(player)) continue;

        num_to_str(get_user_userid(player), szInfo, charsmax(szInfo));
        get_user_authid(player, szAuth, charsmax(szAuth));

        if(GetCache(szAuth, szVal, charsmax(szVal)) && contain(szVal, " ") != -1){
            new total = str_to_num(szVal);
            formatex(szItem, charsmax(szItem), "%n %s[%d]", player, total ? "\r" : "\y", total);
            menu_additem(menu, szItem, szInfo);
        }
        else{
            formatex(szItem, charsmax(szItem), "%n [brak danych]", player);
            menu_additem(menu, szItem, szInfo, 0, g_iMenuNoData);
        }
    }

    if(!menu_items(menu)){
        menu_destroy(menu);
        CC_SendMessage(id, "Brak graczy Steam na serwerze.");
        return PLUGIN_HANDLED;
    }

    menu_setprop(menu, MPROP_BACKNAME, "Wstecz");
    menu_setprop(menu, MPROP_NEXTNAME, "Dalej");
    menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
    menu_display(id, menu);
    return PLUGIN_HANDLED;
}

public MenuNoData(id, menu, item) return ITEM_DISABLED;

public MenuHandler(id, menu, item){
    if(item < 0){
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szInfo[12];
    menu_item_getinfo(menu, item, _, szInfo, charsmax(szInfo));
    menu_destroy(menu);

    new target = find_player_ex(FindPlayer_MatchUserId, str_to_num(szInfo));
    if(!target){
        CC_SendMessage(id, "Gracz opuscil serwer.");
        return PLUGIN_HANDLED;
    }

    new szAuth[MAX_AUTHID_LENGTH], szVal[160], pos;
    get_user_authid(target, szAuth, charsmax(szAuth));
    if(!GetCache(szAuth, szVal, charsmax(szVal)) || (pos = contain(szVal, " ")) == -1){
        CC_SendMessage(id, "Brak raportu w pamieci, uzyj amx_banly");
        return PLUGIN_HANDLED;
    }

    new szName[MAX_NAME_LENGTH];
    get_user_name(target, szName, charsmax(szName));
    ShowMotdUrl(id, szVal[pos + 1], szName);
    return PLUGIN_HANDLED;
}

GetCache(const szAuth[], szVal[], len){
    new iTime;
    return nvault_lookup(g_hVault, szAuth, szVal, len, iTime) && get_systime() - iTime < CACHE_TTL;
}

ShowMotdUrl(id, const szUrl[], const szWho[]){
    new szRefresh[256], szTitle[64];
    formatex(szRefresh, charsmax(szRefresh), "<meta http-equiv=refresh content=^"0;url=%s^">", szUrl);
    formatex(szTitle, charsmax(szTitle), "Banly.pl - %s", szWho);
    show_motd(id, szRefresh, szTitle);
}

CheckUpdate(){
    new szVal[64], szTime[16], szTag[32], iTime;
    if(nvault_lookup(g_hVault, UPDATE_KEY, szVal, charsmax(szVal), iTime)){
        parse(szVal, szTime, charsmax(szTime), szTag, charsmax(szTag));
        if(IsNewer(szTag) || get_systime() - str_to_num(szTime) < 21600){
            NotifyIfNewer(szTag);
            return;
        }
    }

    new EzHttpOptions:opt = ezhttp_create_options();
    ezhttp_option_set_header(opt, "User-Agent", "BanlyAPI-AMXX");
    ezhttp_option_set_header(opt, "Accept", "application/vnd.github+json");
    ezhttp_option_set_timeout(opt, 10000);
    ezhttp_get("https://api.github.com/repos/Banlypl/BanlyAPI-AMXX/releases/latest", "OnUpdateCheck", opt);
}

public OnUpdateCheck(EzHttpRequest:req){
    if(ezhttp_get_error_code(req) != EZH_OK) return;

    new code = ezhttp_get_http_code(req), szTag[32];
    if(code == 200){
        new EzJSON:json = ezhttp_parse_json_response(req);
        if(json == EzInvalid_JSON) return;
        if(ezjson_is_object(json)) ezjson_object_get_string(json, "tag_name", szTag, charsmax(szTag));
        ezjson_free(json);
    }
    else if(code != 404) return;

    new szVal[64];
    formatex(szVal, charsmax(szVal), "%d %s", get_systime(), szTag);
    nvault_pset(g_hVault, UPDATE_KEY, szVal);

    NotifyIfNewer(szTag);
}

NotifyIfNewer(const szTag[]){
    if(!IsNewer(szTag)) return;
    log_amx("[BANLY] Dostepna jest nowsza wersja pluginu: %s", szTag);
    set_task(60.0, "TaskUpdateMsg");
}

public TaskUpdateMsg() CC_SendAdminMessage("a", true, "Dostepna jest nowsza wersja pluginu!");

IsNewer(const szTag[]){
    new szMajor[8], szMinor[8];
    strtok2(szTag[szTag[0] == 'v' ? 1 : 0], szMajor, charsmax(szMajor), szMinor, charsmax(szMinor), '.');
    return str_to_num(szMajor) * 1000 + str_to_num(szMinor) > VERSION_MAJOR * 1000 + VERSION_MINOR;
}
