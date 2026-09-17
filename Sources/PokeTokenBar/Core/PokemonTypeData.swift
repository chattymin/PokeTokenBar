import Foundation

/// 1~5세대(#1~#649) 포켓몬 18종 타입 정의 및 상성 데이터.
public enum PokemonType: String, Codable, Sendable, CaseIterable {
    case normal
    case fire
    case water
    case grass
    case electric
    case ice
    case fighting
    case poison
    case ground
    case flying
    case psychic
    case bug
    case rock
    case ghost
    case dragon
    case steel
    case dark
    case fairy

    /// 타입별 대응 배지 아이템.
    var badgeItem: ItemKind {
        switch self {
        case .normal:   return .plainBadge
        case .fire:     return .volcanoBadge
        case .water:    return .cascadeBadge
        case .grass:    return .rainbowBadge
        case .electric: return .thunderBadge
        case .ice:      return .glacierBadge
        case .fighting: return .stormBadge
        case .poison:   return .soulBadge
        case .ground:   return .earthBadge
        case .flying:   return .zephyrBadge
        case .psychic:  return .marshBadge
        case .bug:      return .hiveBadge
        case .rock:     return .boulderBadge
        case .ghost:    return .fogBadge
        case .dragon:   return .risingBadge
        case .steel:    return .mineralBadge
        case .dark:     return .darkBadge
        case .fairy:    return .fairyBadge
        }
    }

    /// 타입별 대응 업적.
    public var achievement: AchievementType {
        switch self {
        case .normal:   return .badgePlain
        case .fire:     return .badgeVolcano
        case .water:    return .badgeCascade
        case .grass:    return .badgeRainbow
        case .electric: return .badgeThunder
        case .ice:      return .badgeGlacier
        case .fighting: return .badgeStorm
        case .poison:   return .badgeSoul
        case .ground:   return .badgeEarth
        case .flying:   return .badgeZephyr
        case .psychic:  return .badgeMarsh
        case .bug:      return .badgeHive
        case .rock:     return .badgeBoulder
        case .ghost:    return .badgeFog
        case .dragon:   return .badgeRising
        case .steel:    return .badgeMineral
        case .dark:     return .badgeDark
        case .fairy:    return .badgeFairy
        }
    }

    /// 퀘스트 아이콘.
    public var badgeIcon: QuestIcon {
        switch self {
        case .normal:   return .badgePlain
        case .fire:     return .badgeVolcano
        case .water:    return .badgeCascade
        case .grass:    return .badgeRainbow
        case .electric: return .badgeThunder
        case .ice:      return .badgeGlacier
        case .fighting: return .badgeStorm
        case .poison:   return .badgeSoul
        case .ground:   return .badgeEarth
        case .flying:   return .badgeZephyr
        case .psychic:  return .badgeMarsh
        case .bug:      return .badgeHive
        case .rock:     return .badgeBoulder
        case .ghost:    return .badgeFog
        case .dragon:   return .badgeRising
        case .steel:    return .badgeMineral
        case .dark:     return .badgeDark
        case .fairy:    return .badgeFairy
        }
    }

    /// PokéAPI 배지 스프라이트 파일명 (sprites/badges/{id}.png).
    public var badgeSpriteName: String {
        switch self {
        case .rock:     return "badge-1"
        case .water:    return "badge-2"
        case .electric: return "badge-3"
        case .grass:    return "badge-4"
        case .poison:   return "badge-5"
        case .psychic:  return "badge-6"
        case .fire:     return "badge-7"
        case .ground:   return "badge-8"
        case .flying:   return "badge-9"
        case .bug:      return "badge-10"
        case .normal:   return "badge-11"
        case .ghost:    return "badge-12"
        case .fighting: return "badge-13"
        case .steel:    return "badge-14"
        case .ice:      return "badge-15"
        case .dragon:   return "badge-16"
        case .dark:     return "badge-59"
        case .fairy:    return "badge-48"
        }
    }
}

public enum PokemonTypeData {
    /// 1~5세대 종 ID 별 타입 목록.
    public static let speciesToTypes: [Int: [PokemonType]] = {
        var map: [Int: [PokemonType]] = [:]
        map.reserveCapacity(650)
        map[1] = [.grass, .poison]
        map[2] = [.grass, .poison]
        map[3] = [.grass, .poison]
        map[4] = [.fire]
        map[5] = [.fire]
        map[6] = [.fire, .flying]
        map[7] = [.water]
        map[8] = [.water]
        map[9] = [.water]
        map[10] = [.bug]
        map[11] = [.bug]
        map[12] = [.bug, .flying]
        map[13] = [.bug, .poison]
        map[14] = [.bug, .poison]
        map[15] = [.bug, .poison]
        map[16] = [.normal, .flying]
        map[17] = [.normal, .flying]
        map[18] = [.normal, .flying]
        map[19] = [.normal]
        map[20] = [.normal]
        map[21] = [.normal, .flying]
        map[22] = [.normal, .flying]
        map[23] = [.poison]
        map[24] = [.poison]
        map[25] = [.electric]
        map[26] = [.electric]
        map[27] = [.ground]
        map[28] = [.ground]
        map[29] = [.poison]
        map[30] = [.poison]
        map[31] = [.poison, .ground]
        map[32] = [.poison]
        map[33] = [.poison]
        map[34] = [.poison, .ground]
        map[35] = [.fairy]
        map[36] = [.fairy]
        map[37] = [.fire]
        map[38] = [.fire]
        map[39] = [.normal, .fairy]
        map[40] = [.normal, .fairy]
        map[41] = [.poison, .flying]
        map[42] = [.poison, .flying]
        map[43] = [.grass, .poison]
        map[44] = [.grass, .poison]
        map[45] = [.grass, .poison]
        map[46] = [.bug, .grass]
        map[47] = [.bug, .grass]
        map[48] = [.bug, .poison]
        map[49] = [.bug, .poison]
        map[50] = [.ground]
        map[51] = [.ground]
        map[52] = [.normal]
        map[53] = [.normal]
        map[54] = [.water]
        map[55] = [.water]
        map[56] = [.fighting]
        map[57] = [.fighting]
        map[58] = [.fire]
        map[59] = [.fire]
        map[60] = [.water]
        map[61] = [.water]
        map[62] = [.water, .fighting]
        map[63] = [.psychic]
        map[64] = [.psychic]
        map[65] = [.psychic]
        map[66] = [.fighting]
        map[67] = [.fighting]
        map[68] = [.fighting]
        map[69] = [.grass, .poison]
        map[70] = [.grass, .poison]
        map[71] = [.grass, .poison]
        map[72] = [.water, .poison]
        map[73] = [.water, .poison]
        map[74] = [.rock, .ground]
        map[75] = [.rock, .ground]
        map[76] = [.rock, .ground]
        map[77] = [.fire]
        map[78] = [.fire]
        map[79] = [.water, .psychic]
        map[80] = [.water, .psychic]
        map[81] = [.electric, .steel]
        map[82] = [.electric, .steel]
        map[83] = [.normal, .flying]
        map[84] = [.normal, .flying]
        map[85] = [.normal, .flying]
        map[86] = [.water]
        map[87] = [.water, .ice]
        map[88] = [.poison]
        map[89] = [.poison]
        map[90] = [.water]
        map[91] = [.water, .ice]
        map[92] = [.ghost, .poison]
        map[93] = [.ghost, .poison]
        map[94] = [.ghost, .poison]
        map[95] = [.rock, .ground]
        map[96] = [.psychic]
        map[97] = [.psychic]
        map[98] = [.water]
        map[99] = [.water]
        map[100] = [.electric]
        map[101] = [.electric]
        map[102] = [.grass, .psychic]
        map[103] = [.grass, .psychic]
        map[104] = [.ground]
        map[105] = [.ground]
        map[106] = [.fighting]
        map[107] = [.fighting]
        map[108] = [.normal]
        map[109] = [.poison]
        map[110] = [.poison]
        map[111] = [.ground, .rock]
        map[112] = [.ground, .rock]
        map[113] = [.normal]
        map[114] = [.grass]
        map[115] = [.normal]
        map[116] = [.water]
        map[117] = [.water]
        map[118] = [.water]
        map[119] = [.water]
        map[120] = [.water]
        map[121] = [.water, .psychic]
        map[122] = [.psychic, .fairy]
        map[123] = [.bug, .flying]
        map[124] = [.ice, .psychic]
        map[125] = [.electric]
        map[126] = [.fire]
        map[127] = [.bug]
        map[128] = [.normal]
        map[129] = [.water]
        map[130] = [.water, .flying]
        map[131] = [.water, .ice]
        map[132] = [.normal]
        map[133] = [.normal]
        map[134] = [.water]
        map[135] = [.electric]
        map[136] = [.fire]
        map[137] = [.normal]
        map[138] = [.rock, .water]
        map[139] = [.rock, .water]
        map[140] = [.rock, .water]
        map[141] = [.rock, .water]
        map[142] = [.rock, .flying]
        map[143] = [.normal]
        map[144] = [.ice, .flying]
        map[145] = [.electric, .flying]
        map[146] = [.fire, .flying]
        map[147] = [.dragon]
        map[148] = [.dragon]
        map[149] = [.dragon, .flying]
        map[150] = [.psychic]
        map[151] = [.psychic]
        map[152] = [.grass]
        map[153] = [.grass]
        map[154] = [.grass]
        map[155] = [.fire]
        map[156] = [.fire]
        map[157] = [.fire]
        map[158] = [.water]
        map[159] = [.water]
        map[160] = [.water]
        map[161] = [.normal]
        map[162] = [.normal]
        map[163] = [.normal, .flying]
        map[164] = [.normal, .flying]
        map[165] = [.bug, .flying]
        map[166] = [.bug, .flying]
        map[167] = [.bug, .poison]
        map[168] = [.bug, .poison]
        map[169] = [.poison, .flying]
        map[170] = [.water, .electric]
        map[171] = [.water, .electric]
        map[172] = [.electric]
        map[173] = [.fairy]
        map[174] = [.normal, .fairy]
        map[175] = [.fairy]
        map[176] = [.fairy, .flying]
        map[177] = [.psychic, .flying]
        map[178] = [.psychic, .flying]
        map[179] = [.electric]
        map[180] = [.electric]
        map[181] = [.electric]
        map[182] = [.grass]
        map[183] = [.water, .fairy]
        map[184] = [.water, .fairy]
        map[185] = [.rock]
        map[186] = [.water]
        map[187] = [.grass, .flying]
        map[188] = [.grass, .flying]
        map[189] = [.grass, .flying]
        map[190] = [.normal]
        map[191] = [.grass]
        map[192] = [.grass]
        map[193] = [.bug, .flying]
        map[194] = [.water, .ground]
        map[195] = [.water, .ground]
        map[196] = [.psychic]
        map[197] = [.dark]
        map[198] = [.dark, .flying]
        map[199] = [.water, .psychic]
        map[200] = [.ghost]
        map[201] = [.psychic]
        map[202] = [.psychic]
        map[203] = [.normal, .psychic]
        map[204] = [.bug]
        map[205] = [.bug, .steel]
        map[206] = [.normal]
        map[207] = [.ground, .flying]
        map[208] = [.steel, .ground]
        map[209] = [.fairy]
        map[210] = [.fairy]
        map[211] = [.water, .poison]
        map[212] = [.bug, .steel]
        map[213] = [.bug, .rock]
        map[214] = [.bug, .fighting]
        map[215] = [.dark, .ice]
        map[216] = [.normal]
        map[217] = [.normal]
        map[218] = [.fire]
        map[219] = [.fire, .rock]
        map[220] = [.ice, .ground]
        map[221] = [.ice, .ground]
        map[222] = [.water, .rock]
        map[223] = [.water]
        map[224] = [.water]
        map[225] = [.ice, .flying]
        map[226] = [.water, .flying]
        map[227] = [.steel, .flying]
        map[228] = [.dark, .fire]
        map[229] = [.dark, .fire]
        map[230] = [.water, .dragon]
        map[231] = [.ground]
        map[232] = [.ground]
        map[233] = [.normal]
        map[234] = [.normal]
        map[235] = [.normal]
        map[236] = [.fighting]
        map[237] = [.fighting]
        map[238] = [.ice, .psychic]
        map[239] = [.electric]
        map[240] = [.fire]
        map[241] = [.normal]
        map[242] = [.normal]
        map[243] = [.electric]
        map[244] = [.fire]
        map[245] = [.water]
        map[246] = [.rock, .ground]
        map[247] = [.rock, .ground]
        map[248] = [.rock, .dark]
        map[249] = [.psychic, .flying]
        map[250] = [.fire, .flying]
        map[251] = [.psychic, .grass]
        map[252] = [.grass]
        map[253] = [.grass]
        map[254] = [.grass]
        map[255] = [.fire]
        map[256] = [.fire, .fighting]
        map[257] = [.fire, .fighting]
        map[258] = [.water]
        map[259] = [.water, .ground]
        map[260] = [.water, .ground]
        map[261] = [.dark]
        map[262] = [.dark]
        map[263] = [.normal]
        map[264] = [.normal]
        map[265] = [.bug]
        map[266] = [.bug]
        map[267] = [.bug, .flying]
        map[268] = [.bug]
        map[269] = [.bug, .poison]
        map[270] = [.water, .grass]
        map[271] = [.water, .grass]
        map[272] = [.water, .grass]
        map[273] = [.grass]
        map[274] = [.grass, .dark]
        map[275] = [.grass, .dark]
        map[276] = [.normal, .flying]
        map[277] = [.normal, .flying]
        map[278] = [.water, .flying]
        map[279] = [.water, .flying]
        map[280] = [.psychic, .fairy]
        map[281] = [.psychic, .fairy]
        map[282] = [.psychic, .fairy]
        map[283] = [.bug, .water]
        map[284] = [.bug, .flying]
        map[285] = [.grass]
        map[286] = [.grass, .fighting]
        map[287] = [.normal]
        map[288] = [.normal]
        map[289] = [.normal]
        map[290] = [.bug, .ground]
        map[291] = [.bug, .flying]
        map[292] = [.bug, .ghost]
        map[293] = [.normal]
        map[294] = [.normal]
        map[295] = [.normal]
        map[296] = [.fighting]
        map[297] = [.fighting]
        map[298] = [.normal, .fairy]
        map[299] = [.rock]
        map[300] = [.normal]
        map[301] = [.normal]
        map[302] = [.dark, .ghost]
        map[303] = [.steel, .fairy]
        map[304] = [.steel, .rock]
        map[305] = [.steel, .rock]
        map[306] = [.steel, .rock]
        map[307] = [.fighting, .psychic]
        map[308] = [.fighting, .psychic]
        map[309] = [.electric]
        map[310] = [.electric]
        map[311] = [.electric]
        map[312] = [.electric]
        map[313] = [.bug]
        map[314] = [.bug]
        map[315] = [.grass, .poison]
        map[316] = [.poison]
        map[317] = [.poison]
        map[318] = [.water, .dark]
        map[319] = [.water, .dark]
        map[320] = [.water]
        map[321] = [.water]
        map[322] = [.fire, .ground]
        map[323] = [.fire, .ground]
        map[324] = [.fire]
        map[325] = [.psychic]
        map[326] = [.psychic]
        map[327] = [.normal]
        map[328] = [.ground]
        map[329] = [.ground, .dragon]
        map[330] = [.ground, .dragon]
        map[331] = [.grass]
        map[332] = [.grass, .dark]
        map[333] = [.normal, .flying]
        map[334] = [.dragon, .flying]
        map[335] = [.normal]
        map[336] = [.poison]
        map[337] = [.rock, .psychic]
        map[338] = [.rock, .psychic]
        map[339] = [.water, .ground]
        map[340] = [.water, .ground]
        map[341] = [.water]
        map[342] = [.water, .dark]
        map[343] = [.ground, .psychic]
        map[344] = [.ground, .psychic]
        map[345] = [.rock, .grass]
        map[346] = [.rock, .grass]
        map[347] = [.rock, .bug]
        map[348] = [.rock, .bug]
        map[349] = [.water]
        map[350] = [.water]
        map[351] = [.normal]
        map[352] = [.normal]
        map[353] = [.ghost]
        map[354] = [.ghost]
        map[355] = [.ghost]
        map[356] = [.ghost]
        map[357] = [.grass, .flying]
        map[358] = [.psychic]
        map[359] = [.dark]
        map[360] = [.psychic]
        map[361] = [.ice]
        map[362] = [.ice]
        map[363] = [.ice, .water]
        map[364] = [.ice, .water]
        map[365] = [.ice, .water]
        map[366] = [.water]
        map[367] = [.water]
        map[368] = [.water]
        map[369] = [.water, .rock]
        map[370] = [.water]
        map[371] = [.dragon]
        map[372] = [.dragon]
        map[373] = [.dragon, .flying]
        map[374] = [.steel, .psychic]
        map[375] = [.steel, .psychic]
        map[376] = [.steel, .psychic]
        map[377] = [.rock]
        map[378] = [.ice]
        map[379] = [.steel]
        map[380] = [.dragon, .psychic]
        map[381] = [.dragon, .psychic]
        map[382] = [.water]
        map[383] = [.ground]
        map[384] = [.dragon, .flying]
        map[385] = [.steel, .psychic]
        map[386] = [.psychic]
        map[387] = [.grass]
        map[388] = [.grass]
        map[389] = [.grass, .ground]
        map[390] = [.fire]
        map[391] = [.fire, .fighting]
        map[392] = [.fire, .fighting]
        map[393] = [.water]
        map[394] = [.water]
        map[395] = [.water, .steel]
        map[396] = [.normal, .flying]
        map[397] = [.normal, .flying]
        map[398] = [.normal, .flying]
        map[399] = [.normal]
        map[400] = [.normal, .water]
        map[401] = [.bug]
        map[402] = [.bug]
        map[403] = [.electric]
        map[404] = [.electric]
        map[405] = [.electric]
        map[406] = [.grass, .poison]
        map[407] = [.grass, .poison]
        map[408] = [.rock]
        map[409] = [.rock]
        map[410] = [.rock, .steel]
        map[411] = [.rock, .steel]
        map[412] = [.bug]
        map[413] = [.bug, .grass]
        map[414] = [.bug, .flying]
        map[415] = [.bug, .flying]
        map[416] = [.bug, .flying]
        map[417] = [.electric]
        map[418] = [.water]
        map[419] = [.water]
        map[420] = [.grass]
        map[421] = [.grass]
        map[422] = [.water]
        map[423] = [.water, .ground]
        map[424] = [.normal]
        map[425] = [.ghost, .flying]
        map[426] = [.ghost, .flying]
        map[427] = [.normal]
        map[428] = [.normal]
        map[429] = [.ghost]
        map[430] = [.dark, .flying]
        map[431] = [.normal]
        map[432] = [.normal]
        map[433] = [.psychic]
        map[434] = [.poison, .dark]
        map[435] = [.poison, .dark]
        map[436] = [.steel, .psychic]
        map[437] = [.steel, .psychic]
        map[438] = [.rock]
        map[439] = [.psychic, .fairy]
        map[440] = [.normal]
        map[441] = [.normal, .flying]
        map[442] = [.ghost, .dark]
        map[443] = [.dragon, .ground]
        map[444] = [.dragon, .ground]
        map[445] = [.dragon, .ground]
        map[446] = [.normal]
        map[447] = [.fighting]
        map[448] = [.fighting, .steel]
        map[449] = [.ground]
        map[450] = [.ground]
        map[451] = [.poison, .bug]
        map[452] = [.poison, .dark]
        map[453] = [.poison, .fighting]
        map[454] = [.poison, .fighting]
        map[455] = [.grass]
        map[456] = [.water]
        map[457] = [.water]
        map[458] = [.water, .flying]
        map[459] = [.grass, .ice]
        map[460] = [.grass, .ice]
        map[461] = [.dark, .ice]
        map[462] = [.electric, .steel]
        map[463] = [.normal]
        map[464] = [.ground, .rock]
        map[465] = [.grass]
        map[466] = [.electric]
        map[467] = [.fire]
        map[468] = [.fairy, .flying]
        map[469] = [.bug, .flying]
        map[470] = [.grass]
        map[471] = [.ice]
        map[472] = [.ground, .flying]
        map[473] = [.ice, .ground]
        map[474] = [.normal]
        map[475] = [.psychic, .fighting]
        map[476] = [.rock, .steel]
        map[477] = [.ghost]
        map[478] = [.ice, .ghost]
        map[479] = [.electric, .ghost]
        map[480] = [.psychic]
        map[481] = [.psychic]
        map[482] = [.psychic]
        map[483] = [.steel, .dragon]
        map[484] = [.water, .dragon]
        map[485] = [.fire, .steel]
        map[486] = [.normal]
        map[487] = [.ghost, .dragon]
        map[488] = [.psychic]
        map[489] = [.water]
        map[490] = [.water]
        map[491] = [.dark]
        map[492] = [.grass]
        map[493] = [.normal]
        map[494] = [.psychic, .fire]
        map[495] = [.grass]
        map[496] = [.grass]
        map[497] = [.grass]
        map[498] = [.fire]
        map[499] = [.fire, .fighting]
        map[500] = [.fire, .fighting]
        map[501] = [.water]
        map[502] = [.water]
        map[503] = [.water]
        map[504] = [.normal]
        map[505] = [.normal]
        map[506] = [.normal]
        map[507] = [.normal]
        map[508] = [.normal]
        map[509] = [.dark]
        map[510] = [.dark]
        map[511] = [.grass]
        map[512] = [.grass]
        map[513] = [.fire]
        map[514] = [.fire]
        map[515] = [.water]
        map[516] = [.water]
        map[517] = [.psychic]
        map[518] = [.psychic]
        map[519] = [.normal, .flying]
        map[520] = [.normal, .flying]
        map[521] = [.normal, .flying]
        map[522] = [.electric]
        map[523] = [.electric]
        map[524] = [.rock]
        map[525] = [.rock]
        map[526] = [.rock]
        map[527] = [.psychic, .flying]
        map[528] = [.psychic, .flying]
        map[529] = [.ground]
        map[530] = [.ground, .steel]
        map[531] = [.normal]
        map[532] = [.fighting]
        map[533] = [.fighting]
        map[534] = [.fighting]
        map[535] = [.water]
        map[536] = [.water, .ground]
        map[537] = [.water, .ground]
        map[538] = [.fighting]
        map[539] = [.fighting]
        map[540] = [.bug, .grass]
        map[541] = [.bug, .grass]
        map[542] = [.bug, .grass]
        map[543] = [.bug, .poison]
        map[544] = [.bug, .poison]
        map[545] = [.bug, .poison]
        map[546] = [.grass, .fairy]
        map[547] = [.grass, .fairy]
        map[548] = [.grass]
        map[549] = [.grass]
        map[550] = [.water]
        map[551] = [.ground, .dark]
        map[552] = [.ground, .dark]
        map[553] = [.ground, .dark]
        map[554] = [.fire]
        map[555] = [.fire]
        map[556] = [.grass]
        map[557] = [.bug, .rock]
        map[558] = [.bug, .rock]
        map[559] = [.dark, .fighting]
        map[560] = [.dark, .fighting]
        map[561] = [.psychic, .flying]
        map[562] = [.ghost]
        map[563] = [.ghost]
        map[564] = [.water, .rock]
        map[565] = [.water, .rock]
        map[566] = [.rock, .flying]
        map[567] = [.rock, .flying]
        map[568] = [.poison]
        map[569] = [.poison]
        map[570] = [.dark]
        map[571] = [.dark]
        map[572] = [.normal]
        map[573] = [.normal]
        map[574] = [.psychic]
        map[575] = [.psychic]
        map[576] = [.psychic]
        map[577] = [.psychic]
        map[578] = [.psychic]
        map[579] = [.psychic]
        map[580] = [.water, .flying]
        map[581] = [.water, .flying]
        map[582] = [.ice]
        map[583] = [.ice]
        map[584] = [.ice]
        map[585] = [.normal, .grass]
        map[586] = [.normal, .grass]
        map[587] = [.electric, .flying]
        map[588] = [.bug]
        map[589] = [.bug, .steel]
        map[590] = [.grass, .poison]
        map[591] = [.grass, .poison]
        map[592] = [.water, .ghost]
        map[593] = [.water, .ghost]
        map[594] = [.water]
        map[595] = [.bug, .electric]
        map[596] = [.bug, .electric]
        map[597] = [.grass, .steel]
        map[598] = [.grass, .steel]
        map[599] = [.steel]
        map[600] = [.steel]
        map[601] = [.steel]
        map[602] = [.electric]
        map[603] = [.electric]
        map[604] = [.electric]
        map[605] = [.psychic]
        map[606] = [.psychic]
        map[607] = [.ghost, .fire]
        map[608] = [.ghost, .fire]
        map[609] = [.ghost, .fire]
        map[610] = [.dragon]
        map[611] = [.dragon]
        map[612] = [.dragon]
        map[613] = [.ice]
        map[614] = [.ice]
        map[615] = [.ice]
        map[616] = [.bug]
        map[617] = [.bug]
        map[618] = [.ground, .electric]
        map[619] = [.fighting]
        map[620] = [.fighting]
        map[621] = [.dragon]
        map[622] = [.ground, .ghost]
        map[623] = [.ground, .ghost]
        map[624] = [.dark, .steel]
        map[625] = [.dark, .steel]
        map[626] = [.normal]
        map[627] = [.normal, .flying]
        map[628] = [.normal, .flying]
        map[629] = [.dark, .flying]
        map[630] = [.dark, .flying]
        map[631] = [.fire]
        map[632] = [.bug, .steel]
        map[633] = [.dark, .dragon]
        map[634] = [.dark, .dragon]
        map[635] = [.dark, .dragon]
        map[636] = [.bug, .fire]
        map[637] = [.bug, .fire]
        map[638] = [.steel, .fighting]
        map[639] = [.rock, .fighting]
        map[640] = [.grass, .fighting]
        map[641] = [.flying]
        map[642] = [.electric, .flying]
        map[643] = [.dragon, .fire]
        map[644] = [.dragon, .electric]
        map[645] = [.ground, .flying]
        map[646] = [.dragon, .ice]
        map[647] = [.water, .fighting]
        map[648] = [.normal, .psychic]
        map[649] = [.bug, .steel]
        return map
    }()

    /// 타입별 속한 종 ID 집합.
    public static let speciesByType: [PokemonType: Set<Int>] = {
        var map: [PokemonType: Set<Int>] = [:]
        map[.normal] = Set([16, 17, 18, 19, 20, 21, 22, 39, 40, 52, 53, 83, 84, 85, 108, 113, 115, 128, 132, 133, 137, 143, 161, 162, 163, 164, 174, 190, 203, 206, 216, 217, 233, 234, 235, 241, 242, 263, 264, 276, 277, 287, 288, 289, 293, 294, 295, 298, 300, 301, 327, 333, 335, 351, 352, 396, 397, 398, 399, 400, 424, 427, 428, 431, 432, 440, 441, 446, 463, 474, 486, 493, 504, 505, 506, 507, 508, 519, 520, 521, 531, 572, 573, 585, 586, 626, 627, 628, 648])
        map[.fire] = Set([4, 5, 6, 37, 38, 58, 59, 77, 78, 126, 136, 146, 155, 156, 157, 218, 219, 228, 229, 240, 244, 250, 255, 256, 257, 322, 323, 324, 390, 391, 392, 467, 485, 494, 498, 499, 500, 513, 514, 554, 555, 607, 608, 609, 631, 636, 637, 643])
        map[.water] = Set([7, 8, 9, 54, 55, 60, 61, 62, 72, 73, 79, 80, 86, 87, 90, 91, 98, 99, 116, 117, 118, 119, 120, 121, 129, 130, 131, 134, 138, 139, 140, 141, 158, 159, 160, 170, 171, 183, 184, 186, 194, 195, 199, 211, 222, 223, 224, 226, 230, 245, 258, 259, 260, 270, 271, 272, 278, 279, 283, 318, 319, 320, 321, 339, 340, 341, 342, 349, 350, 363, 364, 365, 366, 367, 368, 369, 370, 382, 393, 394, 395, 400, 418, 419, 422, 423, 456, 457, 458, 484, 489, 490, 501, 502, 503, 515, 516, 535, 536, 537, 550, 564, 565, 580, 581, 592, 593, 594, 647])
        map[.grass] = Set([1, 2, 3, 43, 44, 45, 46, 47, 69, 70, 71, 102, 103, 114, 152, 153, 154, 182, 187, 188, 189, 191, 192, 251, 252, 253, 254, 270, 271, 272, 273, 274, 275, 285, 286, 315, 331, 332, 345, 346, 357, 387, 388, 389, 406, 407, 413, 420, 421, 455, 459, 460, 465, 470, 492, 495, 496, 497, 511, 512, 540, 541, 542, 546, 547, 548, 549, 556, 585, 586, 590, 591, 597, 598, 640])
        map[.electric] = Set([25, 26, 81, 82, 100, 101, 125, 135, 145, 170, 171, 172, 179, 180, 181, 239, 243, 309, 310, 311, 312, 403, 404, 405, 417, 462, 466, 479, 522, 523, 587, 595, 596, 602, 603, 604, 618, 642, 644])
        map[.ice] = Set([87, 91, 124, 131, 144, 215, 220, 221, 225, 238, 361, 362, 363, 364, 365, 378, 459, 460, 461, 471, 473, 478, 582, 583, 584, 613, 614, 615, 646])
        map[.fighting] = Set([56, 57, 62, 66, 67, 68, 106, 107, 214, 236, 237, 256, 257, 286, 296, 297, 307, 308, 391, 392, 447, 448, 453, 454, 475, 499, 500, 532, 533, 534, 538, 539, 559, 560, 619, 620, 638, 639, 640, 647])
        map[.poison] = Set([1, 2, 3, 13, 14, 15, 23, 24, 29, 30, 31, 32, 33, 34, 41, 42, 43, 44, 45, 48, 49, 69, 70, 71, 72, 73, 88, 89, 92, 93, 94, 109, 110, 167, 168, 169, 211, 269, 315, 316, 317, 336, 406, 407, 434, 435, 451, 452, 453, 454, 543, 544, 545, 568, 569, 590, 591])
        map[.ground] = Set([27, 28, 31, 34, 50, 51, 74, 75, 76, 95, 104, 105, 111, 112, 194, 195, 207, 208, 220, 221, 231, 232, 246, 247, 259, 260, 290, 322, 323, 328, 329, 330, 339, 340, 343, 344, 383, 389, 423, 443, 444, 445, 449, 450, 464, 472, 473, 529, 530, 536, 537, 551, 552, 553, 618, 622, 623, 645])
        map[.flying] = Set([6, 12, 16, 17, 18, 21, 22, 41, 42, 83, 84, 85, 123, 130, 142, 144, 145, 146, 149, 163, 164, 165, 166, 169, 176, 177, 178, 187, 188, 189, 193, 198, 207, 225, 226, 227, 249, 250, 267, 276, 277, 278, 279, 284, 291, 333, 334, 357, 373, 384, 396, 397, 398, 414, 415, 416, 425, 426, 430, 441, 458, 468, 469, 472, 519, 520, 521, 527, 528, 561, 566, 567, 580, 581, 587, 627, 628, 629, 630, 641, 642, 645])
        map[.psychic] = Set([63, 64, 65, 79, 80, 96, 97, 102, 103, 121, 122, 124, 150, 151, 177, 178, 196, 199, 201, 202, 203, 238, 249, 251, 280, 281, 282, 307, 308, 325, 326, 337, 338, 343, 344, 358, 360, 374, 375, 376, 380, 381, 385, 386, 433, 436, 437, 439, 475, 480, 481, 482, 488, 494, 517, 518, 527, 528, 561, 574, 575, 576, 577, 578, 579, 605, 606, 648])
        map[.bug] = Set([10, 11, 12, 13, 14, 15, 46, 47, 48, 49, 123, 127, 165, 166, 167, 168, 193, 204, 205, 212, 213, 214, 265, 266, 267, 268, 269, 283, 284, 290, 291, 292, 313, 314, 347, 348, 401, 402, 412, 413, 414, 415, 416, 451, 469, 540, 541, 542, 543, 544, 545, 557, 558, 588, 589, 595, 596, 616, 617, 632, 636, 637, 649])
        map[.rock] = Set([74, 75, 76, 95, 111, 112, 138, 139, 140, 141, 142, 185, 213, 219, 222, 246, 247, 248, 299, 304, 305, 306, 337, 338, 345, 346, 347, 348, 369, 377, 408, 409, 410, 411, 438, 464, 476, 524, 525, 526, 557, 558, 564, 565, 566, 567, 639])
        map[.ghost] = Set([92, 93, 94, 200, 292, 302, 353, 354, 355, 356, 425, 426, 429, 442, 477, 478, 479, 487, 562, 563, 592, 593, 607, 608, 609, 622, 623])
        map[.dragon] = Set([147, 148, 149, 230, 329, 330, 334, 371, 372, 373, 380, 381, 384, 443, 444, 445, 483, 484, 487, 610, 611, 612, 621, 633, 634, 635, 643, 644, 646])
        map[.steel] = Set([81, 82, 205, 208, 212, 227, 303, 304, 305, 306, 374, 375, 376, 379, 385, 395, 410, 411, 436, 437, 448, 462, 476, 483, 485, 530, 589, 597, 598, 599, 600, 601, 624, 625, 632, 638, 649])
        map[.dark] = Set([197, 198, 215, 228, 229, 248, 261, 262, 274, 275, 302, 318, 319, 332, 342, 359, 430, 434, 435, 442, 452, 461, 491, 509, 510, 551, 552, 553, 559, 560, 570, 571, 624, 625, 629, 630, 633, 634, 635])
        map[.fairy] = Set([35, 36, 39, 40, 122, 173, 174, 175, 176, 183, 184, 209, 210, 280, 281, 282, 298, 303, 439, 468, 546, 547])
        return map
    }()

    /// 특정 종 ID 의 타입 목록 반환.
    public static func types(forSpeciesID id: Int) -> [PokemonType] {
        speciesToTypes[id] ?? []
    }

    /// 특정 타입에 속하는 종 ID 집합 반환.
    public static func species(for type: PokemonType) -> Set<Int> {
        speciesByType[type] ?? []
    }

    /// 공격 타입이 방어 타입에 가하는 단일 타입 상성 배율.
    public static func effectiveness(attacking: PokemonType, defending: PokemonType) -> Double {
        switch attacking {
        case .normal:
            switch defending {
            case .rock: return 0.5
            case .ghost: return 0.0
            case .steel: return 0.5
            default: return 1.0
            }
        case .fire:
            switch defending {
            case .fire: return 0.5
            case .water: return 0.5
            case .grass: return 2.0
            case .ice: return 2.0
            case .bug: return 2.0
            case .rock: return 0.5
            case .dragon: return 0.5
            case .steel: return 2.0
            default: return 1.0
            }
        case .water:
            switch defending {
            case .fire: return 2.0
            case .water: return 0.5
            case .grass: return 0.5
            case .ground: return 2.0
            case .rock: return 2.0
            case .dragon: return 0.5
            default: return 1.0
            }
        case .grass:
            switch defending {
            case .fire: return 0.5
            case .water: return 2.0
            case .grass: return 0.5
            case .poison: return 0.5
            case .ground: return 2.0
            case .flying: return 0.5
            case .bug: return 0.5
            case .rock: return 2.0
            case .dragon: return 0.5
            case .steel: return 0.5
            default: return 1.0
            }
        case .electric:
            switch defending {
            case .water: return 2.0
            case .grass: return 0.5
            case .electric: return 0.5
            case .ground: return 0.0
            case .flying: return 2.0
            case .dragon: return 0.5
            default: return 1.0
            }
        case .ice:
            switch defending {
            case .fire: return 0.5
            case .water: return 0.5
            case .grass: return 2.0
            case .ice: return 0.5
            case .ground: return 2.0
            case .flying: return 2.0
            case .dragon: return 2.0
            case .steel: return 0.5
            default: return 1.0
            }
        case .fighting:
            switch defending {
            case .normal: return 2.0
            case .ice: return 2.0
            case .poison: return 0.5
            case .flying: return 0.5
            case .psychic: return 0.5
            case .bug: return 0.5
            case .rock: return 2.0
            case .ghost: return 0.0
            case .steel: return 2.0
            case .dark: return 2.0
            case .fairy: return 0.5
            default: return 1.0
            }
        case .poison:
            switch defending {
            case .grass: return 2.0
            case .poison: return 0.5
            case .ground: return 0.5
            case .rock: return 0.5
            case .ghost: return 0.5
            case .steel: return 0.0
            case .fairy: return 2.0
            default: return 1.0
            }
        case .ground:
            switch defending {
            case .fire: return 2.0
            case .grass: return 0.5
            case .electric: return 2.0
            case .poison: return 2.0
            case .flying: return 0.0
            case .bug: return 0.5
            case .rock: return 2.0
            case .steel: return 2.0
            default: return 1.0
            }
        case .flying:
            switch defending {
            case .grass: return 2.0
            case .electric: return 0.5
            case .fighting: return 2.0
            case .bug: return 2.0
            case .rock: return 0.5
            case .steel: return 0.5
            default: return 1.0
            }
        case .psychic:
            switch defending {
            case .fighting: return 2.0
            case .poison: return 2.0
            case .psychic: return 0.5
            case .steel: return 0.5
            case .dark: return 0.0
            default: return 1.0
            }
        case .bug:
            switch defending {
            case .fire: return 0.5
            case .grass: return 2.0
            case .fighting: return 0.5
            case .poison: return 0.5
            case .flying: return 0.5
            case .psychic: return 2.0
            case .ghost: return 0.5
            case .steel: return 0.5
            case .dark: return 2.0
            case .fairy: return 0.5
            default: return 1.0
            }
        case .rock:
            switch defending {
            case .fire: return 2.0
            case .ice: return 2.0
            case .fighting: return 0.5
            case .ground: return 0.5
            case .flying: return 2.0
            case .bug: return 2.0
            case .steel: return 0.5
            default: return 1.0
            }
        case .ghost:
            switch defending {
            case .normal: return 0.0
            case .psychic: return 2.0
            case .ghost: return 2.0
            case .dark: return 0.5
            default: return 1.0
            }
        case .dragon:
            switch defending {
            case .dragon: return 2.0
            case .steel: return 0.5
            case .fairy: return 0.0
            default: return 1.0
            }
        case .steel:
            switch defending {
            case .fire: return 0.5
            case .water: return 0.5
            case .electric: return 0.5
            case .ice: return 2.0
            case .rock: return 2.0
            case .steel: return 0.5
            case .fairy: return 2.0
            default: return 1.0
            }
        case .dark:
            switch defending {
            case .fighting: return 0.5
            case .psychic: return 2.0
            case .ghost: return 2.0
            case .dark: return 0.5
            case .fairy: return 0.5
            default: return 1.0
            }
        case .fairy:
            switch defending {
            case .fire: return 0.5
            case .fighting: return 2.0
            case .poison: return 0.5
            case .dragon: return 2.0
            case .steel: return 0.5
            case .dark: return 2.0
            default: return 1.0
            }
        }
    }

    /// 공격 타입이 특정 종 ID(복합 타입 반영)에 가하는 최종 상성 배율.
    public static func effectiveness(attacking: PokemonType, speciesID: Int) -> Double {
        let defTypes = types(forSpeciesID: speciesID)
        guard !defTypes.isEmpty else { return 1.0 }
        return defTypes.reduce(1.0) { $0 * effectiveness(attacking: attacking, defending: $1) }
    }

    /// 특정 종이 공격 타입(배지)에 약한지(상성 배율 > 1.0) 판정.
    /// 노말 배지는 방어 상성 약점이 존재하지 않으므로 노말 타입 종에게 상시 유효.
    public static func isWeak(to attacking: PokemonType, speciesID: Int) -> Bool {
        if attacking == .normal {
            return types(forSpeciesID: speciesID).contains(.normal)
        }
        return effectiveness(attacking: attacking, speciesID: speciesID) > 1.0
    }
}
