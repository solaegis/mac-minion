# ESO SavedVariables graph model: key findings (2026-10-30)

Full report: https://claude.ai/artifact/G2MvhqWGkcowYWvrYfXhnF

- Scope: live/AddOns (133 manifests, 99 declare 122 globals) + live/SavedVariables (91 .lua, 112 globals, 64.6 MB).
- Roots: Character = (account, megaserver, 16-digit characterId); Addon = (name, AddOnVersion, manifest path). They meet at Scope.
- ZO_SavedVars level 1 is a PROFILE ("Default" = no profile), not a megaserver (LibSavedVars.lua:493). 49 globals Default-only, 21 real servers, 2 both.
- Megaserver has 6 encodings: profile key, namespace at depth 4 (EsoAutoProvision/EsoCombatLock/EsoVendorJunk/CraftStore pass GetWorldName() as namespace), NA/EU short codes (IIfA, LibCK), na/eu suffixes (GS00-17), "NA Megaserver@acct" composites (AGS, LibChatMessage), NAData/EUData (TTC).
- Pseudo-accounts: $InstallationWide, NA, EU, $AllAccounts, MasterMerchant, AllAccountsTheSame. HarvestMap stores account without "@".
- 38 characters (25 NA / 13 EU; 29 @SOLAEGIS / 9 @vavasour). "Masisi" exists on NA and EU: 6 Default-profile name-keyed globals conflate them. "Kellen Dysart" is a name with no ID (orphan).
- Structural Config/Snapshot classification was wrong on 13 of 30 non-GS snapshot calls; code evidence (LAM bindings, writers) must decide; LLM only for residue.
- Text-grep code->SV edges: 4 of 7 cross-addon refs false (comments/strings). Use a token-level scanner.
- Longest dependsOn chain incl. optional deps: 10 hops.
- Fix in MacMinion: SVUsage "saved before servers were split" label; SVLevel .server -> .profile and accept char names at depth 3; SettingsMatrix.homes only uses R1.
- Missing evidence: live/AddOnSettings.txt (not connected), EsoMacMinion_Data.lua absent until the companion is installed, SV git repo has 1 commit.
