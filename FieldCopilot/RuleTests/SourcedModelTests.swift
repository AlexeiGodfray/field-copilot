// Model numbers printed in manufacturers' own documents (product data, spec sheets, nomenclature guides),
// each checked against what the document says the model is. The document is named after each case.
// Distributor-hosted copies of a manufacturer's PDF count as the manufacturer's document.

func runSourcedModelTests() {
    let before = modelFailures
    let ac = EquipmentKind.airConditioner, hp = EquipmentKind.heatPump, furnace = EquipmentKind.furnace
    let ah = EquipmentKind.airHandler, coil = EquipmentKind.evaporatorCoil, pkg = EquipmentKind.packagedUnit

    // Carrier split
    expectModel("26SCA436N005", "Carrier", ac, brands: ["Carrier"], size: "3 tons · R-454B")  // 26SCA4-03PD p.2
    expectModel("27SCA542A003", "Carrier", hp, brands: ["Carrier"], size: "3.5 tons · R-454B")  // 27SCA5-01PD p.2
    expectModel("25HNB636C0030", "Carrier", hp, size: "3 tons · R-410A")  // 25HNB6C-5PD p.2
    expectModel("25HCR336C0030", "Carrier", hp, size: "3 tons · R-22")  // 25HCR3C-1PD p.2, "R = R-22"
    // Carrier 38-series
    expectModel("38BYC018331", "Carrier", hp, size: "1.5 tons")  // 38BYC-7PD p.2
    expectModel("38TRA018331", "Carrier", ac, size: "1.5 tons")  // 38TRA-12PD p.2
    expectModel("38CKC018311", "Carrier", ac, size: "1.5 tons")  // 38CKC-8PD p.2
    expectModel("38QRF018", "Carrier", hp, size: "1.5 tons")  // 38QRF-4SI p.2, duct-free heat pump
    // Carrier furnaces: condensing inputs are exact, 80% inputs are nominal
    expectModel("59SC6A026M14--10", "Carrier", furnace, brands: ["Carrier"], size: "26,000 BTU/h input")  // 59SC6A-04PD p.4
    expectModel("59SC6A140M24--22", "Carrier", furnace, size: "140,000 BTU/h input")  // 59SC6A-04PD p.4
    expectModel("58SC0A045E14--12", "Carrier", furnace, size: "44,000 BTU/h input · 80% AFUE")  // 58SC0A-05PD p.2
    expectModel("58SC0A070E17--16", "Carrier", furnace, size: "66,000 BTU/h input")  // 58SC0A-05PD p.2
    expectModel("58CTA045 100 08", "Carrier", furnace, brands: ["Carrier"], size: "44,000 BTU/h input")  // 58CTA product data p.2
    // Carrier, Bryant and Payne fan coils
    expectModel("FE4ANF002L00", "Carrier", ah, brands: ["Carrier", "Bryant", "Payne"], size: "1.5–3 tons")  // PDSFE4A-12 p.3
    expectModel("FE4ANB006T00", "Carrier", ah, size: "3–5 tons")  // PDSFE4A-12 p.3
    expectModel("FB4CNP025L00", "Carrier", ah, size: "2 tons")  // FB4CNF-P-12PD p.3
    expectModel("FB4CNP061L00", "Carrier", ah, size: "5 tons")  // FB4CNF-P-12PD p.3
    expectModel("FJ4DNXC36L00", "Carrier", ah, size: "3 tons")  // PDSFJ4D-01 p.2
    expectModel("FJ5ANXA18L05", "Carrier", ah, size: "1.5 tons")  // FJ5-02PD p.2
    expectModel("FJ5ANBD60L00", "Carrier", ah, size: "5 tons")  // FJ5-02PD p.2
    expectModel("FE5BNBC48L00", "Carrier", ah, size: "4 tons")  // FE5B-04PD p.3
    expectModel("PF4MNB061", "Carrier", ah, brands: ["Payne"], size: "5 tons")  // PF4MNB product data p.2
    expectModel("PF1MNC018005", "Carrier", ah, brands: ["Payne"], size: "1.5 tons")  // PF1MNC product data p.2
    // Carrier, Bryant and Payne coils: any capacity in a range
    expectModel("CNPVP2417ALA", "Carrier", coil, brands: ["Carrier", "Bryant", "Payne", "WeatherMaker", "Brock"], size: "2 tons")  // Payne 2012–13 guide p.30
    expectModel("CNRVU3617ACA", "Carrier", coil, size: "3 tons")  // CNPV-6PD
    expectModel("CAAMP3717AMA", "Carrier", coil, size: "3 tons")  // CAAMP-01PD
    expectModel("CVAVA3817XMA", "Carrier", coil, size: "3 tons")  // CVAVA-01PD
    expectModel("CVAMA4421XMA", "Carrier", coil, size: "3.5 tons")  // CVAMA-01PD p.2, "42 - 47 = 3½ Ton"
    // Bryant split, packaged and furnaces
    expectModel("113RNA036000A", "Carrier", ac, brands: ["Bryant"], size: "3 tons")  // PDS113R-06 p.2
    expectModel("215BNA0360000", "Carrier", hp, brands: ["Bryant"], size: "3 tons")  // PDS215B-01 p.2
    expectModel("550ANX024", "Carrier", ac, brands: ["Bryant"], size: "2 tons")  // PDS 550A.24.10 p.3
    expectModel("538BNR036000A", "Carrier", hp, brands: ["Bryant"], size: "3 tons")  // PDS538BNR-07 p.2
    expectModel("607CNXK24000AB", "Carrier", pkg, brands: ["Bryant"], size: "2 tons · heat pump")  // PDS607C-18 p.2
    expectModel("575CNWB36060N", "Carrier", pkg, brands: ["Bryant"], size: "3 tons · gas heat / electric cooling")  // PDS575C-04 p.3
    expectModel("916SA30026M14", "Carrier", furnace, brands: ["Bryant"], size: "26,000 BTU/h input")  // PDS916SA-04 p.4
    expectModel("916SA66140M24", "Carrier", furnace, size: "140,000 BTU/h input · 90%+ AFUE")  // PDS916SA-04 p.4
    expectModel("800SA60155E24", "Carrier", furnace, size: "154,000 BTU/h input · 80% AFUE")  // PDS800SA-10 p.2
    expectModel("820SA48070V17", "Carrier", furnace, size: "66,000 BTU/h input")  // PDS820SA-03 p.2
    // Payne and the builder line
    expectModel("PG96VTAA36060A", "Carrier", furnace, brands: ["Payne", "WeatherMaker", "Brock"], size: "60,000 BTU/h input")  // SS-PG96VTAA-05 p.5
    expectModel("PG80ESLA36070B", "Carrier", furnace, size: "66,000 BTU/h input")  // SS-PG80ESA-10 p.2
    expectModel("PH5SAN51900A", "Carrier", hp, brands: ["Payne"], size: "1.5 tons · R-454B")  // SSG-PH5SAN5-05 p.2
    expectModel("PH5SAN53100A", "Carrier", hp, brands: ["Payne"], size: "2.5 tons")  // SSG-PH5SAN5-05 p.2
    expectModel("PH8TAN52400A", "Carrier", hp, brands: ["Payne"], size: "2 tons · R-454B")  // SSG-PH8TAN5-01 p.2
    expectModel("GA5SAN53600W", "Carrier", ac, brands: ["Carrier", "Bryant"], size: "3 tons · R-454B")  // PDSGA5SAN5-01 p.2

    // ICP
    expectModel("R4A418AKB100", "ICP", ac, brands: ModelLookup.icpBrands, size: "1.5 tons")  // ICP 421 65 6240 06 p.3
    expectModel("H4H524GKA100", "ICP", hp, brands: ["Heil", "Arcoaire", "Airquest"], size: "2 tons")  // ICP 428 04 5800 00 p.30
    expectModel("HCH624GKA1", "ICP", hp, brands: ["Heil", "Arcoaire", "Airquest"], size: "2 tons")  // Heil catalog 401 12 2300 18 p.49
    expectModel("CCH624GKA1", "ICP", hp, brands: ["Comfortmaker", "Day & Night", "KeepRite"])  // KeepRite catalog 401 12 2300 18 p.49
    expectModel("N4A5S18AKAWA", "ICP", ac, brands: ModelLookup.icpBrands, size: "1.5 tons")  // N4A5S-11-02PD p.2
    expectModel("N5A5S36AKDWA", "ICP", ac, size: "3 tons")  // N5A5S-11-02PD p.2
    expectModel("R4A5S61AKAWA", "ICP", ac, brands: ModelLookup.icpBrands, size: "5 tons")  // R4A5S-01PD p.2
    expectModel("R4A5S49AKAWA", "ICP", ac, size: "4 tons")  // R4A5S-01PD p.2
    expectModel("N92ESN0802120A", "ICP", furnace, size: "80,000 BTU/h input")  // ICP 440 21 4541 01 p.2
    expectModel("N95ESN0261410A", "ICP", furnace, size: "26,000 BTU/h input")  // ICP N95ESN spec p.1
    expectModel("N95ESN0601412A", "ICP", furnace, size: "60,000 BTU/h input")  // ICP N95ESN spec p.1

    // Lennox
    expectModel("13ACX-024-230-2", "Lennox", ac, size: "2 tons · R-410A")  // 13ACX installation instructions 506374-01 p.3
    expectModel("13HPX-024-230-17", "Lennox", hp, size: "2 tons · R-410A")  // 13HPX installation instructions 506727-01 p.2
    expectModel("XC16-036-230-2", "Lennox", ac, size: "3 tons · R-410A")  // XC16 bulletin 210465 p.1
    expectModel("XP16-036-230-6", "Lennox", hp, size: "3 tons · R-410A")  // XP16 bulletin 210463 p.1
    expectModel("SL25KCV-036-230A-1", "Lennox", ac, size: "3 tons · R-454B")  // form 210965 p.2
    expectModel("ML14XC1-036-230A01", "Lennox", ac, size: "3 tons · R-410A")  // bulletin 210760 p.1
    expectModel("HS18-261-7P", "Lennox", ac, size: "2 tons")  // Lennox data-tag guide p.4
    expectModel("HS19-311-1P", "Lennox", ac, size: "2.5 tons")  // Lennox data-tag guide p.4
    expectModel("ML180UH070XE36B", "Lennox", furnace, size: "66,000 BTU/h input")  // bulletin 210825, form 210965 p.1
    expectModel("ML180UH135E60D", "Lennox", furnace, size: "132,000 BTU/h input")  // bulletin 210825
    expectModel("ML180UH030V36AK", "Lennox", furnace, size: "30,000 BTU/h input")  // form 211183
    expectModel("CBX40UHV-036-230-6-01", "Lennox", ah, size: "3 tons · R-410A")  // CBX40UHV installation instructions
    expectModel("CBA25UH-030-230-61", "Lennox", ah, size: "2.5 tons · R-410A")  // form 211248 p.1
    expectModel("CBK45UHPT-036-230-71", "Lennox", ah, size: "3 tons")  // form 211147 p.1
    expectModel("CBK45UHVT-036-230-01", "Lennox", ah, size: "3 tons")  // form 211068 p.1
    expectModel("CX35-36A-6F-1", "Lennox", coil, size: "3 tons")  // bulletin 210879 p.1
    expectModel("C35-36A-2-61", "Lennox", coil, size: "3 tons")  // form 211249
    expectModel("CX35-48B-6F", "Lennox", coil, size: "3.5–4 tons")  // bulletin 210879: "48 = 3.5/4 tons"
    expectModel("CX35-30/36B-6F", "Lennox", coil, size: "2.5–3 tons")  // bulletin 210879
    expectModel("CX34-50/60C-6F", "Lennox", coil, size: "4–5 tons")  // bulletin 210879
    // Allied Air
    expectModel("4SHP20LX160P-1", "Allied Air", hp, size: "5 tons")  // Allied 4SHP20LX-100 p.2
    expectModel("4SHP18LT124P-1A", "Allied Air", hp, size: "2 tons · R-410A")  // Allied 4SHP18LT spec

    // Goodman, Amana and Daikin
    let goodman = "Goodman", all3 = ["Goodman", "Amana", "Daikin"]
    expectModel("GSC130181G", goodman, ac, brands: ["Goodman"], size: "1.5 tons · 13 SEER")  // SS-GSC13 pp.2–3
    expectModel("GSX140371", goodman, ac, brands: ["Goodman"], size: "3 tons")  // SS-GSX14 p.2, "037 - 3 tons"
    expectModel("ANX130611A", goodman, ac, brands: ["Amana"], size: "5 tons")  // SS-ANX13 pp.2–3
    expectModel("GSXM401810A", goodman, ac, brands: ["Goodman"], size: "1.5 tons")  // Goodman catalog 5/23
    expectModel("GSZV906010A", goodman, hp, brands: ["Goodman"], size: "5 tons")  // Goodman catalog 5/23
    expectModel("GLXS4BA3610AA", goodman, ac, brands: ["Goodman"], size: "3 tons")  // R-32 nomenclature (Goodman) 03-24
    expectModel("ALXS4BA3610AA", goodman, ac, brands: ["Amana"], size: "3 tons")  // R-32 nomenclature (Amana) 03-24
    expectModel("GZV7SA6010A", goodman, hp, brands: ["Goodman"], size: "5 tons")  // SS-GZV7S-R32 p.2
    expectModel("AZV7SA6010A", goodman, hp, brands: ["Amana"], size: "5 tons")  // SS-AZV7S-R32 p.2
    expectModel("DZ14SA0491K", goodman, hp, brands: ["Daikin"], size: "4 tons · 14 SEER")  // SS-DZ14SA p.3
    expectModel("DZ14SA0181K", goodman, hp, brands: ["Daikin"], size: "1.5 tons")  // SS-DZ14SA p.3
    expectModel("DH7VSA6010A", goodman, hp, brands: ["Daikin"], size: "5 tons")  // SS-DH7VS-R32 pp.2–3
    expectModel("DC5SEA1810A", goodman, ac, brands: ["Daikin"], size: "1.5 tons")  // SS-DC5SE-R32 p.3
    expectModel("GPHH33041", goodman, pkg, brands: ["Goodman"], size: "2.5 tons · heat pump")  // SS-GPHH3 pp.2–3
    expectModel("GPGM36108041", goodman, pkg, brands: ["Goodman"], size: "5 tons")  // Goodman catalog 5/23
    expectModel("GPUM34808041", goodman, pkg, brands: ["Goodman"], size: "4 tons")  // Goodman catalog 5/23
    expectModel("DP5HM3631", goodman, pkg, brands: ["Daikin"], size: "3 tons · heat pump")  // SS-DP5HM-R32 p.3
    expectModel("DP14HH3641", goodman, pkg, brands: ["Daikin"], size: "3 tons · heat pump")  // SS-DP14HH p.2
    expectModel("GPC1336M41A", goodman, pkg, brands: ["Goodman"], size: "3 tons · air conditioner")  // SS-GPC13M p.3
    expectModel("APG1324045M41BA", goodman, pkg, brands: ["Amana"], size: "2 tons")  // RP-703A p.1
    expectModel("APG1360115M41BA", goodman, pkg, brands: ["Amana"], size: "5 tons")  // RP-703A p.1
    expectModel("GMS81405DNC", goodman, furnace, brands: ["Goodman"], size: "140,000 BTU/h input · 80% AFUE")  // SS-GMS8 p.3
    expectModel("GMH950453BXA", goodman, furnace, brands: ["Goodman"], size: "45,000 BTU/h input · about 95% AFUE")  // SS-GMH95 p.3
    expectModel("GRVS800603BNAA", goodman, furnace, brands: ["Goodman"], size: "60,000 BTU/h input")  // R-32 nomenclature (Goodman)
    expectModel("DM96VC1205DNA", goodman, furnace, brands: ["Daikin"], size: "120,000 BTU/h input · about 96% AFUE")  // SS-DM96VC p.2
    expectModel("CAUF3137B6", goodman, coil, brands: all3, size: "2.5–3 tons")  // SS-GCoil p.2
    expectModel("CHPF2430B6", goodman, coil, size: "2–2.5 tons")  // SS-GCoil p.8
    expectModel("CSCF3036N6", goodman, coil, size: "2.5–3 tons")  // SS-GCoil p.9
    expectModel("CAUFA2318A6", goodman, coil, size: "2 tons")  // Goodman catalog 5/23 p.50
    expectModel("CHPTA1818A3AA", goodman, coil, size: "1.5 tons")  // R-32 nomenclature (Goodman)
    expectModel("CAUFA1714A6", goodman, coil, size: "1.5 tons")  // Goodman catalog 5/23 p.50, "1½"
    expectModel("ARUF486016", goodman, ah, brands: all3, size: "4–5 tons")  // SS-GARUF 2/12 p.3
    expectModel("ARUF172916", goodman, ah, size: "1.5–2.5 tons")  // SS-GARUF 2/12 p.2, "1729 1½ to 2½ Tons"
    expectModel("AWUF310516", goodman, ah, size: "2.5 tons · 5 kW heater")  // SS-AAWUF p.2, "05 = 5 kW"
    expectModel("ARUF25B14AA", goodman, ah, brands: all3)  // SS-DARUF
    expectModel("DV37PTCB14", goodman, ah, brands: ["Daikin"])  // SS-DVPTC p.3
    expectModel("AMST36BU1400BA", goodman, ah, brands: all3, size: "3 tons")  // SS-DAMST p.2, "36 - 3.0 Tons"
    expectModel("DFVE60DP1300A", goodman, ah, brands: ["Daikin"], size: "5 tons")  // SS-DFVE; SS-DH7VS-R32 p.3
    expectModel("DMVT36BU1400BA", goodman, ah, brands: ["Daikin"], size: "3 tons")  // SS-DMVT

    // Trane, American Standard, RunTru and Ameristar
    let trane = "Trane", both = ["Trane", "American Standard"]
    expectModel("5TWV0X24A1000A", trane, hp, brands: ["Trane"], size: "2 tons · R-454B")  // ODR-PSD025B-EN p.1
    expectModel("5TTV0X25A1000A", trane, ac, brands: ["Trane"], size: "2 tons")  // ODR-PSD019A-EN p.1
    expectModel("4TWR3036A1000AA", trane, hp, brands: ["Trane"], size: "3 tons · R-410A")  // Trane 22-1795-03 p.6
    expectModel("2TWR1024A1000A", trane, hp, brands: ["Trane"], size: "R-22")  // Trane 22-1742-01 p.1
    expectModel("4A7A5036A1", trane, ac, brands: ["American Standard"], size: "3 tons · R-410A")  // AS 12-1275-01 p.1
    expectModel("4A6H5049E1", trane, hp, brands: ["American Standard"], size: "4 tons")  // AS 12-1256-15 p.1
    expectModel("2A6B3036A1000AA", trane, hp, brands: ["American Standard"], size: "3 tons · R-22")  // AS 12-1215-02 p.6
    expectModel("5A5V0X48A1000A", trane, hp, brands: ["American Standard"], size: "4 tons · R-454B")  // americanstandardair.com Platinum 20
    expectModel("A5AC3018B1000A", trane, ac, brands: ["RunTru", "Ameristar"], size: "1.5 tons · R-454B")  // ODR-PSD030C-EN p.1
    expectModel("A5AC3060B1000A", trane, ac, brands: ["RunTru", "Ameristar"], size: "5 tons")  // ODR-PSD030C-EN p.1
    expectModel("5HCL5036B1000A", trane, hp, brands: both, size: "3 tons · R-454B")  // ODR-PSD038A-EN p.1
    expectModel("5HCL5060B1000A", trane, hp, size: "5 tons")  // ODR-PSD038A-EN p.1
    expectModel("4TXK1609A10N0", trane, hp, size: "9,000 BTU/h · R-410A")  // 22-1918-1D-EN p.1
    expectModel("4TXK1624A10N0", trane, hp, size: "2 tons")  // 22-1918-1D-EN, "X = Heat Pump Inverter"
    expectModel("4TYK1612A10N0", trane, ac, size: "1 ton")  // 22-1918-1D-EN, "Y = Cooling Only Inverter"
    expectModel("5YCC4060A1115A", trane, pkg, brands: both, size: "5 tons · gas heat / electric cooling")  // PKGR-PSD005B-EN p.1
    expectModel("4YCY4024A1064AA", trane, pkg, size: "2 tons")  // Trane 22-1797-01
    expectModel("4WCZ5030E1", trane, pkg, size: "heat pump")  // American Standard EnergyGuide label
    expectModel("4DCZ5036E1", trane, pkg, size: "dual fuel")  // American Standard EnergyGuide label (packaged hybrid)
    expectModel("5TCC4036A1000A", trane, pkg, size: "air conditioner")  // trane.com Choice 14 packaged AC
    expectModel("4TCY4024A1000B", trane, pkg)  // Trane 22-1796-15A-EN, "Single Packaged Convertible Cooling"
    expectModel("TUD1B080A9H31AA", trane, furnace, brands: ["Trane"], size: "80,000 BTU/h input · 3 tons airflow")  // 22-1795-03 p.6
    expectModel("AUD1A040A9301B", trane, furnace, brands: ["American Standard"], size: "2.5 tons airflow")  // AS catalog 14-1011-36
    expectModel("AUD1C120A9541B", trane, furnace, size: "5 tons airflow")  // AS catalog 14-1011-36; 12-1248-12, "54 = 5 Tons"
    expectModel("AUD1D100A9721B", trane, furnace, size: "6 tons airflow")  // AS catalog 14-1011-36; 12-1248-12, "72 = 6 Tons"
    expectModel("S8X1B060M3PSAB", trane, furnace, brands: both, size: "60,000 BTU/h input · 80% AFUE")  // 22-1644-1B-EN p.1
    expectModel("S9X2B060U3PSAB", trane, furnace, size: "about 96% AFUE")  // AS catalog 14-1011-36
    expectModel("S8X1A026M2PSAB", trane, furnace, size: "26,000 BTU/h input")  // 22-1644-1B-EN p.5
    expectModel("GAM5B0C60M51SA", trane, ah, brands: both, size: "5 tons")  // Trane 22-1845-12 p.1
    expectModel("GAM2A0A36S31SAA", trane, ah, size: "3 tons")  // AS 12-1248-12 p.6
    expectModel("GAM5B0A18M11SA", trane, ah, size: "1.5 tons")  // AS 12-1248-12, "1-5 - nom. Tonnage"
    expectModel("5TEM4B02AC21SA", trane, ah, size: "R-454B")  // 5TEM4B02A-SUB-1A-EN p.1
    expectModel("4TEE3F36A1000AA", trane, ah, size: "3 tons · R-410A")  // Trane 22-1795-03 p.6
    expectModel("2TXCB036AC3HCAA", trane, coil, size: "3 tons · R-22")  // AS 12-1215-02 p.6
    expectModel("5TXCA001AS3HCA", trane, coil, size: "1.5–2 tons · R-454B")  // 5TXC-AS-SUB-1B-EN p.1
    expectModel("5TXCB006AS3HCA", trane, coil, size: "3.5–4 tons")  // 5TXC-AS-SUB-1B-EN p.1
    expectModel("5TXCD008AS3HCA", trane, coil, size: "3.5–5 tons")  // 5TXC-AS-SUB-1B-EN p.1

    // Rheem, Ruud and Rheem-built private labels
    expectModel("RD18AY60AJVCA", "Rheem", hp, size: "5 tons · R-454B")  // RD18AY brochure, "5 ton"
    expectModel("RA13NZ24AJ1NA", "Rheem", ac, size: "2 tons · R-410A")  // Ruud RA13NZ spec A22-338 p.4
    expectModel("RP17AY48AJVCA", "Rheem", hp, size: "4 tons · R-454B")  // RP17AY spec P11-861 p.4
    expectModel("RP1730HJVXA", "Rheem", hp, size: "2.5 tons")  // RP17**H spec P11-821
    expectModel("SP14AY18AJ1NAA40", "Rheem", hp, brands: ["Sure Comfort", "Russell"])  // Sure Comfort SP14AY spec PSC-840 p.4
    expectModel("FWSA14AY18AJ1NA", "Rheem", ac, brands: ["Friedrich"])  // Friedrich spec AFR-352
    expectModel("RANL-018JAZ", "Rheem", ac, brands: ["Rheem"], size: "1.5 tons")  // RANL parts list p.2
    expectModel("RPNL-024JEZ", "Rheem", hp, brands: ["Rheem"], size: "2 tons")  // RPNL parts list p.2
    expectModel("RASL-024JEC", "Rheem", ac, brands: ["Rheem"], size: "2 tons")  // RASL parts list
    expectModel("R951V0403A17M4SCAP", "Rheem", furnace, size: "about 95% AFUE · 3 tons airflow")  // R951V spec G11-674 p.4
    expectModel("R951T0403A17M4SNAS", "Rheem", furnace, size: "42,000 BTU/h input · about 95% AFUE")  // R951T spec G11-673 table
    expectModel("R801T0503A14UHSNAS", "Rheem", furnace, size: "50,000 BTU/h input · 80% AFUE")  // R801T spec G11-662
    expectModel("U98MV0603A17UPSGAP", "Rheem", furnace, brands: ["Ruud"])  // Ruud U98MV spec G22-678
    expectModel("U96VA0402317MSA", "Rheem", furnace, brands: ["Ruud"], size: "about 96% AFUE")  // Ruud U96V spec G22-540 p.4
    expectModel("R96VA0602317MSA", "Rheem", furnace, size: "56,000 BTU/h input")  // R96V spec G11-540, "060 = 56,000"
    expectModel("R801TA075317ZSA", "Rheem", furnace, size: "75,000 BTU/h input · 80% AFUE · 3 tons airflow")  // R801T parts list p.2
    expectModel("R801CA050314ZSA", "Rheem", furnace, size: "80% AFUE")  // R801C parts list
    expectModel("R801TA100521ZSA", "Rheem", furnace, size: "98,000 BTU/h input")  // R801T parts list, "100 = 98,000 BTU/HR"
    expectModel("RGLN-05EAUER", "Rheem", furnace, brands: ["Rheem"])  // RGLN parts list
    expectModel("RGLT-10EBRMR", "Rheem", furnace, brands: ["Rheem"])  // RGLT parts list
    expectModel("RH2TY2417STANNJ", "Rheem", ah, size: "up to 2 tons")  // RH2TY spec H11-592 p.4
    expectModel("RH2T4821MEACJA", "Rheem", ah, size: "up to 4 tons")  // RH2T parts list
    expectModel("RH1AY2417STANNJ", "Rheem", ah, size: "up to 2 tons")  // bim.ruud.com RH1AY
    expectModel("RHLL-HM6024JA", "Rheem", ah, brands: ["Rheem"], size: "up to 5 tons")  // RHLL parts list
    expectModel("RHLL-HM3821JA", "Rheem", ah, brands: ["Rheem"])  // RHLL parts list
    expectModel("RCFY2414STAAMCL", "Rheem", coil, size: "2 tons")  // RCFY spec C11-228 p.4
    expectModel("RCF2421UEAMCA", "Rheem", coil, size: "2 tons")  // RCF spec C11-224
    expectModel("RCH2417STAVUA", "Rheem", coil, size: "2 tons")  // RCH installation instructions

    // Water heaters
    let wh = EquipmentKind.waterHeater, aos = "A. O. Smith"
    expectModel("XG50T12UHN76U0", "Rheem", wh, size: "50 gal · natural gas · 76,000 BTU/h · 12-year warranty")  // rheem.com
    expectModel("PROE47 S2 RH95", "Rheem", wh, brands: ["Rheem"], size: "47 gal · electric")  // PROE RH N Rev. 14
    expectModel("PROE40 M2 RU95", "Rheem", wh, brands: ["Ruud"], size: "40 gal")  // ruud.com Professional Achiever
    expectModel("PROE55 T2 RH94", "Rheem", wh, size: "55 gal · electric")  // PROE RH N Rev. 14
    expectModel("PROE50 2 RH95 MH", "Rheem", wh, size: "electric")  // rheem.com proe50-2-rh95-mh
    expectModel("FCG-100 400", aos, wh, size: "100 gal · gas")  // hotwater.com FCG-100 400
    expectModel("FCG-100 401", aos, wh, size: "propane")  // hotwater.com FCG-100 401, "PROPANE"
    expectModel("GPDT-50", aos, wh, size: "gas")  // hotwater.com ProLine gas spec index
    expectModel("G12-T5040NVR", aos, wh, size: "50 gal · natural gas · 40,000 BTU/h")  // aosmithatlowes.com
    expectModel("G6-PVT4050PV", aos, wh, size: "propane")  // aosmithatlowes.com, "Liquid Propane"
    expectModel("G6N-T5040NVR", aos, wh, size: "50 gal")  // aosmithatlowes.com
    expectModel("GC9-PS5065NV", aos, wh, size: "50 gal")  // aosmithatlowes.com
    expectModel("E6-40R38D-TTP", aos, wh, size: "40 gal · electric · 3,800 W")  // aosmithatlowes.com
    expectModel("HPV10-80H01DV", aos, wh, size: "80 gal · heat pump")  // aosmithatlowes.com
    expectModel("HPSN10-50H45DV", aos, wh, size: "50 gal · heat pump")  // aosmithatlowes.com
    expectModel("GS6 40 YOCT L", aos, wh, brands: ["State"], size: "40 gal · natural gas")  // State SRGSS03711
    expectModel("GS6 40 YBRT G", aos, wh, brands: ["State"], size: "natural gas")  // State SRGSS01206
    expectModel("GS6 50 YRRT L5", aos, wh, brands: ["State"], size: "natural gas")  // State SRGSS03711
    expectModel("EN6-40-DORT 110", aos, wh, brands: ["State"], size: "40 gal · electric")  // statewaterheaters.com
    expectModel("HPX-80-DHPTNE", aos, wh, brands: ["State"], size: "80 gal · heat pump")  // statewaterheaters.com
    expectModel("HP6-80-DHPT 130", aos, wh, brands: ["State"], size: "heat pump")  // statewaterheaters.com
    expectModel("G62-40T40R 410", aos, wh, brands: ["American Water Heater"], size: "40 gal · gas · 40,000 BTU/h")  // americanwaterheater.com
    expectModel("G62-100T77-4NOV", aos, wh, brands: ["American Water Heater"], size: "100 gal")  // americanwaterheater.com
    expectModel("E61-19L-045DV", aos, wh, brands: ["American Water Heater"], size: "19 gal · electric · 4,500 W")  // americanwaterheater.com
    expectModel("E61-19L-045DV 100", aos, wh, brands: ["American Water Heater"], size: "electric")  // americanwaterheater.com
    expectModel("RG150T6N", "Bradford White", wh, size: "50 gal · natural gas · 6-year warranty")  // Bradford White 1101-1125 p.2
    expectModel("RG230S6N", "Bradford White", wh, size: "30 gal · natural gas")  // Bradford White 1101-1125 p.2
    expectModel("RUCS75iN", "Rinnai", wh, size: "160,000 BTU/h")  // rinnai.us, "160,000 BTU (maximum)"
    expectModel("RUCS65iN", "Rinnai", wh, size: "130,000 BTU/h")  // rinnai.us, "130,000 BTU (maximum)"
    expectModel("RU199eP", "Rinnai", wh, size: "tankless · propane · 199,000 BTU/h")  // rinnai.us RU199eP
    expectModel("V75iN", "Rinnai", wh, size: "180,000 BTU/h")  // rinnai.us V75iN
    expectModel("NPE-180A2-NG", "Navien", wh, size: "150,000 BTU/h")  // Navien NPE-2 QuickFacts
    expectModel("NPE-210S2", "Navien", wh, size: "180,000 BTU/h")  // Navien NPE-2 QuickFacts
    expectModel("NPE-150S2", "Navien", wh, size: "120,000 BTU/h")  // Navien NPE-2 QuickFacts

    print(modelFailures == before ? "All sourced model checks passed" : "\(modelFailures - before) sourced model check(s) FAILED")
}
