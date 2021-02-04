#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define DATABASE_CONFIG_NAME "FaceitRank"
#define PREFIKS "[ \x02RANK\x01 ]"

#define MAX_LEVEL 10

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name = "Faceit Elo Rank",
	author = "-_- (Karol Skupień)",
	description = "Rank",
	version = "2.0",
	url = "https://github.com/Qesik/"
};

int gPointsForLevel[ MAX_LEVEL + 1 ] = {
	0, 1, 801, 951, 1101, 1251, 
	1401, 1551, 1701, 1851, 2001
};

Database DBK;

ConVar g_cPointsForKill;
ConVar g_cPointsForDeath;

enum struct ClientInfo {
	bool LoadData;
	int EloPoints;
	int FaceitLevel;

	void ResetVars()
	{
		this.LoadData = false;
		this.EloPoints = g_cPointsForKill.IntValue;
		this.FaceitLevel = 3;
	}
}
ClientInfo gClientInfo[MAXPLAYERS];

public void OnPluginStart(/*void*/) {
	LoadTranslations("t_elorank.phrases");

	RegConsoleCmd("sm_elo", cmd_EloRank, "Menu Faceit Elo");
	RegConsoleCmd("sm_toplvl", cmd_ToLVL, "Menu TOP LVL Faceit Elo");
	RegAdminCmd("sm_eloadmin", cmd_EloAdmin, ADMFLAG_ROOT);

	HookEvent("player_death", ev_PlayerDeath);

	g_cPointsForKill = CreateConVar("elo_points_for_kill", "2", "Ilość punktów za zabicie");
	g_cPointsForDeath = CreateConVar("elo_points_for_death", "1", "Ilość punktów za śmierć");
	AutoExecConfig(true, "FaceitRank");

	if ( DBK == null && SQL_AreStatsEnabled() ) {
		SQL_ConnectDB();
	}
}
public void OnMapStart(/*void*/) {
	char sBuffer[PLATFORM_MAX_PATH];
	for(int i = 1; i <= 10; i++)
	{
		FormatEx(sBuffer, sizeof(sBuffer), "materials/panorama/images/icons/xp/level%i.png", 5000 + i);
		AddFileToDownloadsTable(sBuffer);
	}

	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, sdk_ThinkPost);
}
public void OnMapEnd() {
	SDKUnhook(GetPlayerResourceEntity(), SDKHook_ThinkPost, sdk_ThinkPost);
}

public void OnClientAuthorized(int iClient, const char[] sAuth) {
	gClientInfo[iClient].ResetVars();
	if ( !StrEqual(sAuth, "BOT") ) {
		SQL_LoadDataClient(iClient);
	}
}
public void OnClientDisconnect(int iClient) {
	SQL_SaveClientData(iClient);
	gClientInfo[iClient].ResetVars();
}
/*
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
*/
bool SQL_AreStatsEnabled(/*void*/) {
	return SQL_CheckConfig(DATABASE_CONFIG_NAME);
}
void SQL_ConnectDB(/*void*/) {
	char sError[255];
	DBK = SQL_Connect(DATABASE_CONFIG_NAME, true, sError, sizeof(sError));
	if ( DBK == null ) {
		LogError("[CONNECT] Error: %s", sError);
		SetFailState("Problem with connect - Stop...");
	}

	if ( !SQL_FastQuery(DBK, "CREATE TABLE IF NOT EXISTS `Players` \
	( \
		`AuthID` INTEGER NOT NULL PRIMARY KEY, \
		`SteamID` VARCHAR(32) UNIQUE, \
		`Nick` VARCHAR(64), \
		`Level` INTEGER NOT NULL, \
		`EloPoints` INTEGER NOT NULL \
	)") ) {
		SQL_GetError(DBK, sError, sizeof(sError));
		LogMessage("[CREATE TABLE] Error: %s", sError);
		SetFailState("Problem with create - Stop....");
	}
}

public void SQL_LoadDataClient(int iClient) {
	if ( DBK == null || !IsConnected(iClient) || gClientInfo[iClient].LoadData )
		return;

	int iAuthid = GetSteamAccountID(iClient);
	if ( !iAuthid )
		return;

	char sQuery[128];
	FormatEx(sQuery, sizeof(sQuery), "SELECT `Level`, `EloPoints` FROM `Players` WHERE `AuthID`='%d';", iAuthid);
	DBK.Query(SQL_LoadDataClientH, sQuery, GetClientUserId(iClient));
}
public void SQL_LoadDataClientH(Database db, DBResultSet dbResults, const char[] sError, const int iClientID) {
	int iClient = GetClientOfUserId(iClientID);
	if ( !IsConnected(iClient) || gClientInfo[iClient].LoadData ) {
		return;
	}
	gClientInfo[iClient].LoadData = false;

	if ( dbResults == null ) {
		LogError("[LOAD] Error: %s", sError);
		return;
	}

	if ( dbResults.FetchRow() ) {
		gClientInfo[iClient].FaceitLevel = dbResults.FetchInt(0);
		gClientInfo[iClient].EloPoints = dbResults.FetchInt(1);

		gClientInfo[iClient].LoadData = true;
	} else {
		SQL_CreateClientData(iClient);
	}
}

public void SQL_CreateClientData(int iClient) {
	int iAuthid = GetSteamAccountID(iClient);
	if ( !iAuthid ) {
		return;
	}

	char sName[32];
	if ( !GetClientName(iClient, sName, sizeof(sName)) ) {
		LogError("[LOAD] Failed to get name for %L", iClient);
		return;
	}

	char sSanitized_name[sizeof(sName) * 2 + 1];
	if ( !SQL_EscapeString(DBK, sName, sSanitized_name, sizeof(sSanitized_name)) ) {
		LogError("[LOAD] Failed to get sanitized name for %L", iClient);
		return;
	}

	char sSteamID[32];
	if ( !GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID)) ) {
		LogError("[LOAD] Failed to get steam id for %L", iClient);
		return;
	}

	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `Players` (`AuthID`, `SteamID`, `Nick`, `Level`, `EloPoints`) VALUES ('%d', '%s', '%s', '3', '1000');", iAuthid, sSteamID, sSanitized_name);
	if ( !SQL_FastQuery(DBK, sQuery) ) {
		char sError[255];
		SQL_GetError(DBK, sError, 512);
		LogError("[CREATE] `Players` Error: %s", sError);
	} else gClientInfo[iClient].LoadData = true;
}

public void SQL_SaveClientData(int iClient) {
	if ( DBK == null || !gClientInfo[iClient].LoadData ) {
		return;
	}

	int iAuthid = GetSteamAccountID(iClient);
	if ( !iAuthid ) {
		return;
	}

	char sName[32];
	if ( !GetClientName(iClient, sName, sizeof(sName)) ) {
		LogError("[LOAD] Failed to get name for %L", iClient);
		return;
	}

	char sSanitized_name[sizeof(sName) * 2 + 1];
	if ( !SQL_EscapeString(DBK, sName, sSanitized_name, sizeof(sSanitized_name)) ) {
		LogError("[LOAD] Failed to get sanitized name for %L", iClient);
		return;
	}

	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "UPDATE `Players` SET `Nick`='%s', `Level`='%d', `EloPoints`='%d' WHERE `AuthID`='%d';",
	sSanitized_name, gClientInfo[iClient].FaceitLevel, gClientInfo[iClient].EloPoints, iAuthid);
	if ( !SQL_FastQuery(DBK, sQuery) ) {
		char sError[255];
		SQL_GetError(DBK, sError, sizeof(sError));
		LogError("[SAVE] Error: %s", sError);
	}
}
/*
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
*/
public Action ev_PlayerDeath(Event eEvent, const char[] sName, bool bDontBroadcast) {
	int iVictim = GetClientOfUserId(eEvent.GetInt("userid"));
	int iKiller = GetClientOfUserId(eEvent.GetInt("attacker"));

	if ( !IsValidClient(iKiller) || !IsValidClient(iVictim) || GetClientTeam(iVictim) == GetClientTeam(iKiller) || GameRules_GetProp("m_bWarmupPeriod") == 1 ) {
		return Plugin_Continue;
	}

	gClientInfo[iKiller].EloPoints += g_cPointsForKill.IntValue;
	gClientInfo[iVictim].EloPoints -= g_cPointsForDeath.IntValue;

	if ( gClientInfo[iVictim].EloPoints < 0 ) {
		gClientInfo[iVictim].EloPoints = 0;
	}
	
	TranslationPrintToChat(iKiller, "c_killer", gClientInfo[iKiller].EloPoints, g_cPointsForKill.IntValue);
	TranslationPrintToChat(iVictim, "c_victim", gClientInfo[iVictim].EloPoints, g_cPointsForDeath.IntValue);

	UpdateLevel(iKiller);
	UpdateLevel(iVictim);
	return Plugin_Continue;
}

public void UpdateLevel(int iClient) {
	bool bLevelUp = false;
	while(gClientInfo[iClient].FaceitLevel < MAX_LEVEL && gClientInfo[iClient].EloPoints >= gPointsForLevel[gClientInfo[iClient].FaceitLevel + 1])
	{
		gClientInfo[iClient].FaceitLevel ++;
		TranslationPrintToChat(iClient, "c_info_rank", gClientInfo[iClient].FaceitLevel);
		TranslationPrintToChat(iClient, "c_info_elo", gClientInfo[iClient].EloPoints);
		bLevelUp = true;
	}
	while(!bLevelUp && gClientInfo[iClient].FaceitLevel > 0 && gClientInfo[iClient].EloPoints < gPointsForLevel[gClientInfo[iClient].FaceitLevel])
	{
		gClientInfo[iClient].FaceitLevel --;
		TranslationPrintToChat(iClient, "c_info_rank", gClientInfo[iClient].FaceitLevel);
		TranslationPrintToChat(iClient, "c_info_elo", gClientInfo[iClient].EloPoints);
	}
}

public Action sdk_ThinkPost(int iEnt)
{
	for (int pID = 1; pID <= MaxClients; pID++)
	{
		if ( gClientInfo[pID].FaceitLevel ) {
			SetEntData(iEnt, (FindSendPropInfo("CCSPlayerResource", "m_nPersonaDataPublicLevel") + (pID * 4)), gClientInfo[pID].FaceitLevel + 5000);
		}
	}
}

public void OnPlayerRunCmdPost(int iClient, int iButtons) {
	static int iOldButtons[MAXPLAYERS+1];

	if ( iButtons & IN_SCORE && !(iOldButtons[iClient] & IN_SCORE) ) {
		StartMessageOne("ServerRankRevealAll", iClient, USERMSG_BLOCKHOOKS);
		EndMessage();
	}

	iOldButtons[iClient] = iButtons;
}
/*
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
*/
public Action cmd_EloRank(int iClient, int iArgs) {
	if ( !IsValidClient(iClient) )
		return Plugin_Continue;

	TranslationPrintToChat(iClient, "c_info_rank", gClientInfo[iClient].FaceitLevel);
	TranslationPrintToChat(iClient, "c_info_elo", gClientInfo[iClient].EloPoints);
	if ( gClientInfo[iClient].FaceitLevel < MAX_LEVEL )
		TranslationPrintToChat(iClient, "c_cmd_info_rank", gClientInfo[iClient].FaceitLevel + 1, gPointsForLevel[gClientInfo[iClient].FaceitLevel + 1]);
	return Plugin_Continue;
}

public Action cmd_EloAdmin(int iClient, int iArgs) {
	Menu mMenu = new Menu(EloAdminH);
	mMenu.SetTitle("CSC :: Reset Elo\nWybierz gracza\n");

	char sName[64], sID[16];
	for(int i = 1; i <= MaxClients; i++)
	{
		if ( !IsClientInGame(i) )
			continue;

		IntToString(GetClientUserId(i), sID, sizeof(sID));
		GetClientName(i, sName, sizeof(sName));
		mMenu.AddItem(sID, sName);
	}
	mMenu.Display(iClient, 30);
}
public int EloAdminH(Menu mMenu, MenuAction mAction, int iClient, int iParam) {
	if ( mAction == MenuAction_End ) {
		delete mMenu;
	} else if ( mAction == MenuAction_Select ) {
		char sInfo[16];
		mMenu.GetItem(iParam, sInfo, sizeof(sInfo));
		int iUserID = GetClientOfUserId(StringToInt(sInfo));

		if ( !IsValidClient(iUserID) )
			return 0;

		gClientInfo[iUserID].FaceitLevel = 3;
		gClientInfo[iUserID].EloPoints = 1000;
		PrintToChat(iClient, "Zresetowałeś Elo graczowi %N", iUserID);
	}
	return 0;
}

public Action cmd_ToLVL(int iClient, int iArgs) {
	if ( !IsValidClient(iClient) )
		return Plugin_Continue;

	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT `Nick`, `Level`, `EloPoints` FROM `Players` ORDER BY `EloPoints` DESC LIMIT 15");
	DBK.Query(MenuTopLVL, sQuery, GetClientUserId(iClient));

	return Plugin_Continue;
}
public void MenuTopLVL(Database db, DBResultSet dbResults, const char[] sError, int iClientID) {
	if ( db == null || dbResults == null ) {
		LogError("[TOP LVL] Error: %s", sError);
		return;
	}

	int iClient = GetClientOfUserId(iClientID);
	if ( !iClient )
		return;

	char sMenu[128], sName[64];
	Menu mMenu = new Menu(MenuTopLVLH);
	
	mMenu.SetTitle("TOP 15 Faceit LVL:");

	while( dbResults.FetchRow() )
	{
		dbResults.FetchString(0, sName, sizeof(sName));

		FormatEx(sMenu, sizeof(sMenu), "%s Level %d Punkty %d", sName, dbResults.FetchInt(1), dbResults.FetchInt(2));
		mMenu.AddItem("", sMenu, ITEMDRAW_DISABLED);
	}

	mMenu.Display(iClient, 40);
}
public int MenuTopLVLH(Menu mMenu, MenuAction mAction, int iClient, int iParam) {
	if ( mAction == MenuAction_End ) {
		delete mMenu;
	}
	return 0;
}
/*
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
	* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
*/
bool IsValidClient(int iClient) {
	return iClient > 0 && iClient <= MaxClients && IsClientConnected(iClient) && IsClientInGame(iClient)/* && !IsFakeClient(iClient)*/;
}
bool IsConnected(int iClient) {
	return iClient > 0 && iClient <= MaxClients && IsClientConnected(iClient) && !IsFakeClient(iClient);
}

void TranslationFormatColor(char[] sText, const int iMaxlen) {
	ReplaceString(sText, iMaxlen, "@default", "\x01");
	ReplaceString(sText, iMaxlen, "@red", "\x02");
	ReplaceString(sText, iMaxlen, "@lgreen", "\x03");
	ReplaceString(sText, iMaxlen, "@green", "\x04");
	ReplaceString(sText, iMaxlen, "@lime", "\x06");
	ReplaceString(sText, iMaxlen, "@grey", "\x0A");
	ReplaceString(sText, iMaxlen, "@darkblue", "\x0C");
	ReplaceString(sText, iMaxlen, "@orange", "\x10");
	ReplaceString(sText, iMaxlen, "@orchid", "\x0E");
	ReplaceString(sText, iMaxlen, "@grey2", "\x0D");
	ReplaceString(sText, iMaxlen, "@ct", "\x0B");
	ReplaceString(sText, iMaxlen, "@tt", "\x09");
}

void TranslationPrintToChat(int iClient, any ...) {
	if ( !IsFakeClient(iClient) ) {
		SetGlobalTransTarget(iClient);

		static char sTranslation[192];
		VFormat(sTranslation, sizeof(sTranslation), "%t", 2);

		TranslationFormatColor(sTranslation, 192);

		PrintToChat(iClient, " %s \x01%s", PREFIKS, sTranslation);
	}
}