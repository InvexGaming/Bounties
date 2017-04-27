#include <sourcemod>
#include <cstrike>
#include <store>
#include <csgocolors>

//Defines
#define VERSION "1.03"
#define CHAT_TAG_PREFIX "[{RED}BOUNTIES{NORMAL}] "
#define PLAYER_SERVER 0
#define CS_TEAM_UNASSIGNED 0

//Cvars
ConVar cvar_max_bounty_amount = null;
ConVar cvar_min_players = null;

//Variables
bool isEnabled = false;

int playerKillStreak[MAXPLAYERS+1] = 0;
ArrayList playerSetBountyTarget[MAXPLAYERS+1];  //list of players who set a bounty on client
ArrayList playerSetBountyAmount[MAXPLAYERS+1];  //ammount a player has put on another player

char g_LogPath[256]; //log filename path

public Plugin myinfo =
{
  name = "Bounties",
  author = "Invex | Byte",
  description = "Sets bounties on players once they gain killstreaks. Allows players to set bounties on other players.",
  version = VERSION,
  url = "http://www.invexgaming.com.au"
};

// Plugin Start
public void OnPluginStart()
{
  //Translations
  LoadTranslations("common.phrases");
  LoadTranslations("bounties.phrases");
  
  BuildPath(Path_SM, g_LogPath, sizeof(g_LogPath), "logs/bountyhunter.log");
  
  //Flags
  CreateConVar("sm_bounties_version", VERSION, "", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_CHEAT|FCVAR_DONTRECORD);
  
  RegConsoleCmd("sm_setbounty", Command_Set_Bounty, "Set bounty on another player");
  RegConsoleCmd("sm_sb", Command_Set_Bounty, "Set bounty on another player");
  RegConsoleCmd("sm_checkbounty", Command_Check_Bounty, "Check bounty put on another players head");
  RegConsoleCmd("sm_cb", Command_Check_Bounty, "Check bounty put on another players head");
  RegConsoleCmd("sm_bountylist", Command_List_Bounty, "List the top bounties");
  RegConsoleCmd("sm_bl", Command_List_Bounty, "List the top bounties");
  
  //Hooks
  HookEvent("player_death", Event_PlayerDeath);
  HookEvent("cs_win_panel_match", Event_Match_End);
  AddCommandListener(Command_JoinTeam, "jointeam");
  
  //Cvars
  cvar_max_bounty_amount = CreateConVar("sm_bounties_max_bounty_amount", "1000", "Maximum amount a player can put on another players head (def. 1000)");
  cvar_min_players = CreateConVar("sm_bounties_min_players", "6", "Minimum amount of players before plugin active (def. 6)");
  
  //Starts disabled
  isEnabled = false;
  
  //Create config file
  AutoExecConfig(true, "bounties");
}

//On Map Start
public OnMapStart()
{
  //Start disabled on a new map
  isEnabled = false;
  
  //Create arrays
  for (int i = 1; i <= MaxClients; ++i) {
    if (IsClientInGame(i)) {
      playerKillStreak[i] = 0;
      playerSetBountyTarget[i] = new ArrayList(1);
      playerSetBountyAmount[i] = new ArrayList(1);
    }
  }
  
  //Delay count of players
  CreateTimer(30.0, Timer_CheckPlayers);
}

//Client put in server
public void OnClientPutInServer(int client)
{
  playerKillStreak[client] = 0;
  
  if (playerSetBountyTarget[client] != null)
    playerSetBountyTarget[client].Clear();
  else 
    playerSetBountyTarget[client] = new ArrayList(1);
  
  if (playerSetBountyAmount[client] != null)
    playerSetBountyAmount[client].Clear();
  else
    playerSetBountyAmount[client] = new ArrayList(1);
}

//Client disconnect from server
public void OnClientDisconnect(int client)
{
  if (!isEnabled)
    return;
  
  //Check if handle is valid
  if (playerSetBountyTarget[client] == null)
    return;
  
  //Check if player has a bounty on them, if they did, refund everybody
  int bountySize = playerSetBountyTarget[client].Length;
  
  if (bountySize != 0) {
    for (int i = 0; i < bountySize; ++i) {
      int refundTarget = playerSetBountyTarget[client].Get(i);
      int refundAmount = playerSetBountyAmount[client].Get(i);
      
      //Refund credits
      if (refundTarget > 0 && refundTarget < MaxClients && IsClientInGame(refundTarget)) {
        int curCredits = Store_GetClientCredits(refundTarget);
        Store_SetClientCredits(refundTarget, curCredits + refundAmount);
        
        CPrintToChat(refundTarget, "%s%t", CHAT_TAG_PREFIX, "You Were Refunded - Disconnect", refundAmount, client);
      }
    }
  }
  
  //Reset bounty for player
  OnClientPutInServer(client);
}

//Delayed player count
public Action Timer_CheckPlayers(Handle timer)
{
  if (isEnabled)
    return Plugin_Handled;
    
  int playerCount = 0;
  
  for (int i = 1; i <= MaxClients; ++i) {
    if (IsClientInGame(i)) {
      ++playerCount;
    }
  }
  
  if (playerCount < cvar_min_players.IntValue) {
    //Plugin remains disabled
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "Plugin Disabled Map", cvar_min_players.IntValue);
  }
  else {
    //Plugin is enabled
    isEnabled = true;
    
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "Plugin Enabled Map");
  }
  
  return Plugin_Handled;
}

//Called when match ends
public Action Event_Match_End(Event event, const char[] name, bool dontBroadcast)
{
  if (!isEnabled)
    return Plugin_Handled;
    
  //Reset all bounties
  //Give bounty to player who has bounty on their head
  for (int i = 1; i <= MaxClients; ++i) {
    if (IsClientInGame(i)) {
      int bountySize = playerSetBountyTarget[i].Length;
      int totalBountyAmount = 0;
      
      if (bountySize != 0) {
        for (int j = 0; j < bountySize; ++j) {
          totalBountyAmount += playerSetBountyAmount[i].Get(j);
        }
        
        //Hand out credits
        if (IsClientInGame(i)) {
          int curCredits = Store_GetClientCredits(i);
          Store_SetClientCredits(i, curCredits + totalBountyAmount);
          
          CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "Map End Survived", i, totalBountyAmount);
        }
      }
      
      //Reset all bounties
      OnClientPutInServer(i);
    }
  }
  
  return Plugin_Handled;
}


//Player death hook
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
  if (!isEnabled)
    return Plugin_Continue;

  int deadClient = GetClientOfUserId(event.GetInt("userid"));
  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  
  ++playerKillStreak[attacker]; //increase killstreak
  playerKillStreak[deadClient] = 0; //reset killstreak for this player
  
  if (deadClient == attacker || attacker == 0) {
    //Player suicided or died to world, refund all credits
    int bountySize = playerSetBountyTarget[deadClient].Length;
    
    if (bountySize != 0) {
      for (int i = 0; i < bountySize; ++i) {
        int refundTarget = playerSetBountyTarget[deadClient].Get(i);
        int refundAmount = playerSetBountyAmount[deadClient].Get(i);
        
        //Refund credits
        if (refundTarget > 0 && refundTarget < MaxClients && IsClientInGame(refundTarget)) {
          int curCredits = Store_GetClientCredits(refundTarget);
          Store_SetClientCredits(refundTarget, curCredits + refundAmount);
          
          CPrintToChat(refundTarget, "%s%t", CHAT_TAG_PREFIX, "You Were Refunded - Suicide", refundAmount, deadClient);
        }
      }
    }
    
    //Reset bounty for player
    OnClientPutInServer(deadClient);
    
    return Plugin_Continue;
  }
  
  //Give out bounty to attacker if dead client had one on their head
  int bountySize = playerSetBountyTarget[deadClient].Length;
  int totalBountyAmount = 0;
  
  if (bountySize != 0) {
    for (int i = 0; i < bountySize; ++i) {
      totalBountyAmount += playerSetBountyAmount[deadClient].Get(i);
    }
    
    //Reset bounty for this client
    ClearArray(playerSetBountyTarget[deadClient]);
    ClearArray(playerSetBountyAmount[deadClient]);
    
    //Hand out credits
    if (IsClientInGame(attacker)) {
      int curCredits = Store_GetClientCredits(attacker);
      Store_SetClientCredits(attacker, curCredits + totalBountyAmount);
  
      CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "Bounty Collected", attacker, totalBountyAmount, deadClient);
    }
  }
  
  //Check for automatic bounty
  int autoBountyAmount = 0;
  
  switch (playerKillStreak[attacker]) {
    case 4:
    {
      autoBountyAmount = 10;
    }
    case 7:
    {
      autoBountyAmount = 20;
    }
    case 10:
    {
      autoBountyAmount = 50;
    }
    case 13:
    {
      autoBountyAmount = 100;
    }
    case 16:
    {
      autoBountyAmount = 175;
    }
    case 19:
    {
      autoBountyAmount = 325;
    }
    case 21:
    {
      autoBountyAmount = 750;
    }
    case 40:
    {
      autoBountyAmount = 3000;
      
      //Record killstreak to file
      if (IsClientInGame(attacker)) {
        char auth[32];
        if (!GetClientAuthId(attacker, AuthId_Steam2, auth, sizeof(auth)))
          Format(auth, sizeof(auth), "NO_AUTH");
        
        LogToFileEx(g_LogPath, "Player %N (%s) attained %d killstreak!", attacker, auth, playerKillStreak[attacker]);
      }
    }
  }
  
  //There will be no change to auto bounty here
  if (autoBountyAmount == 0) {
    return Plugin_Continue;
  }
  
  //Check if an auto bounty is set for this player
  bool wasAutoBountyUpdated = false;
  int index = playerSetBountyTarget[attacker].FindValue(PLAYER_SERVER);
  
  if (index != -1) {
    //Remove old auto bounty
    playerSetBountyTarget[attacker].Erase(index);
    playerSetBountyAmount[attacker].Erase(index);
    
    wasAutoBountyUpdated = true;
    
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "Auto Bounty Update", attacker, autoBountyAmount);
  }
  
  //Insert auto bounty
  playerSetBountyTarget[attacker].Push(PLAYER_SERVER);
  playerSetBountyAmount[attacker].Push(autoBountyAmount);
  
  if (!wasAutoBountyUpdated)
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "Auto Bounty Added", autoBountyAmount, attacker);
  
  return Plugin_Continue;
}

public Action Command_Set_Bounty(int client, int args) 
{
  if (!isEnabled) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Plugin Disabled For Map");
    return Plugin_Handled;
  }
    
  if (!IsClientInGame(client))
    return Plugin_Handled;
    
  if (args < 2) {
    CPrintToChat(client, "%s%s", CHAT_TAG_PREFIX, "Usage: sm_setbounty <target> <amount>");
    return Plugin_Handled;
  }
  
  char arg1[32];
  char arg2[32];
  GetCmdArg(1, arg1, sizeof(arg1));
  GetCmdArg(2, arg2, sizeof(arg2));

  int target = FindTarget(client, arg1, true, false);
  int bountyAmount = StringToInt(arg2);
  
  //Ensure chosen target is valid
  if (target == -1) {
    CPrintToChat(client, "%s%s", CHAT_TAG_PREFIX, "Specified target is invalid.");
    return Plugin_Handled;
  }
  
  //Check to ensure target isn't the player themselves
  if (target == client) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Cant Bounty Self");
    return Plugin_Handled;
  }
  
  //Check to ensure target isn't in spectate mode
  int targetTeam = GetClientTeam(target);
  if (targetTeam != CS_TEAM_T && targetTeam != CS_TEAM_CT) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Cant Bounty Bad Team", target);
    return Plugin_Handled;
  }
  
  //Check that bounty isn't too low or zeo
  if (bountyAmount <= 0) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Bounty Cant Negative Or Zero");
    return Plugin_Handled;
  }
  
  //Check that bounty isn't too high
  if (bountyAmount > cvar_max_bounty_amount.IntValue) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Bounty Too High", cvar_max_bounty_amount.IntValue);
    return Plugin_Handled;
  }
  
  //Check that player hasn't already set bounty on target
  int index = playerSetBountyTarget[target].FindValue(client);
  if (index != -1) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Bounty Already Set", target);
    return Plugin_Handled;
  }
  
  //Check for enough credits
  int curCredits = Store_GetClientCredits(client);
  
  if (bountyAmount > curCredits) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Not Enough Credits", target);
    return Plugin_Handled;
  }
  
  //At this stage bounty can be set
  Store_SetClientCredits(client, curCredits - bountyAmount);
  
  //Set bounty
  playerSetBountyTarget[target].Push(client);
  playerSetBountyAmount[target].Push(bountyAmount);
  
  CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "New Bounty Set", bountyAmount, target, client);
  
  return Plugin_Handled;
}

    
//Tells you the bounties put on various players
public Action Command_Check_Bounty(int client, int args) 
{
  if (!isEnabled) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Plugin Disabled For Map");
    return Plugin_Handled;
  }
    
  if (!IsClientInGame(client))
    return Plugin_Handled;
    
  if (args < 1) {
    CPrintToChat(client, "%s%s", CHAT_TAG_PREFIX, "Usage: sm_checkbounty <target>");
    return Plugin_Handled;
  }
  
  char arg1[32];
  GetCmdArg(1, arg1, sizeof(arg1));

  int target = FindTarget(client, arg1, true, false);
  
  //Ensure chosen target is valid
  if (target == -1) {
    CPrintToChat(client, "%s%s", CHAT_TAG_PREFIX, "Specified target is invalid.");
    return Plugin_Handled;
  }
  
  //Check if there is bounty on this players head
  int bountySize = playerSetBountyTarget[target].Length;
  int totalBountyAmount = 0;
  
  if (bountySize != 0) {
    for (int i = 0; i < bountySize; ++i) {
      totalBountyAmount += playerSetBountyAmount[target].Get(i);
    }
  }
  
  if (bountySize == 0) {
    if (client == target)
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "No Bounty Player Self Check");
    else
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "No Bounty Player", target);
  }
  else {
    if (client == target)
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Yes Bounty Player Self Check", totalBountyAmount);
    else
      CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Yes Bounty Player", totalBountyAmount, target);
  }
  
  return Plugin_Handled;
}

//Tells you the bounties put on various players
public Action Command_List_Bounty(int client, int args) 
{
  if (!isEnabled) {
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "Plugin Disabled For Map");
    return Plugin_Handled;
  }

  if (!IsClientInGame(client))
    return Plugin_Handled;
    
  ArrayList top10Bounty = new ArrayList(64, MaxClients+1);
  int totalNumBounties = 0;
  
  //Check all bounties
  for (int i = 1; i < MaxClients; ++i) {
    if (IsClientInGame(i)) {
      int bountySize = playerSetBountyTarget[i].Length;
      int totalBountyAmount = 0;

      if (bountySize != 0) {
        for (int j = 0; j < bountySize; ++j) {
          totalBountyAmount += playerSetBountyAmount[i].Get(j);
        }
      }
      
      if (totalBountyAmount <= 0)
        continue;
      
      char bountyLine[128];
      char name[64];
      GetClientName(i, name, sizeof(name));
      Format(bountyLine, sizeof(bountyLine), "%s (%d)", name, totalBountyAmount);
      
      //Add to totals
      top10Bounty.PushString(bountyLine);
      
      ++totalNumBounties;
    }
  }
  
  //Sort
  SortADTArrayCustom(top10Bounty, mySort);
  
  //Rank from highest to lowest
  Menu BountyMenu = new Menu(BountyMenuHandler);
  BountyMenu.SetTitle("Bounty List:");
  
  for (int i = 0; i < totalNumBounties; ++i) {
    char buff1[128], option[2];
    IntToString(i, option, sizeof(option));
    top10Bounty.GetString(i, buff1, sizeof(buff1));
    BountyMenu.AddItem(option, buff1, ITEMDRAW_DISABLED);
  }
  
  if (totalNumBounties == 0) {
    BountyMenu.AddItem("1", "No bounties placed", ITEMDRAW_DISABLED);
  }
  
  //Free array
  delete top10Bounty;
  
  //Display this menu until clients exits it
  BountyMenu.Display(client, MENU_TIME_FOREVER);
  
  return Plugin_Handled;
}

public int BountyMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
  //Destroy menu
  if (action == MenuAction_End)
    delete menu;
}

//SortFuncADTArray to sort the top 10 bounty list
public int mySort(int index1, int index2, Handle array, Handle hndl)
{
  char buff1[128], buff2[128];
  GetArrayString(array, index1, buff1, sizeof(buff1));
  GetArrayString(array, index2, buff2, sizeof(buff2));
  
  int charIndex1 = FindCharInString(buff1, '(', true);
  int charIndex2 = FindCharInString(buff2, '(', true);
  
  char dest1[128], dest2[128];
  strcopy(dest1, strlen(buff1)-charIndex1-1, buff1[charIndex1+1]);
  strcopy(dest2, strlen(buff2)-charIndex2-1, buff2[charIndex2+1]);
  int num1 = StringToInt(dest1);
  int num2 = StringToInt(dest2);
  
  if (num1 < num2)
    return 1;
  else if (num1 == num2)
    return 0;
  else
    return -1;
}

//Refunds bounty if a player moves to spectate but not if they switch teams while dead
public Action Command_JoinTeam(int client, const char[] command, int argc) 
{
  if (!(client > 0 && client <= MaxClients && IsClientInGame(client)) || argc < 1)
    return Plugin_Handled;
  
  if (!isEnabled)
    return Plugin_Continue;
  
  char arg[4];
  GetCmdArg(1, arg, sizeof(arg));
  int toTeam = StringToInt(arg);
  
  if (toTeam == CS_TEAM_SPECTATOR || toTeam == CS_TEAM_UNASSIGNED) {
    //Check if they have a bounty on them
    //If so, refund the bounty and reset kill streak
    
    int bountySize = playerSetBountyTarget[client].Length;
    
    if (bountySize != 0) {
      for (int i = 0; i < bountySize; ++i) {
        int refundTarget = playerSetBountyTarget[client].Get(i);
        int refundAmount = playerSetBountyAmount[client].Get(i);
        
        //Refund credits
        if (refundTarget > 0 && refundTarget < MaxClients && IsClientInGame(refundTarget)) {
          int curCredits = Store_GetClientCredits(refundTarget);
          Store_SetClientCredits(refundTarget, curCredits + refundAmount);
          
          CPrintToChat(refundTarget, "%s%t", CHAT_TAG_PREFIX, "You Were Refunded - Join Spec", refundAmount, client);
        }
      }
    }
    
    //Reset bounty for player
    OnClientPutInServer(client);
  }
  
  return Plugin_Continue;
}