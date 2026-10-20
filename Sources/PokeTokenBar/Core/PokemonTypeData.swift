import Foundation

/// Gym badge of each type (`PokemonType` itself lives in UI/Badge.swift with the type colors).
extension PokemonType {
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

    /// PokéAPI 배지 스프라이트 파일명 (sprites/badges/{id}.png).
    var badgeSpriteName: String {
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

/// 1~9세대(#1~#1025) 포켓몬 타입(PokéAPI 기본 폼) 및 상성 데이터.
enum PokemonTypeData {
    /// 종 ID 별 타입 목록. 부화 가능한 종(`PokemonAssets.animatedSpeciesIDs`)을 모두 덮어야 한다:
    /// 빠진 종은 타입 보증 알에서 나오지 않고 배지·백금옥 효과도 받지 못한다.
    static let speciesToTypes: [Int: [PokemonType]] = {
        var map: [Int: [PokemonType]] = [:]
        map.reserveCapacity(1026)
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
        map[650] = [.grass]
        map[651] = [.grass]
        map[652] = [.grass, .fighting]
        map[653] = [.fire]
        map[654] = [.fire]
        map[655] = [.fire, .psychic]
        map[656] = [.water]
        map[657] = [.water]
        map[658] = [.water, .dark]
        map[659] = [.normal]
        map[660] = [.normal, .ground]
        map[661] = [.normal, .flying]
        map[662] = [.fire, .flying]
        map[663] = [.fire, .flying]
        map[664] = [.bug]
        map[665] = [.bug]
        map[666] = [.bug, .flying]
        map[667] = [.fire, .normal]
        map[668] = [.fire, .normal]
        map[669] = [.fairy]
        map[670] = [.fairy]
        map[671] = [.fairy]
        map[672] = [.grass]
        map[673] = [.grass]
        map[674] = [.fighting]
        map[675] = [.fighting, .dark]
        map[676] = [.normal]
        map[677] = [.psychic]
        map[678] = [.psychic]
        map[679] = [.steel, .ghost]
        map[680] = [.steel, .ghost]
        map[681] = [.steel, .ghost]
        map[682] = [.fairy]
        map[683] = [.fairy]
        map[684] = [.fairy]
        map[685] = [.fairy]
        map[686] = [.dark, .psychic]
        map[687] = [.dark, .psychic]
        map[688] = [.rock, .water]
        map[689] = [.rock, .water]
        map[690] = [.poison, .water]
        map[691] = [.poison, .dragon]
        map[692] = [.water]
        map[693] = [.water]
        map[694] = [.electric, .normal]
        map[695] = [.electric, .normal]
        map[696] = [.rock, .dragon]
        map[697] = [.rock, .dragon]
        map[698] = [.rock, .ice]
        map[699] = [.rock, .ice]
        map[700] = [.fairy]
        map[701] = [.fighting, .flying]
        map[702] = [.electric, .fairy]
        map[703] = [.rock, .fairy]
        map[704] = [.dragon]
        map[705] = [.dragon]
        map[706] = [.dragon]
        map[707] = [.steel, .fairy]
        map[708] = [.ghost, .grass]
        map[709] = [.ghost, .grass]
        map[710] = [.ghost, .grass]
        map[711] = [.ghost, .grass]
        map[712] = [.ice]
        map[713] = [.ice]
        map[714] = [.flying, .dragon]
        map[715] = [.flying, .dragon]
        map[716] = [.fairy]
        map[717] = [.dark, .flying]
        map[718] = [.dragon, .ground]
        map[719] = [.rock, .fairy]
        map[720] = [.psychic, .ghost]
        map[721] = [.fire, .water]
        map[722] = [.grass, .flying]
        map[723] = [.grass, .flying]
        map[724] = [.grass, .ghost]
        map[725] = [.fire]
        map[726] = [.fire]
        map[727] = [.fire, .dark]
        map[728] = [.water]
        map[729] = [.water]
        map[730] = [.water, .fairy]
        map[731] = [.normal, .flying]
        map[732] = [.normal, .flying]
        map[733] = [.normal, .flying]
        map[734] = [.normal]
        map[735] = [.normal]
        map[736] = [.bug]
        map[737] = [.bug, .electric]
        map[738] = [.bug, .electric]
        map[739] = [.fighting]
        map[740] = [.fighting, .ice]
        map[741] = [.fire, .flying]
        map[742] = [.bug, .fairy]
        map[743] = [.bug, .fairy]
        map[744] = [.rock]
        map[745] = [.rock]
        map[746] = [.water]
        map[747] = [.poison, .water]
        map[748] = [.poison, .water]
        map[749] = [.ground]
        map[750] = [.ground]
        map[751] = [.water, .bug]
        map[752] = [.water, .bug]
        map[753] = [.grass]
        map[754] = [.grass]
        map[755] = [.grass, .fairy]
        map[756] = [.grass, .fairy]
        map[757] = [.poison, .fire]
        map[758] = [.poison, .fire]
        map[759] = [.normal, .fighting]
        map[760] = [.normal, .fighting]
        map[761] = [.grass]
        map[762] = [.grass]
        map[763] = [.grass]
        map[764] = [.fairy]
        map[765] = [.normal, .psychic]
        map[766] = [.fighting]
        map[767] = [.bug, .water]
        map[768] = [.bug, .water]
        map[769] = [.ghost, .ground]
        map[770] = [.ghost, .ground]
        map[771] = [.water]
        map[772] = [.normal]
        map[773] = [.normal]
        map[774] = [.rock, .flying]
        map[775] = [.normal]
        map[776] = [.fire, .dragon]
        map[777] = [.electric, .steel]
        map[778] = [.ghost, .fairy]
        map[779] = [.water, .psychic]
        map[780] = [.normal, .dragon]
        map[781] = [.ghost, .grass]
        map[782] = [.dragon]
        map[783] = [.dragon, .fighting]
        map[784] = [.dragon, .fighting]
        map[785] = [.electric, .fairy]
        map[786] = [.psychic, .fairy]
        map[787] = [.grass, .fairy]
        map[788] = [.water, .fairy]
        map[789] = [.psychic]
        map[790] = [.psychic]
        map[791] = [.psychic, .steel]
        map[792] = [.psychic, .ghost]
        map[793] = [.rock, .poison]
        map[794] = [.bug, .fighting]
        map[795] = [.bug, .fighting]
        map[796] = [.electric]
        map[797] = [.steel, .flying]
        map[798] = [.grass, .steel]
        map[799] = [.dark, .dragon]
        map[800] = [.psychic]
        map[801] = [.steel, .fairy]
        map[802] = [.fighting, .ghost]
        map[803] = [.poison]
        map[804] = [.poison, .dragon]
        map[805] = [.rock, .steel]
        map[806] = [.fire, .ghost]
        map[807] = [.electric]
        map[808] = [.steel]
        map[809] = [.steel]
        map[810] = [.grass]
        map[811] = [.grass]
        map[812] = [.grass]
        map[813] = [.fire]
        map[814] = [.fire]
        map[815] = [.fire]
        map[816] = [.water]
        map[817] = [.water]
        map[818] = [.water]
        map[819] = [.normal]
        map[820] = [.normal]
        map[821] = [.flying]
        map[822] = [.flying]
        map[823] = [.flying, .steel]
        map[824] = [.bug]
        map[825] = [.bug, .psychic]
        map[826] = [.bug, .psychic]
        map[827] = [.dark]
        map[828] = [.dark]
        map[829] = [.grass]
        map[830] = [.grass]
        map[831] = [.normal]
        map[832] = [.normal]
        map[833] = [.water]
        map[834] = [.water, .rock]
        map[835] = [.electric]
        map[836] = [.electric]
        map[837] = [.rock]
        map[838] = [.rock, .fire]
        map[839] = [.rock, .fire]
        map[840] = [.grass, .dragon]
        map[841] = [.grass, .dragon]
        map[842] = [.grass, .dragon]
        map[843] = [.ground]
        map[844] = [.ground]
        map[845] = [.flying, .water]
        map[846] = [.water]
        map[847] = [.water]
        map[848] = [.electric, .poison]
        map[849] = [.electric, .poison]
        map[850] = [.fire, .bug]
        map[851] = [.fire, .bug]
        map[852] = [.fighting]
        map[853] = [.fighting]
        map[854] = [.ghost]
        map[855] = [.ghost]
        map[856] = [.psychic]
        map[857] = [.psychic]
        map[858] = [.psychic, .fairy]
        map[859] = [.dark, .fairy]
        map[860] = [.dark, .fairy]
        map[861] = [.dark, .fairy]
        map[862] = [.dark, .normal]
        map[863] = [.steel]
        map[864] = [.ghost]
        map[865] = [.fighting]
        map[866] = [.ice, .psychic]
        map[867] = [.ground, .ghost]
        map[868] = [.fairy]
        map[869] = [.fairy]
        map[870] = [.fighting]
        map[871] = [.electric]
        map[872] = [.ice, .bug]
        map[873] = [.ice, .bug]
        map[874] = [.rock]
        map[875] = [.ice]
        map[876] = [.psychic, .normal]
        map[877] = [.electric, .dark]
        map[878] = [.steel]
        map[879] = [.steel]
        map[880] = [.electric, .dragon]
        map[881] = [.electric, .ice]
        map[882] = [.water, .dragon]
        map[883] = [.water, .ice]
        map[884] = [.steel, .dragon]
        map[885] = [.dragon, .ghost]
        map[886] = [.dragon, .ghost]
        map[887] = [.dragon, .ghost]
        map[888] = [.fairy]
        map[889] = [.fighting]
        map[890] = [.poison, .dragon]
        map[891] = [.fighting]
        map[892] = [.fighting, .dark]
        map[893] = [.dark, .grass]
        map[894] = [.electric]
        map[895] = [.dragon]
        map[896] = [.ice]
        map[897] = [.ghost]
        map[898] = [.psychic, .grass]
        map[899] = [.normal, .psychic]
        map[900] = [.bug, .rock]
        map[901] = [.ground, .normal]
        map[902] = [.water, .ghost]
        map[903] = [.fighting, .poison]
        map[904] = [.dark, .poison]
        map[905] = [.fairy, .flying]
        map[906] = [.grass]
        map[907] = [.grass]
        map[908] = [.grass, .dark]
        map[909] = [.fire]
        map[910] = [.fire]
        map[911] = [.fire, .ghost]
        map[912] = [.water]
        map[913] = [.water]
        map[914] = [.water, .fighting]
        map[915] = [.normal]
        map[916] = [.normal]
        map[917] = [.bug]
        map[918] = [.bug]
        map[919] = [.bug]
        map[920] = [.bug, .dark]
        map[921] = [.electric]
        map[922] = [.electric, .fighting]
        map[923] = [.electric, .fighting]
        map[924] = [.normal]
        map[925] = [.normal]
        map[926] = [.fairy]
        map[927] = [.fairy]
        map[928] = [.grass, .normal]
        map[929] = [.grass, .normal]
        map[930] = [.grass, .normal]
        map[931] = [.normal, .flying]
        map[932] = [.rock]
        map[933] = [.rock]
        map[934] = [.rock]
        map[935] = [.fire]
        map[936] = [.fire, .psychic]
        map[937] = [.fire, .ghost]
        map[938] = [.electric]
        map[939] = [.electric]
        map[940] = [.electric, .flying]
        map[941] = [.electric, .flying]
        map[942] = [.dark]
        map[943] = [.dark]
        map[944] = [.poison, .normal]
        map[945] = [.poison, .normal]
        map[946] = [.grass, .ghost]
        map[947] = [.grass, .ghost]
        map[948] = [.ground, .grass]
        map[949] = [.ground, .grass]
        map[950] = [.rock]
        map[951] = [.grass]
        map[952] = [.grass, .fire]
        map[953] = [.bug]
        map[954] = [.bug, .psychic]
        map[955] = [.psychic]
        map[956] = [.psychic]
        map[957] = [.fairy, .steel]
        map[958] = [.fairy, .steel]
        map[959] = [.fairy, .steel]
        map[960] = [.water]
        map[961] = [.water]
        map[962] = [.flying, .dark]
        map[963] = [.water]
        map[964] = [.water]
        map[965] = [.steel, .poison]
        map[966] = [.steel, .poison]
        map[967] = [.dragon, .normal]
        map[968] = [.steel]
        map[969] = [.rock, .poison]
        map[970] = [.rock, .poison]
        map[971] = [.ghost]
        map[972] = [.ghost]
        map[973] = [.flying, .fighting]
        map[974] = [.ice]
        map[975] = [.ice]
        map[976] = [.water, .psychic]
        map[977] = [.water]
        map[978] = [.dragon, .water]
        map[979] = [.fighting, .ghost]
        map[980] = [.poison, .ground]
        map[981] = [.normal, .psychic]
        map[982] = [.normal]
        map[983] = [.dark, .steel]
        map[984] = [.ground, .fighting]
        map[985] = [.fairy, .psychic]
        map[986] = [.grass, .dark]
        map[987] = [.ghost, .fairy]
        map[988] = [.bug, .fighting]
        map[989] = [.electric, .ground]
        map[990] = [.ground, .steel]
        map[991] = [.ice, .water]
        map[992] = [.fighting, .electric]
        map[993] = [.dark, .flying]
        map[994] = [.fire, .poison]
        map[995] = [.rock, .electric]
        map[996] = [.dragon, .ice]
        map[997] = [.dragon, .ice]
        map[998] = [.dragon, .ice]
        map[999] = [.ghost]
        map[1000] = [.steel, .ghost]
        map[1001] = [.dark, .grass]
        map[1002] = [.dark, .ice]
        map[1003] = [.dark, .ground]
        map[1004] = [.dark, .fire]
        map[1005] = [.dragon, .dark]
        map[1006] = [.fairy, .fighting]
        map[1007] = [.fighting, .dragon]
        map[1008] = [.electric, .dragon]
        map[1009] = [.water, .dragon]
        map[1010] = [.grass, .psychic]
        map[1011] = [.grass, .dragon]
        map[1012] = [.grass, .ghost]
        map[1013] = [.grass, .ghost]
        map[1014] = [.poison, .fighting]
        map[1015] = [.poison, .psychic]
        map[1016] = [.poison, .fairy]
        map[1017] = [.grass]
        map[1018] = [.steel, .dragon]
        map[1019] = [.grass, .dragon]
        map[1020] = [.fire, .dragon]
        map[1021] = [.electric, .dragon]
        map[1022] = [.rock, .psychic]
        map[1023] = [.steel, .psychic]
        map[1024] = [.normal]
        map[1025] = [.poison, .ghost]
        return map
    }()

    /// 타입별 속한 종 ID 집합. `speciesToTypes` 에서 파생해 두 표가 어긋날 수 없게 한다.
    static let speciesByType: [PokemonType: Set<Int>] = speciesToTypes.reduce(into: [:]) { map, entry in
        for type in entry.value { map[type, default: []].insert(entry.key) }
    }

    /// 특정 종 ID 의 타입 목록 반환.
    static func types(forSpeciesID id: Int) -> [PokemonType] {
        speciesToTypes[id] ?? []
    }

    /// 특정 타입에 속하는 종 ID 집합 반환.
    static func species(for type: PokemonType) -> Set<Int> {
        speciesByType[type] ?? []
    }

    /// Gym badges ask for the Gen 1 to 5 Pokémon of their type only, whatever generations hatch.
    static let badgeSpeciesIDs = 1...649

    /// Species a type's gym badge asks for.
    static func badgeSpecies(for type: PokemonType) -> [Int] {
        species(for: type).filter { badgeSpeciesIDs.contains($0) }.sorted()
    }

    /// 공격 타입이 방어 타입에 가하는 단일 타입 상성 배율.
    static func effectiveness(attacking: PokemonType, defending: PokemonType) -> Double {
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
    static func effectiveness(attacking: PokemonType, speciesID: Int) -> Double {
        let defTypes = types(forSpeciesID: speciesID)
        guard !defTypes.isEmpty else { return 1.0 }
        return defTypes.reduce(1.0) { $0 * effectiveness(attacking: attacking, defending: $1) }
    }

    /// 특정 종이 공격 타입(배지)에 약한지(상성 배율 > 1.0) 판정.
    /// 노말 배지는 방어 상성 약점이 존재하지 않으므로 노말 타입 종에게 상시 유효.
    static func isWeak(to attacking: PokemonType, speciesID: Int) -> Bool {
        if attacking == .normal {
            return types(forSpeciesID: speciesID).contains(.normal)
        }
        return effectiveness(attacking: attacking, speciesID: speciesID) > 1.0
    }
}
