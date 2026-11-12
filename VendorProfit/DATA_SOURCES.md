# Profession data

`ProfessionData.lua` contains numeric profession facts extracted from the installed [SkillUp Forever 1.9.0](https://github.com/cjber/skillup-forever) data and reformatted for Vendor Profit. The derived data retains the source's GPL-3.0-or-later license. See `ProfessionData.LICENSE.txt`.

- WoW Forever client build 1.60.1.70888 provides recipe thresholds, reagents, outputs and vendor prices. [Client table exports](https://wago.tools/db2/SkillLineAbility/csv?build=1.60.1.70888)
- Trainer costs and some drop sources use Classic records and observations. [CMaNGOS Classic database](https://github.com/cmangos/classic-db), [SkillUp Forever credits](https://github.com/cjber/skillup-forever/blob/main/THIRD_PARTY.md)
- The list of standard merchant reagents originates in LibPeriodicTable-3.1. [LibPeriodicTable-3.1](https://github.com/doadin/libperiodictable-3-1)

Vendor Profit prefers live recipe data and reads optional location data through QuestieDB at runtime.

## Bulk buying

`BulkBuy.lua` is new code. The shift-click idea and the half-second purchase pace follow [Multi Buyer](https://github.com/rockschtar/MultiBuyer) (GPL-3.0), which is a rewrite of BuyEmAll.
