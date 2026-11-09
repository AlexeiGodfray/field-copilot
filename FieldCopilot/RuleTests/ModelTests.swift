// Model-number lookup tests. Every real model number below comes from a manufacturer document,
// ENERGY STAR listing or the labels in this project (sources are listed in each ModelRules file).
// Each must match exactly one rule; the look-alikes from other makers must match none.

var modelFailures = 0

func expectModel(_ model: String, _ manufacturer: String?, _ kind: EquipmentKind? = nil,
                 brands: [String]? = nil, size: String? = nil) {
    let matches = ModelLookup.allMatches(model)
    var problems: [String] = []
    if let manufacturer {
        if matches.count != 1 { problems.append("\(matches.count) rules matched") }
        if let m = matches.first {
            if m.manufacturer != manufacturer { problems.append("maker \(m.manufacturer)") }
            if let kind, m.kind != kind { problems.append("type \(m.kind?.displayName ?? "none")") }
            if let brands, m.brands != brands { problems.append("brands \(m.brands)") }
            if let size, !(m.size ?? "").contains(size) { problems.append("size \(m.size ?? "none")") }
        }
    } else if !matches.isEmpty {
        problems.append("look-alike matched \(matches.map(\.manufacturer))")
    }
    if !problems.isEmpty {
        modelFailures += 1
        print("FAIL  \(model): \(problems.joined(separator: ", "))")
    }
}

func runModelTests() {
    let ac = EquipmentKind.airConditioner, hp = EquipmentKind.heatPump, furnace = EquipmentKind.furnace
    let ah = EquipmentKind.airHandler, coil = EquipmentKind.evaporatorCoil, pkg = EquipmentKind.packagedUnit
    let wh = EquipmentKind.waterHeater

    // ICP
    expectModel("R4A442GKB100", "ICP", ac, brands: ModelLookup.icpBrands, size: "3.5 tons")
    expectModel("N4A442GKB100", "ICP", ac, brands: ModelLookup.icpBrands)
    expectModel("T4A436AKB100", "ICP", ac, brands: ["Tempstar"])
    expectModel("H4H424AKB100", "ICP", hp, brands: ["Heil", "Arcoaire", "Airquest"])
    expectModel("C4A360AKB100", "ICP", ac, brands: ["Comfortmaker", "Day & Night", "KeepRite"])
    expectModel("TCA724GKA100", "ICP", ac, brands: ["Tempstar"])
    expectModel("R4A5S42AKAWA", "ICP", ac)
    // SEER2 heat pumps as printed (distributor listings) and ENERGY STAR's B and W letters.
    expectModel("N5H5S24AKAAA", "ICP", hp, brands: ModelLookup.icpBrands, size: "2 tons")
    expectModel("B5H0V24AKAAA", "ICP", hp, brands: ModelLookup.icpBrands)
    expectModel("W4H5S30AKAAA", "ICP", hp, brands: ["Grandaire", "Ecotemp"])
    expectModel("G96VTN0801714A", "ICP", furnace)
    // Capacity code 31 is 2½ tons (Heil catalog 401 12 2300 18); the model number is from a parts listing.
    expectModel("R4H331GKB100", "ICP", hp, size: "2.5 tons")

    // Carrier, Bryant, Payne
    expectModel("24ACA336A300", "Carrier", ac, brands: ["Carrier"], size: "3 tons")
    expectModel("24ACA336A0030010", "Carrier", ac)
    for m in ["24ACC636A0030", "26SCA448N013"] { expectModel(m, "Carrier", ac) }
    for m in ["25HCC536A0031", "25HCE436A0030", "25SCA518A003", "27VNA036A0030"] { expectModel(m, "Carrier", hp) }
    expectModel("27SCA560A003", "Carrier", hp, size: "5 tons · R-454B")
    expectModel("38TKB018331", "Carrier", ac, size: "1.5 tons")
    expectModel("38YCC036", "Carrier", hp, size: "3 tons")
    for m in ["59SC6A040M14--10", "59TP6C060V17--16", "58CTA045"] { expectModel(m, "Carrier", furnace) }
    expectModel("FE4ANB006", "Carrier", ah, size: "3–5 tons")
    expectModel("FB4CNF024000", "Carrier", ah, size: "2 tons")
    expectModel("FJ5ANXB24L00", "Carrier", ah)
    expectModel("CNWVP1814ALA", "Carrier", coil, size: "1.5 tons")
    expectModel("CVAVA3617XMA", "Carrier", coil, size: "3 tons")
    for m in ["113ANA036BN0", "113APA030000", "134SAN03600N", "597CNX018"] { expectModel(m, "Carrier", ac, brands: ["Bryant"]) }
    for m in ["246SAN01800A", "248TAN03600A", "284ANV0360000B", "661CJX018"] { expectModel(m, "Carrier", hp, brands: ["Bryant"]) }
    for m in ["916SA36040M14", "987MC42060C17"] { expectModel(m, "Carrier", furnace, brands: ["Bryant"]) }
    for m in ["577EEWK360000A", "607ENXK24000AA"] { expectModel(m, "Carrier", pkg, brands: ["Bryant"]) }
    // Older packaged units are numbered like the split units of the time (California's archive).
    for m in ["577BNW024040", "589ANW042100", "674ANW030040", "564ABX060"] {
        expectModel(m, "Carrier", pkg, brands: ["Bryant", "Payne", "Day & Night"])
    }
    expectModel("519DXX018", nil)  // a coil, not an air conditioner
    expectModel("4TCA4060A1", "Trane", pkg)  // packaged, not a cold-climate heat pump
    // DOE lists Bryant's 61x as indoor units, and 6-40-HBDS is a Reliance water heater.
    for m in ["619PEQ030BBMA", "615AHAQ24XA3", "640HBDS301"] { expectModel(m, nil) }
    // Other makers' models that read like Carrier's or a water heater's (California's archive): a Reliance water
    // heater, Allied Air's Magic-Pak and Armstrong's packaged units, and Smith Cast Iron's steam boilers.
    for m in ["6 50 MDV0 250", "26HWC124A", "PGE10124D050A", "GSX-88-CON", "GSX-118-INT"] { expectModel(m, nil) }
    expectModel("PA4SAN51800N", "Carrier", ac, brands: ["Payne"], size: "1.5 tons")
    expectModel("PA4SAP53600N", "Carrier", ac, brands: ["Payne"])
    expectModel("PH5SAN54800A", "Carrier", hp, brands: ["Payne"], size: "4 tons")
    expectModel("GH5SAN41800A", "Carrier", hp, brands: ["Carrier", "Bryant"])
    expectModel("PA13NA036000", "Carrier", ac, brands: ["Payne"])
    for m in ["PG96MSAA36040B", "PG8MVA036070"] { expectModel(m, "Carrier", furnace, brands: ["Payne", "WeatherMaker", "Brock"]) }
    expectModel("PG97VTAA48080B", "Carrier", furnace, size: "about 97% AFUE")
    expectModel("PF4MNA018", "Carrier", ah, brands: ["Payne"])

    // Lennox and Allied
    expectModel("13HPX-048-230-18", "Lennox", hp, size: "4 tons")
    for m in ["13HPX-024-230-2", "XP21-036-230-01", "EL16KP1-036-230A01", "EL18KSLV-024-230A01", "ML14KP1-048-463A01"] {
        expectModel(m, "Lennox", hp)
    }
    for m in ["XC16-036-230-2", "ML13KC1-036-230A01", "ML13KC1-036-233A01", "SL25KCV-036-230A-1"] { expectModel(m, "Lennox", ac) }
    expectModel("ML14KP1-048-463A01", "Lennox", hp, brands: ["Lennox", "Allied Commercial", "GE"])
    expectModel("SL25KCV-036-230A-1", "Lennox", ac, brands: ["Lennox"])
    expectModel("HS26-060-1P", "Lennox", ac, size: "5 tons")
    // Model numbers from parts listings; the letters are from Lennox: a regional S (bulletin 210760) and an
    // expansion-valve V (data-tag guide p.5).
    expectModel("ML14XC1S036-230A-10", "Lennox", ac, size: "3 tons")
    expectModel("HS16-411V-3", "Lennox", ac, size: "3 tons")
    expectModel("HP19-511-1Y", "Lennox", hp, size: "4 tons")
    for m in ["ML180UH070XE36B", "SLP99UH070XV36BK", "EL297DF045XV36B"] { expectModel(m, "Lennox", furnace) }
    for m in ["CBX25UH-030-230-01", "CBX32MV-036-230-6-01", "CBK45UHET-036-230A-71"] { expectModel(m, "Lennox", ah) }
    expectModel("CBX25UH-030-230-01", "Lennox", ah, size: "2.5 tons · R-410A")
    // K doesn't settle an air handler's refrigerant: CBK45 is paired with R-410A and R-454B systems.
    if ModelLookup.lookup("CBK45UHET-036-230A-71")?.size != "3 tons" {
        modelFailures += 1
        print("FAIL  CBK45UHET-036-230A-71 shouldn't show a refrigerant: \(ModelLookup.lookup("CBK45UHET-036-230A-71")?.size ?? "nil")")
    }
    for m in ["CK40CT-36A-71", "CX35-36B"] { expectModel(m, "Lennox", coil, size: "3 tons") }
    expectModel("4SCU16LE136P-4A", "Allied Air", ac, size: "3 tons")
    for m in ["A7AC14F36P", "7AC14F36P"] { expectModel(m, "Allied Air", ac) }
    for m in ["4SHP17LE118P-4A", "7HP14F24P-4A", "A7CP21V24P-4A"] { expectModel(m, "Allied Air", hp) }
    expectModel("4SHP17LE118P-4A", "Allied Air", hp, brands: ["Armstrong Air", "AirEase", "Ducane", "Concord", "Allied"])
    expectModel("A7CP21V24P-4A", "Allied Air", hp, brands: ["Armstrong Air", "AirEase", "AC Pro"])

    // Goodman, Amana, Daikin
    let goodman = "Goodman"
    for m in ["GSX140361", "GSX140361KC", "GSXC180361B", "DSXC180361A", "GSXN403610A", "GSXN3N3610A", "GLXS5BA3610AA", "GXV9SA3610AA"] {
        expectModel(m, goodman, ac, brands: ["Goodman"])
    }
    expectModel("GSX140361", goodman, ac, size: "3 tons · 14 SEER")
    expectModel("GSX140421", goodman, ac, brands: ["Goodman"], size: "3.5 tons")
    for m in ["ASX140361AA", "AVXC200361AA", "ALZS5BA3610A"] { expectModel(m, goodman, nil, brands: ["Amana"]) }
    for m in ["GSZH503610A", "GSZC702410A", "GSZV903610A", "GLZS5BA2410A", "GZV6SA121MA"] { expectModel(m, goodman, hp, brands: ["Goodman"]) }
    expectModel("AZV9SA361CA", goodman, hp, brands: ["Amana"])
    for m in ["DZ14SA0361K", "DZ14SA0363AA", "DH5SEA3610AA", "DZ6VSA241EA", "DZ9VCA4810A"] { expectModel(m, goodman, hp, brands: ["Daikin"]) }
    expectModel("DX5SEA3610AA", goodman, ac, brands: ["Daikin"])
    for m in ["GPCM32431AA", "GPGM33608031AA", "GPHM53641A", "GPC1460M41A", "GPGM34808041", "GPCH36041"] { expectModel(m, goodman, pkg) }
    for m in ["GMVC960803BN", "GMVC960803BNB", "GMEC960803BN", "GMEC961005CNA", "GMH950453BX", "GM9S800403A", "GM9S960403AN", "GR9S960403AN", "GMS80453AN"] {
        expectModel(m, goodman, furnace, brands: ["Goodman"])
    }
    expectModel("GMEC960803BN", goodman, furnace, size: "80,000 BTU/h input · about 96% AFUE")
    for m in ["AMVC950905CXAC", "ARVT960403BN"] { expectModel(m, goodman, furnace, brands: ["Amana"]) }
    for m in ["DM96VC0603BN", "DR96SN0403AN", "DD97MC1005CN"] { expectModel(m, goodman, furnace, brands: ["Daikin"]) }
    for m in ["CAPFA2422B6", "CAPF3743C6", "CAUF1824A6AA", "CHPTA2426B4", "CHPT4860D4", "CAPEA1818B4"] { expectModel(m, goodman, coil) }
    expectModel("CAPF3743C6", goodman, coil, size: "3–3.5 tons")
    for m in ["ASPT37C14", "ARUF486016", "ARUF37C14", "AVPTC25B14BA", "AMST36BU1400", "AWST18SU1405", "AHVE24BP1300A", "ACSF18MN1605AA"] {
        expectModel(m, goodman, ah, brands: ["Goodman", "Amana", "Daikin"])
    }
    expectModel("DMVE48DP1400A", goodman, ah, brands: ["Daikin"])

    // Trane and American Standard
    let trane = "Trane"
    for m in ["4TTR4036L1000A", "5TTR5036A1000A"] { expectModel(m, trane, ac, brands: ["Trane"]) }
    expectModel("4TTR4036L1000A", trane, ac, size: "3 tons · R-410A")
    for m in ["4TWR5036G1000AA", "4TWV0X24A1", "4TWL9024A1", "5TWR5018A1", "5TCV0X36A1", "2TWB0036A1000A"] { expectModel(m, trane, hp, brands: ["Trane"]) }
    for m in ["2A6B3018A1", "4A6H3036C1000A", "5A6H5018A1", "5A5V0X36A1", "4A6V0X24A1"] { expectModel(m, trane, hp, brands: ["American Standard"]) }
    expectModel("4A7A6036E1", trane, ac, brands: ["American Standard"])
    expectModel("A5HP5036A1000A", trane, hp, brands: ["RunTru", "Ameristar"])
    expectModel("E4HL5024A1000A", trane, hp, brands: ["RunTru", "Ameristar", "Trane", "American Standard"])
    expectModel("N5HP5018A1", trane, hp, brands: ["Trane", "American Standard"])
    for m in ["5HPL5024A1", "5HCL5036B1"] { expectModel(m, trane, hp) }
    for m in ["5DCZ5024A1", "5WCZ5024A1", "4YCC3018A1040AB"] { expectModel(m, trane, pkg) }
    for m in ["AUD2B060ACV32B", "AUC1B060A9361A", "AUH1B040A9H21B", "AUHMB060ACV3VB", "ADH1B065A9H31B"] {
        expectModel(m, trane, furnace, brands: ["American Standard"])
    }
    expectModel("TUHMB060CCV3V", trane, furnace, brands: ["Trane"])
    for m in ["S9V2B040U3VSAB", "S9X2B060U4PSBB", "S8X1B060M4PSCB"] { expectModel(m, trane, furnace, brands: ["Trane", "American Standard"]) }
    expectModel("S9X2B060U4PSBB", trane, furnace, size: "about 96% AFUE")
    expectModel("S9B1B040D3PS", trane, furnace, size: "40,000 BTU/h input · about 92% AFUE")  // DOE certifies S9B1 at 92.1%
    expectModel("A951X040BU3S", trane, furnace, brands: ["RunTru", "Ameristar"])
    for m in ["TAM7A0C36H31SA", "TEM6A0B30H21", "TAMXB0C36V31", "5TAM5B01AC21SB", "5TEM9C02AC21SAA", "5TAMXD04AV31", "4TEE3F36A1000AA"] {
        expectModel(m, trane, ah)
    }
    for m in ["GAM5B0C42M31SA", "GAF2A0A36S31EE"] { expectModel(m, trane, ah, brands: ["Trane", "American Standard"]) }
    for m in ["4TXCB003DS3HCB", "5TXCB003AS3HCA", "2TXCB036AC3HCAA"] { expectModel(m, trane, coil) }

    // Rheem, Ruud and Rheem-built private labels
    let rheemOutdoor = ["Rheem", "Ruud", "Sure Comfort", "Russell", "Friedrich"]
    for m in ["RA1436AJ1NA", "RA1418AJ1NA", "RA14AZ24AJ1NA", "RA14AY36AC1NA", "RA14AY48AJ1NALHP", "RA1442AJ1NA"] {
        expectModel(m, "Rheem", ac, brands: rheemOutdoor)
    }
    expectModel("RA14AY36AC1NA", "Rheem", ac, size: "3 tons · R-454B")
    for m in ["RP14AZ36AJ2NA", "RP16AZ48AJ3CA", "RD16AY36AJVC"] { expectModel(m, "Rheem", hp, brands: rheemOutdoor) }
    expectModel("UA18AZ36AJVCA", "Rheem", ac, brands: ["Ruud"])
    expectModel("UP19AY48AJVCA", "Rheem", hp, brands: ["Ruud"])
    expectModel("WP14AZ24AJ2NA", "Rheem", hp, brands: ["WeatherKing", "Rheem", "Ruud", "Rheem Select", "Ruud Choice", "Fujitsu"])
    expectModel("SP15AZ48AJ2N", "Rheem", hp, brands: ["Sure Comfort", "Russell"])
    expectModel("MLP15AY18AJ2N", "Rheem", hp, brands: ["Mainline"])
    for m in ["RANL-018JAZ", "RAKA-024JAZ"] { expectModel(m, "Rheem", ac, brands: ["Rheem"]) }
    expectModel("RPNL-024JEZ", "Rheem", hp, brands: ["Rheem"])
    for m in ["UAKB-036JAZ", "UAPL-036JAZ"] { expectModel(m, "Rheem", ac, brands: ["Ruud"]) }
    for m in ["R951V0403A17M4SCAP", "R802V0503A14DZSCAP", "R98VB060M317USA", "U96VA0402317MSA", "R96PA0602317MSA",
              "U801TA075417ZSA", "R96TA0702521MSA", "U98MV0855A21UPS", "W951W0403A17M4S", "RGPN-07EAMGR"] {
        expectModel(m, "Rheem", furnace)
    }
    for m in ["RH2TY2417STANAA", "RH1T3617STANJA", "RH3VZ3617STACNJ", "RH2TZ3621MTANA", "RHLL-HM2417JD"] { expectModel(m, "Rheem", ah) }
    for m in ["RCF3617STAMCA", "RCF4821MTAMCA", "RCFY2414STAAMCL", "RCFY3624MTANM"] { expectModel(m, "Rheem", coil) }

    // Water heaters
    expectModel("XG40T06EC36U1", "Rheem", wh, size: "40 gal · natural gas · 36,000 BTU/h")
    for m in ["XG50T06EC38U1", "XG50T06ECX58U0", "XG50T09HE40U0", "XG75T12UHN100U0"] { expectModel(m, "Rheem", wh, size: "natural gas") }
    expectModel("XP40T06EC32U1", "Rheem", wh, size: "propane")
    expectModel("XE50T06ST45U1", "Rheem", wh, size: "50 gal · electric · 4,500 W")
    for m in ["XE40M06ST38U1", "XE40T09CG55U0"] { expectModel(m, "Rheem", wh, size: "electric") }
    expectModel("XE50T10HD50U1", "Rheem", wh, size: "50 gal · heat pump")
    expectModel("XE50T10H45U1", "Rheem", wh, size: "heat pump")
    for m in ["PROE50 T2 RH95", "PROE28 S2 RH95 B"] { expectModel(m, "Rheem", wh, brands: ["Rheem"], size: "electric") }
    expectModel("PROE50 T2 RU95", "Rheem", wh, brands: ["Ruud"])
    expectModel("PROG50-38N RH60", "Rheem", wh, size: "50 gal · natural gas · 38,000 BTU/h")
    expectModel("PROG40S-36P RH62", "Rheem", wh, size: "propane")
    for m in ["PROG48-60N RH AX", "PRO+G40-50U RH HE EC1"] { expectModel(m, "Rheem", wh) }
    for m in ["PROPH50 T2 RH375-30", "PRO H40 T2 RU310BM"] { expectModel(m, "Rheem", wh, size: "heat pump") }
    expectModel("PROPH50 T2 RH375-30", "Rheem", wh, brands: ["Rheem"])
    expectModel("CPROPH50 T2 CD375-30", "Rheem", wh, brands: ["Ruud"])
    for m in ["GCR-50", "GCRT-50", "XCR-30", "FCG-75", "GPVL-50", "GCV-50", "GCR-50 300"] { expectModel(m, "A. O. Smith", wh, size: "gas") }
    expectModel("GCR-50 301", "A. O. Smith", wh, size: "propane")
    expectModel("FPTU-66 120", "A. O. Smith", wh, size: "66 gal")
    // A series cut short or misread isn't part of the gallons: no reading beats "503 gal".
    for m in ["GCR-50 3", "GDHE-50 3", "FPTU-50 1", "GCR-50 3OO"] { expectModel(m, nil) }
    for m in ["ENS-40", "ENT-50", "PXNT-50W", "HNT-50", "ECRT-52"] { expectModel(m, "A. O. Smith", wh, size: "electric") }
    for m in ["HPTU-50N", "FPTU-80"] { expectModel(m, "A. O. Smith", wh, size: "heat pump") }
    for m in ["G6-PVS4040NV", "G6-S5040NV"] { expectModel(m, "A. O. Smith", wh, size: "gas") }
    expectModel("E6-50H45DV", "A. O. Smith", wh, size: "electric · 4,500 W")
    for m in ["HP1050H45DV", "HPA10-50H45DV"] { expectModel(m, "A. O. Smith", wh, size: "heat pump") }
    for m in ["GS6 40 YBRT", "GSX 40 YBRT", "GS6 50 YBRS", "GS6 50 YBVIT", "GS6-75-XRRSL", "GS640YBRS200"] {
        expectModel(m, "A. O. Smith", wh, brands: ["State"], size: "natural gas")
    }
    for m in ["GS6 40 HBRT", "GS675 CRRS L"] { expectModel(m, "A. O. Smith", wh, brands: ["State"], size: "propane") }
    expectModel("ES6-50-DORS", "A. O. Smith", wh, brands: ["State"], size: "electric")
    expectModel("HP6-50-DHPT", "A. O. Smith", wh, brands: ["State"], size: "heat pump")
    for m in ["G61-50T40", "G62-40T40R", "BFG6250T403NO", "VG6250T76NV"] { expectModel(m, "A. O. Smith", wh, brands: ["American Water Heater"], size: "gas") }
    for m in ["E62-40LB-045DV", "E61-19L-045DV"] { expectModel(m, "A. O. Smith", wh, brands: ["American Water Heater"], size: "electric") }
    expectModel("HPHE10250H045DV", "A. O. Smith", wh, brands: ["American Water Heater"], size: "heat pump")
    for m in ["RG240T6N", "RG250T6N", "RG230S6N", "RG250L6N", "RG250H6N", "RG275H6N", "RG2100H6N", "RG1PV50S6N"] {
        expectModel(m, "Bradford White", wh, size: "natural gas")
    }
    expectModel("RG140T6X", "Bradford White", wh, size: "propane")
    for m in ["RE230LN6-1NCZZ", "RE250S6-1NCWW", "RE250T6-1NCWW"] { expectModel(m, "Bradford White", wh, size: "electric") }
    expectModel("RE2H50S10-1NCWT", "Bradford White", wh, size: "heat pump")
    expectModel("RU199iN", "Rinnai", wh, size: "tankless · natural gas · 199,000 BTU/h")
    for m in ["RL75iN", "V65iN", "RL94iN"] { expectModel(m, "Rinnai", wh) }
    expectModel("NPE-240A2", "Navien", wh, size: "199,900 BTU/h")

    // Tesla part numbers printed in Tesla's documents (manuals, datasheets, service parts) and on your label.
    let battery = EquipmentKind.battery, tesla = "Tesla"
    for m in ["1707000-21-M", "1707000-11-L", "1707000-21-L", "1707000-00-J", "1707000-21-K", "1707000-00-H"] {
        expectModel(m, tesla, battery, brands: ["Tesla"], size: "Powerwall 3 · 13.5 kWh · built-in solar inverter")
    }
    expectModel("1707000 -21 - M", tesla, battery)  // as OCR reads it
    expectModel("1807000-20-B", tesla, battery, size: "Powerwall 3 Expansion")
    for m in ["1092170-05-J", "2012170-05-C", "3012170-10-B"] { expectModel(m, tesla, battery, size: "Powerwall 2 AC") }
    for m in ["1067000-00-B", "1067000-01-E"] { expectModel(m, tesla, battery, size: "Powerwall (first generation) · 6.4 kWh") }
    expectModel("1850000-01-C", tesla, battery, size: "Powerwall+")
    expectModel("1538000-25-F", tesla, .solarInverter, size: "Tesla Solar Inverter · up to 7.6 kW")
    expectModel("1534000-00-A", tesla, .solarInverter, size: "3.8 kW")
    expectModel("1152100-13-J", tesla, .transferSwitch, size: "Backup Gateway 2")
    expectModel("1118431-01-K", tesla, .transferSwitch, size: "Backup Gateway (first generation)")
    expectModel("1624171-00-D", tesla, .transferSwitch, size: "Backup Switch")
    expectModel("1841000-01-C", tesla, .transferSwitch, size: "Gateway 3")
    expectModel("1841000-02-A", tesla, .transferSwitch, size: "Powershare Gateway")
    // Other Tesla numbers in the same format: the Powerwall 2 "LABEL PN", Megapack, Wall Connector, a
    // service part, an Australian model name, and a part number missing its revision.
    for m in ["1104459-00-F", "1462965-00-A", "1457768-01-F", "1857363-00-J", "1707000-11.04", "3012170-05"] {
        expectModel(m, nil)
    }

    // Heat pump or air conditioner for Nortek, Johnson Controls and the mini-split makers, from the lists' models.
    expectModel("FSH4BF5M2SX24K", "Nortek", hp, size: "2 tons")
    expectModel("FSA1BE4M1SN18K", "Nortek", ac, size: "1.5 tons")
    expectModel("JS4BD-018KA", "Nortek", ac)
    expectModel("GXH24-36MSK4DH", "Nortek", hp, size: "2–3 tons")
    expectModel("DXH12PSK3IH", "Nortek", hp)
    expectModel("YH2E18SB21", "Johnson Controls", hp, brands: ["York"], size: "1.5 tons")
    expectModel("YC2D18SB21", "Johnson Controls", ac, brands: ["York"])
    expectModel("TCJF24S41S1", "Johnson Controls", ac)
    expectModel("THF2B18S21", "Johnson Controls", hp)
    expectModel("AC19B2421", "Johnson Controls", ac, brands: ["Coleman"])
    expectModel("HL19B2421", "Johnson Controls", hp)
    expectModel("RHP14318B21", "Johnson Controls", hp, brands: ["Guardian", "Evcon"])
    expectModel("RAC14L18B21", "Johnson Controls", ac)
    expectModel("XH518E2S11", "Johnson Controls", hp)
    expectModel("XD524E2D11", "Johnson Controls", hp)
    expectModel("RAC-DJ09WHAA", "Johnson Controls", hp, brands: ["Hitachi"])
    expectModel("MUZ-GL15NA", "Mitsubishi Electric", hp)
    expectModel("MUY-GL15NA", "Mitsubishi Electric", ac)
    expectModel("MXZ-2C20NA4", "Mitsubishi Electric", hp)
    expectModel("AOU12RLFF", "Fujitsu", hp)
    expectModel("AOU12C1", "Fujitsu", ac)
    expectModel("LSU090HSV5", "LG", hp)
    expectModel("LSU092CE", "LG", ac)
    expectModel("GWH12QC-D3DNA1A/O", "Gree", hp)
    expectModel("38MHRCQ18AA3", "Carrier", hp)
    expectModel("38MHREC12AA3", "Carrier", ac)
    expectModel("D5CERAH09AAJ", "ICP", hp)
    expectModel("D5CERAA09AAK", "ICP", ac)
    expectModel("RX09BXVJU", "Goodman", hp, brands: ["Daikin"])
    expectModel("RKF09AXVJU", "Goodman", ac)
    expectModel("2MXL18WMVJU", "Goodman", hp)
    // Coils, air handlers, packaged units and a ductless air conditioner that start the same way.
    for m in ["TCFY2417STAN", "CH32-18CDI", "YCD036A3HOA", "CCG3036A4P", "AC1A042A", "YHJE18YJMEXGO-Y", "GWH12QC-D3DNA1A/I"] {
        expectModel(m, nil)
    }

    // Look-alikes from other makers, accessories and non-heaters: must not match anything.
    for m in ["HVAHP036B21S", "UPC09CN23STG1", "PH9E36N00D21", "PHE6B3624", "GHO18H52ACXL05",
              "25SPV0-HP-X-D", "24000-CHP-O", "1U24T3PS", "ML18HP230LMNT-O", "HSA1418S1", "HP-18ODU-001", "HP-A36/O",
              "ACVE245CB", "GSP-100", "PM-14", "TW-12", "RXBC-24", "CDVS960603BU", "VR9S960803BN", "RXMD-A04"] {
        expectModel(m, nil)
    }

    print(modelFailures == 0 ? "All model lookup checks passed" : "\(modelFailures) model lookup check(s) FAILED")
}
