// Weight Initialization Code
// Weights: OC=32, IC=1, KH=5, KW=5
// Layout: [Tile_OC][Tile_IC][KY][KW][PE_ROWS][4 words]

        // Zero out all weight memory (6400 words)
        for (k = 0; k < 6400; k = k + 1) begin
            u_tb_common.write_wgt_word(k, 32'h00000000);
        end

        // Write actual weights (only row 0 of each block for IC=1)
        // Block 0: tile_oc=0, ky=0, kw=0
        u_tb_common.write_wgt_word(0, 32'h15041009); // K[0,0]: OC0=9, OC1=16, OC2=4, OC3=21
        u_tb_common.write_wgt_word(1, 32'h0fe9fe2f); // K[0,0]: OC4=47, OC5=-2, OC6=-23, OC7=15
        u_tb_common.write_wgt_word(2, 32'heff6080b); // K[0,0]: OC8=11, OC9=8, OC10=-10, OC11=-17
        u_tb_common.write_wgt_word(3, 32'hc6ff00ef); // K[0,0]: OC12=-17, OC13=0, OC14=-1, OC15=-58
        // Block 1: tile_oc=0, ky=0, kw=1
        u_tb_common.write_wgt_word(128, 32'h1c041f07); // K[0,1]: OC0=7, OC1=31, OC2=4, OC3=28
        u_tb_common.write_wgt_word(129, 32'h0af80529); // K[0,1]: OC4=41, OC5=5, OC6=-8, OC7=10
        u_tb_common.write_wgt_word(130, 32'h0a02ee1b); // K[0,1]: OC8=27, OC9=-18, OC10=2, OC11=10
        u_tb_common.write_wgt_word(131, 32'hff1815f5); // K[0,1]: OC12=-11, OC13=21, OC14=24, OC15=-1
        // Block 2: tile_oc=0, ky=0, kw=2
        u_tb_common.write_wgt_word(256, 32'h0af9f4eb); // K[0,2]: OC0=-21, OC1=-12, OC2=-7, OC3=10
        u_tb_common.write_wgt_word(257, 32'h0415f5fb); // K[0,2]: OC4=-5, OC5=-11, OC6=21, OC7=4
        u_tb_common.write_wgt_word(258, 32'hee17fcf5); // K[0,2]: OC8=-11, OC9=-4, OC10=23, OC11=-18
        u_tb_common.write_wgt_word(259, 32'h080818ef); // K[0,2]: OC12=-17, OC13=24, OC14=8, OC15=8
        // Block 3: tile_oc=0, ky=0, kw=3
        u_tb_common.write_wgt_word(384, 32'h03ebf5f3); // K[0,3]: OC0=-13, OC1=-11, OC2=-21, OC3=3
        u_tb_common.write_wgt_word(385, 32'h242cd9df); // K[0,3]: OC4=-33, OC5=-39, OC6=44, OC7=36
        u_tb_common.write_wgt_word(386, 32'hfaf8f5e9); // K[0,3]: OC8=-23, OC9=-11, OC10=-8, OC11=-6
        u_tb_common.write_wgt_word(387, 32'h35131e06); // K[0,3]: OC12=6, OC13=30, OC14=19, OC15=53
        // Block 4: tile_oc=0, ky=0, kw=4
        u_tb_common.write_wgt_word(512, 32'hebfefa06); // K[0,4]: OC0=6, OC1=-6, OC2=-2, OC3=-21
        u_tb_common.write_wgt_word(513, 32'hfc23dbd5); // K[0,4]: OC4=-43, OC5=-37, OC6=35, OC7=-4
        u_tb_common.write_wgt_word(514, 32'h08f3f3ed); // K[0,4]: OC8=-19, OC9=-13, OC10=-13, OC11=8
        u_tb_common.write_wgt_word(515, 32'h4302fd10); // K[0,4]: OC12=16, OC13=-3, OC14=2, OC15=67
        // Block 5: tile_oc=0, ky=1, kw=0
        u_tb_common.write_wgt_word(640, 32'hf6f6fa10); // K[1,0]: OC0=16, OC1=-6, OC2=-10, OC3=-10
        u_tb_common.write_wgt_word(641, 32'h15dd0cfd); // K[1,0]: OC4=-3, OC5=12, OC6=-35, OC7=21
        u_tb_common.write_wgt_word(642, 32'h02f81217); // K[1,0]: OC8=23, OC9=18, OC10=-8, OC11=2
        u_tb_common.write_wgt_word(643, 32'h2813dfe0); // K[1,0]: OC12=-32, OC13=-33, OC14=19, OC15=40
        // Block 6: tile_oc=0, ky=1, kw=1
        u_tb_common.write_wgt_word(768, 32'h2f001bfa); // K[1,1]: OC0=-6, OC1=27, OC2=0, OC3=47
        u_tb_common.write_wgt_word(769, 32'h19ec1ce1); // K[1,1]: OC4=-31, OC5=28, OC6=-20, OC7=25
        u_tb_common.write_wgt_word(770, 32'hecf31b02); // K[1,1]: OC8=2, OC9=27, OC10=-13, OC11=-20
        u_tb_common.write_wgt_word(771, 32'h2d0402fd); // K[1,1]: OC12=-3, OC13=2, OC14=4, OC15=45
        // Block 7: tile_oc=0, ky=1, kw=2
        u_tb_common.write_wgt_word(896, 32'h1fe900fb); // K[1,2]: OC0=-5, OC1=0, OC2=-23, OC3=31
        u_tb_common.write_wgt_word(897, 32'h18d1f1e1); // K[1,2]: OC4=-31, OC5=-15, OC6=-47, OC7=24
        u_tb_common.write_wgt_word(898, 32'hee1a1b0d); // K[1,2]: OC8=13, OC9=27, OC10=26, OC11=-18
        u_tb_common.write_wgt_word(899, 32'h29183a11); // K[1,2]: OC12=17, OC13=58, OC14=24, OC15=41
        // Block 8: tile_oc=0, ky=1, kw=3
        u_tb_common.write_wgt_word(1024, 32'hdddef9e5); // K[1,3]: OC0=-27, OC1=-7, OC2=-34, OC3=-35
        u_tb_common.write_wgt_word(1025, 32'h16ef0ef3); // K[1,3]: OC4=-13, OC5=14, OC6=-17, OC7=22
        u_tb_common.write_wgt_word(1026, 32'h14052efe); // K[1,3]: OC8=-2, OC9=46, OC10=5, OC11=20
        u_tb_common.write_wgt_word(1027, 32'h4d122714); // K[1,3]: OC12=20, OC13=39, OC14=18, OC15=77
        // Block 9: tile_oc=0, ky=1, kw=4
        u_tb_common.write_wgt_word(1152, 32'heaf2f0f1); // K[1,4]: OC0=-15, OC1=-16, OC2=-14, OC3=-22
        u_tb_common.write_wgt_word(1153, 32'h23fe3f12); // K[1,4]: OC4=18, OC5=63, OC6=-2, OC7=35
        u_tb_common.write_wgt_word(1154, 32'h0b031e04); // K[1,4]: OC8=4, OC9=30, OC10=3, OC11=11
        u_tb_common.write_wgt_word(1155, 32'h481eea07); // K[1,4]: OC12=7, OC13=-22, OC14=30, OC15=72
        // Block 10: tile_oc=0, ky=2, kw=0
        u_tb_common.write_wgt_word(1280, 32'h0b0ee00c); // K[2,0]: OC0=12, OC1=-32, OC2=14, OC3=11
        u_tb_common.write_wgt_word(1281, 32'h23fc07cc); // K[2,0]: OC4=-52, OC5=7, OC6=-4, OC7=35
        u_tb_common.write_wgt_word(1282, 32'h17f70708); // K[2,0]: OC8=8, OC9=7, OC10=-9, OC11=23
        u_tb_common.write_wgt_word(1283, 32'h4bf20bf4); // K[2,0]: OC12=-12, OC13=11, OC14=-14, OC15=75
        // Block 11: tile_oc=0, ky=2, kw=1
        u_tb_common.write_wgt_word(1408, 32'h2d14f703); // K[2,1]: OC0=3, OC1=-9, OC2=20, OC3=45
        u_tb_common.write_wgt_word(1409, 32'h17e216ea); // K[2,1]: OC4=-22, OC5=22, OC6=-30, OC7=23
        u_tb_common.write_wgt_word(1410, 32'hfc0d1905); // K[2,1]: OC8=5, OC9=25, OC10=13, OC11=-4
        u_tb_common.write_wgt_word(1411, 32'h43e92505); // K[2,1]: OC12=5, OC13=37, OC14=-23, OC15=67
        // Block 12: tile_oc=0, ky=2, kw=2
        u_tb_common.write_wgt_word(1536, 32'h0a151ee0); // K[2,2]: OC0=-32, OC1=30, OC2=21, OC3=10
        u_tb_common.write_wgt_word(1537, 32'h06c501ff); // K[2,2]: OC4=-1, OC5=1, OC6=-59, OC7=6
        u_tb_common.write_wgt_word(1538, 32'h08180d04); // K[2,2]: OC8=4, OC9=13, OC10=24, OC11=8
        u_tb_common.write_wgt_word(1539, 32'h2af53110); // K[2,2]: OC12=16, OC13=49, OC14=-11, OC15=42
        // Block 13: tile_oc=0, ky=2, kw=3
        u_tb_common.write_wgt_word(1664, 32'hf11b0cdd); // K[2,3]: OC0=-35, OC1=12, OC2=27, OC3=-15
        u_tb_common.write_wgt_word(1665, 32'hfdcc1c2e); // K[2,3]: OC4=46, OC5=28, OC6=-52, OC7=-3
        u_tb_common.write_wgt_word(1666, 32'h022217fe); // K[2,3]: OC8=-2, OC9=23, OC10=34, OC11=2
        u_tb_common.write_wgt_word(1667, 32'h09291c05); // K[2,3]: OC12=5, OC13=28, OC14=41, OC15=9
        // Block 14: tile_oc=0, ky=2, kw=4
        u_tb_common.write_wgt_word(1792, 32'hd52003df); // K[2,4]: OC0=-33, OC1=3, OC2=32, OC3=-43
        u_tb_common.write_wgt_word(1793, 32'h26e12a35); // K[2,4]: OC4=53, OC5=42, OC6=-31, OC7=38
        u_tb_common.write_wgt_word(1794, 32'h081c2600); // K[2,4]: OC8=0, OC9=38, OC10=28, OC11=8
        u_tb_common.write_wgt_word(1795, 32'h2131f708); // K[2,4]: OC12=8, OC13=-9, OC14=49, OC15=33
        // Block 15: tile_oc=0, ky=3, kw=0
        u_tb_common.write_wgt_word(1920, 32'h13edf312); // K[3,0]: OC0=18, OC1=-13, OC2=-19, OC3=19
        u_tb_common.write_wgt_word(1921, 32'h162114e2); // K[3,0]: OC4=-30, OC5=20, OC6=33, OC7=22
        u_tb_common.write_wgt_word(1922, 32'hf2f1ff0e); // K[3,0]: OC8=14, OC9=-1, OC10=-15, OC11=-14
        u_tb_common.write_wgt_word(1923, 32'hfb080320); // K[3,0]: OC12=32, OC13=3, OC14=8, OC15=-5
        // Block 16: tile_oc=0, ky=3, kw=1
        u_tb_common.write_wgt_word(2048, 32'h29fbf31d); // K[3,1]: OC0=29, OC1=-13, OC2=-5, OC3=41
        u_tb_common.write_wgt_word(2049, 32'h09112b07); // K[3,1]: OC4=7, OC5=43, OC6=17, OC7=9
        u_tb_common.write_wgt_word(2050, 32'h07f50505); // K[3,1]: OC8=5, OC9=5, OC10=-11, OC11=7
        u_tb_common.write_wgt_word(2051, 32'hddff15ff); // K[3,1]: OC12=-1, OC13=21, OC14=-1, OC15=-35
        // Block 17: tile_oc=0, ky=3, kw=2
        u_tb_common.write_wgt_word(2176, 32'h11190c19); // K[3,2]: OC0=25, OC1=12, OC2=25, OC3=17
        u_tb_common.write_wgt_word(2177, 32'hde131924); // K[3,2]: OC4=36, OC5=25, OC6=19, OC7=-34
        u_tb_common.write_wgt_word(2178, 32'h07fff801); // K[3,2]: OC8=1, OC9=-8, OC10=-1, OC11=7
        u_tb_common.write_wgt_word(2179, 32'hc6da1cfc); // K[3,2]: OC12=-4, OC13=28, OC14=-38, OC15=-58
        // Block 18: tile_oc=0, ky=3, kw=3
        u_tb_common.write_wgt_word(2304, 32'hea2cf703); // K[3,3]: OC0=3, OC1=-9, OC2=44, OC3=-22
        u_tb_common.write_wgt_word(2305, 32'hf0f7fd17); // K[3,3]: OC4=23, OC5=-3, OC6=-9, OC7=-16
        u_tb_common.write_wgt_word(2306, 32'h071bfc14); // K[3,3]: OC8=20, OC9=-4, OC10=27, OC11=7
        u_tb_common.write_wgt_word(2307, 32'haae31612); // K[3,3]: OC12=18, OC13=22, OC14=-29, OC15=-86
        // Block 19: tile_oc=0, ky=3, kw=4
        u_tb_common.write_wgt_word(2432, 32'hd329f300); // K[3,4]: OC0=0, OC1=-13, OC2=41, OC3=-45
        u_tb_common.write_wgt_word(2433, 32'he9f9e10a); // K[3,4]: OC4=10, OC5=-31, OC6=-7, OC7=-23
        u_tb_common.write_wgt_word(2434, 32'h01171ee3); // K[3,4]: OC8=-29, OC9=30, OC10=23, OC11=1
        u_tb_common.write_wgt_word(2435, 32'haa02e90a); // K[3,4]: OC12=10, OC13=-23, OC14=2, OC15=-86
        // Block 20: tile_oc=0, ky=4, kw=0
        u_tb_common.write_wgt_word(2560, 32'h0ac7ee11); // K[4,0]: OC0=17, OC1=-18, OC2=-57, OC3=10
        u_tb_common.write_wgt_word(2561, 32'he82bfd24); // K[4,0]: OC4=36, OC5=-3, OC6=43, OC7=-24
        u_tb_common.write_wgt_word(2562, 32'hede5cb03); // K[4,0]: OC8=3, OC9=-53, OC10=-27, OC11=-19
        u_tb_common.write_wgt_word(2563, 32'hcee7fe11); // K[4,0]: OC12=17, OC13=-2, OC14=-25, OC15=-50
        // Block 21: tile_oc=0, ky=4, kw=1
        u_tb_common.write_wgt_word(2688, 32'h2de0091f); // K[4,1]: OC0=31, OC1=9, OC2=-32, OC3=45
        u_tb_common.write_wgt_word(2689, 32'hc81d2113); // K[4,1]: OC4=19, OC5=33, OC6=29, OC7=-56
        u_tb_common.write_wgt_word(2690, 32'h0ee4df1c); // K[4,1]: OC8=28, OC9=-33, OC10=-28, OC11=14
        u_tb_common.write_wgt_word(2691, 32'ha8f51609); // K[4,1]: OC12=9, OC13=22, OC14=-11, OC15=-88
        // Block 22: tile_oc=0, ky=4, kw=2
        u_tb_common.write_wgt_word(2816, 32'h04150e12); // K[4,2]: OC0=18, OC1=14, OC2=21, OC3=4
        u_tb_common.write_wgt_word(2817, 32'hd930faf6); // K[4,2]: OC4=-10, OC5=-6, OC6=48, OC7=-39
        u_tb_common.write_wgt_word(2818, 32'hf8e1c90b); // K[4,2]: OC8=11, OC9=-55, OC10=-31, OC11=-8
        u_tb_common.write_wgt_word(2819, 32'ha3d928f3); // K[4,2]: OC12=-13, OC13=40, OC14=-39, OC15=-93
        // Block 23: tile_oc=0, ky=4, kw=3
        u_tb_common.write_wgt_word(2944, 32'hda2bf831); // K[4,3]: OC0=49, OC1=-8, OC2=43, OC3=-38
        u_tb_common.write_wgt_word(2945, 32'hd829e4e9); // K[4,3]: OC4=-23, OC5=-28, OC6=41, OC7=-40
        u_tb_common.write_wgt_word(2946, 32'h0f09d9fd); // K[4,3]: OC8=-3, OC9=-39, OC10=9, OC11=15
        u_tb_common.write_wgt_word(2947, 32'hc3dafb0b); // K[4,3]: OC12=11, OC13=-5, OC14=-38, OC15=-61
        // Block 24: tile_oc=0, ky=4, kw=4
        u_tb_common.write_wgt_word(3072, 32'he228fa1d); // K[4,4]: OC0=29, OC1=-6, OC2=40, OC3=-30
        u_tb_common.write_wgt_word(3073, 32'hfb07d3ca); // K[4,4]: OC4=-54, OC5=-45, OC6=7, OC7=-5
        u_tb_common.write_wgt_word(3074, 32'hfb07f8e1); // K[4,4]: OC8=-31, OC9=-8, OC10=7, OC11=-5
        u_tb_common.write_wgt_word(3075, 32'h07e4f01a); // K[4,4]: OC12=26, OC13=-16, OC14=-28, OC15=7
        // Block 25: tile_oc=1, ky=0, kw=0
        u_tb_common.write_wgt_word(3200, 32'he511ef2a); // K[0,0]: OC16=42, OC17=-17, OC18=17, OC19=-27
        u_tb_common.write_wgt_word(3201, 32'h01e3f9cb); // K[0,0]: OC20=-53, OC21=-7, OC22=-29, OC23=1
        u_tb_common.write_wgt_word(3202, 32'h1216f2e6); // K[0,0]: OC24=-26, OC25=-14, OC26=22, OC27=18
        u_tb_common.write_wgt_word(3203, 32'hf3e012f9); // K[0,0]: OC28=-7, OC29=18, OC30=-32, OC31=-13
        // Block 26: tile_oc=1, ky=0, kw=1
        u_tb_common.write_wgt_word(3328, 32'hc41bfc1e); // K[0,1]: OC16=30, OC17=-4, OC18=27, OC19=-60
        u_tb_common.write_wgt_word(3329, 32'he6d22709); // K[0,1]: OC20=9, OC21=39, OC22=-46, OC23=-26
        u_tb_common.write_wgt_word(3330, 32'h0a0c20e4); // K[0,1]: OC24=-28, OC25=32, OC26=12, OC27=10
        u_tb_common.write_wgt_word(3331, 32'h1a022c05); // K[0,1]: OC28=5, OC29=44, OC30=2, OC31=26
        // Block 27: tile_oc=1, ky=0, kw=2
        u_tb_common.write_wgt_word(3456, 32'hd12ff20f); // K[0,2]: OC16=15, OC17=-14, OC18=47, OC19=-47
        u_tb_common.write_wgt_word(3457, 32'hd9f10a12); // K[0,2]: OC20=18, OC21=10, OC22=-15, OC23=-39
        u_tb_common.write_wgt_word(3458, 32'h151e05e5); // K[0,2]: OC24=-27, OC25=5, OC26=30, OC27=21
        u_tb_common.write_wgt_word(3459, 32'hf61a07e9); // K[0,2]: OC28=-23, OC29=7, OC30=26, OC31=-10
        // Block 28: tile_oc=1, ky=0, kw=3
        u_tb_common.write_wgt_word(3584, 32'hc821f726); // K[0,3]: OC16=38, OC17=-9, OC18=33, OC19=-56
        u_tb_common.write_wgt_word(3585, 32'hffddfd27); // K[0,3]: OC20=39, OC21=-3, OC22=-35, OC23=-1
        u_tb_common.write_wgt_word(3586, 32'h12eae90a); // K[0,3]: OC24=10, OC25=-23, OC26=-22, OC27=18
        u_tb_common.write_wgt_word(3587, 32'h101b09fd); // K[0,3]: OC28=-3, OC29=9, OC30=27, OC31=16
        // Block 29: tile_oc=1, ky=0, kw=4
        u_tb_common.write_wgt_word(3712, 32'hf1f80722); // K[0,4]: OC16=34, OC17=7, OC18=-8, OC19=-15
        u_tb_common.write_wgt_word(3713, 32'h2cfeef34); // K[0,4]: OC20=52, OC21=-17, OC22=-2, OC23=44
        u_tb_common.write_wgt_word(3714, 32'hf5cafdec); // K[0,4]: OC24=-20, OC25=-3, OC26=-54, OC27=-11
        u_tb_common.write_wgt_word(3715, 32'he40ce6f4); // K[0,4]: OC28=-12, OC29=-26, OC30=12, OC31=-28
        // Block 30: tile_oc=1, ky=1, kw=0
        u_tb_common.write_wgt_word(3840, 32'h031af317); // K[1,0]: OC16=23, OC17=-13, OC18=26, OC19=3
        u_tb_common.write_wgt_word(3841, 32'hd9e024f7); // K[1,0]: OC20=-9, OC21=36, OC22=-32, OC23=-39
        u_tb_common.write_wgt_word(3842, 32'h22fc1604); // K[1,0]: OC24=4, OC25=22, OC26=-4, OC27=34
        u_tb_common.write_wgt_word(3843, 32'heef512fe); // K[1,0]: OC28=-2, OC29=18, OC30=-11, OC31=-18
        // Block 31: tile_oc=1, ky=1, kw=1
        u_tb_common.write_wgt_word(3968, 32'hf117082a); // K[1,1]: OC16=42, OC17=8, OC18=23, OC19=-15
        u_tb_common.write_wgt_word(3969, 32'hc9de2611); // K[1,1]: OC20=17, OC21=38, OC22=-34, OC23=-55
        u_tb_common.write_wgt_word(3970, 32'hf4241117); // K[1,1]: OC24=23, OC25=17, OC26=36, OC27=-12
        u_tb_common.write_wgt_word(3971, 32'h15fc37ff); // K[1,1]: OC28=-1, OC29=55, OC30=-4, OC31=21
        // Block 32: tile_oc=1, ky=1, kw=2
        u_tb_common.write_wgt_word(4096, 32'hea1c1127); // K[1,2]: OC16=39, OC17=17, OC18=28, OC19=-22
        u_tb_common.write_wgt_word(4097, 32'hdbe9ea13); // K[1,2]: OC20=19, OC21=-22, OC22=-23, OC23=-37
        u_tb_common.write_wgt_word(4098, 32'h02330101); // K[1,2]: OC24=1, OC25=1, OC26=51, OC27=2
        u_tb_common.write_wgt_word(4099, 32'h0920070d); // K[1,2]: OC28=13, OC29=7, OC30=32, OC31=9
        // Block 33: tile_oc=1, ky=1, kw=3
        u_tb_common.write_wgt_word(4224, 32'h02e7001a); // K[1,3]: OC16=26, OC17=0, OC18=-25, OC19=2
        u_tb_common.write_wgt_word(4225, 32'h0c0cdb14); // K[1,3]: OC20=20, OC21=-37, OC22=12, OC23=12
        u_tb_common.write_wgt_word(4226, 32'h0b02f7f8); // K[1,3]: OC24=-8, OC25=-9, OC26=2, OC27=11
        u_tb_common.write_wgt_word(4227, 32'h0611edf8); // K[1,3]: OC28=-8, OC29=-19, OC30=17, OC31=6
        // Block 34: tile_oc=1, ky=1, kw=4
        u_tb_common.write_wgt_word(4352, 32'h06dcf221); // K[1,4]: OC16=33, OC17=-14, OC18=-36, OC19=6
        u_tb_common.write_wgt_word(4353, 32'h370beb28); // K[1,4]: OC20=40, OC21=-21, OC22=11, OC23=55
        u_tb_common.write_wgt_word(4354, 32'h100207fe); // K[1,4]: OC24=-2, OC25=7, OC26=2, OC27=16
        u_tb_common.write_wgt_word(4355, 32'hf400d81a); // K[1,4]: OC28=26, OC29=-40, OC30=0, OC31=-12
        // Block 35: tile_oc=1, ky=2, kw=0
        u_tb_common.write_wgt_word(4480, 32'h4000f9f8); // K[2,0]: OC16=-8, OC17=-7, OC18=0, OC19=64
        u_tb_common.write_wgt_word(4481, 32'hcfe41b0a); // K[2,0]: OC20=10, OC21=27, OC22=-28, OC23=-49
        u_tb_common.write_wgt_word(4482, 32'h10050911); // K[2,0]: OC24=17, OC25=9, OC26=5, OC27=16
        u_tb_common.write_wgt_word(4483, 32'hfbfb2dfd); // K[2,0]: OC28=-3, OC29=45, OC30=-5, OC31=-5
        // Block 36: tile_oc=1, ky=2, kw=1
        u_tb_common.write_wgt_word(4608, 32'h400204f9); // K[2,1]: OC16=-7, OC17=4, OC18=2, OC19=64
        u_tb_common.write_wgt_word(4609, 32'he2f90325); // K[2,1]: OC20=37, OC21=3, OC22=-7, OC23=-30
        u_tb_common.write_wgt_word(4610, 32'hfa100005); // K[2,1]: OC24=5, OC25=0, OC26=16, OC27=-6
        u_tb_common.write_wgt_word(4611, 32'h001029f4); // K[2,1]: OC28=-12, OC29=41, OC30=16, OC31=0
        // Block 37: tile_oc=1, ky=2, kw=2
        u_tb_common.write_wgt_word(4736, 32'h35f7f120); // K[2,2]: OC16=32, OC17=-15, OC18=-9, OC19=53
        u_tb_common.write_wgt_word(4737, 32'hfe15dd0b); // K[2,2]: OC20=11, OC21=-35, OC22=21, OC23=-2
        u_tb_common.write_wgt_word(4738, 32'hef24ea1c); // K[2,2]: OC24=28, OC25=-22, OC26=36, OC27=-17
        u_tb_common.write_wgt_word(4739, 32'hf604feed); // K[2,2]: OC28=-19, OC29=-2, OC30=4, OC31=-10
        // Block 38: tile_oc=1, ky=2, kw=3
        u_tb_common.write_wgt_word(4864, 32'h15ca0827); // K[2,3]: OC16=39, OC17=8, OC18=-54, OC19=21
        u_tb_common.write_wgt_word(4865, 32'h301fec03); // K[2,3]: OC20=3, OC21=-20, OC22=31, OC23=48
        u_tb_common.write_wgt_word(4866, 32'h1c05ed07); // K[2,3]: OC24=7, OC25=-19, OC26=5, OC27=28
        u_tb_common.write_wgt_word(4867, 32'h0a23ecf2); // K[2,3]: OC28=-14, OC29=-20, OC30=35, OC31=10
        // Block 39: tile_oc=1, ky=2, kw=4
        u_tb_common.write_wgt_word(4992, 32'h0aedee14); // K[2,4]: OC16=20, OC17=-18, OC18=-19, OC19=10
        u_tb_common.write_wgt_word(4993, 32'h44f80e1d); // K[2,4]: OC20=29, OC21=14, OC22=-8, OC23=68
        u_tb_common.write_wgt_word(4994, 32'h0d100911); // K[2,4]: OC24=17, OC25=9, OC26=16, OC27=13
        u_tb_common.write_wgt_word(4995, 32'h0806d523); // K[2,4]: OC28=35, OC29=-43, OC30=6, OC31=8
        // Block 40: tile_oc=1, ky=3, kw=0
        u_tb_common.write_wgt_word(5120, 32'h0418eeca); // K[3,0]: OC16=-54, OC17=-18, OC18=24, OC19=4
        u_tb_common.write_wgt_word(5121, 32'hc831ff0a); // K[3,0]: OC20=10, OC21=-1, OC22=49, OC23=-56
        u_tb_common.write_wgt_word(5122, 32'h031cfd18); // K[3,0]: OC24=24, OC25=-3, OC26=28, OC27=3
        u_tb_common.write_wgt_word(5123, 32'h02f318fa); // K[3,0]: OC28=-6, OC29=24, OC30=-13, OC31=2
        // Block 41: tile_oc=1, ky=3, kw=1
        u_tb_common.write_wgt_word(5248, 32'h0ffeedd7); // K[3,1]: OC16=-41, OC17=-19, OC18=-2, OC19=15
        u_tb_common.write_wgt_word(5249, 32'hcf1bfb03); // K[3,1]: OC20=3, OC21=-5, OC22=27, OC23=-49
        u_tb_common.write_wgt_word(5250, 32'hf8000922); // K[3,1]: OC24=34, OC25=9, OC26=0, OC27=-8
        u_tb_common.write_wgt_word(5251, 32'h050422fd); // K[3,1]: OC28=-3, OC29=34, OC30=4, OC31=5
        // Block 42: tile_oc=1, ky=3, kw=2
        u_tb_common.write_wgt_word(5376, 32'h1bd8fceb); // K[3,2]: OC16=-21, OC17=-4, OC18=-40, OC19=27
        u_tb_common.write_wgt_word(5377, 32'hf40ee900); // K[3,2]: OC20=0, OC21=-23, OC22=14, OC23=-12
        u_tb_common.write_wgt_word(5378, 32'h0b130501); // K[3,2]: OC24=1, OC25=5, OC26=19, OC27=11
        u_tb_common.write_wgt_word(5379, 32'h131f0f02); // K[3,2]: OC28=2, OC29=15, OC30=31, OC31=19
        // Block 43: tile_oc=1, ky=3, kw=3
        u_tb_common.write_wgt_word(5504, 32'h02db0d05); // K[3,3]: OC16=5, OC17=13, OC18=-37, OC19=2
        u_tb_common.write_wgt_word(5505, 32'h4a13f8fc); // K[3,3]: OC20=-4, OC21=-8, OC22=19, OC23=74
        u_tb_common.write_wgt_word(5506, 32'h1e11fc13); // K[3,3]: OC24=19, OC25=-4, OC26=17, OC27=30
        u_tb_common.write_wgt_word(5507, 32'h0901d80d); // K[3,3]: OC28=13, OC29=-40, OC30=1, OC31=9
        // Block 44: tile_oc=1, ky=3, kw=4
        u_tb_common.write_wgt_word(5632, 32'h10feee28); // K[3,4]: OC16=40, OC17=-18, OC18=-2, OC19=16
        u_tb_common.write_wgt_word(5633, 32'h2f0015f6); // K[3,4]: OC20=-10, OC21=21, OC22=0, OC23=47
        u_tb_common.write_wgt_word(5634, 32'h061fee03); // K[3,4]: OC24=3, OC25=-18, OC26=31, OC27=6
        u_tb_common.write_wgt_word(5635, 32'h0004ec19); // K[3,4]: OC28=25, OC29=-20, OC30=4, OC31=0
        // Block 45: tile_oc=1, ky=4, kw=0
        u_tb_common.write_wgt_word(5760, 32'he00b12c9); // K[4,0]: OC16=-55, OC17=18, OC18=11, OC19=-32
        u_tb_common.write_wgt_word(5761, 32'he4340af7); // K[4,0]: OC20=-9, OC21=10, OC22=52, OC23=-28
        u_tb_common.write_wgt_word(5762, 32'he4e910f7); // K[4,0]: OC24=-9, OC25=16, OC26=-23, OC27=-28
        u_tb_common.write_wgt_word(5763, 32'hf503240f); // K[4,0]: OC28=15, OC29=36, OC30=3, OC31=-11
        // Block 46: tile_oc=1, ky=4, kw=1
        u_tb_common.write_wgt_word(5888, 32'hdf13f7bb); // K[4,1]: OC16=-69, OC17=-9, OC18=19, OC19=-33
        u_tb_common.write_wgt_word(5889, 32'he828e8de); // K[4,1]: OC20=-34, OC21=-24, OC22=40, OC23=-24
        u_tb_common.write_wgt_word(5890, 32'h1001f826); // K[4,1]: OC24=38, OC25=-8, OC26=1, OC27=16
        u_tb_common.write_wgt_word(5891, 32'hecf524f0); // K[4,1]: OC28=-16, OC29=36, OC30=-11, OC31=-20
        // Block 47: tile_oc=1, ky=4, kw=2
        u_tb_common.write_wgt_word(6016, 32'h000607d7); // K[4,2]: OC16=-41, OC17=7, OC18=6, OC19=0
        u_tb_common.write_wgt_word(6017, 32'h23fdfbe4); // K[4,2]: OC20=-28, OC21=-5, OC22=-3, OC23=35
        u_tb_common.write_wgt_word(6018, 32'hf0040c09); // K[4,2]: OC24=9, OC25=12, OC26=4, OC27=-16
        u_tb_common.write_wgt_word(6019, 32'hec19edfb); // K[4,2]: OC28=-5, OC29=-19, OC30=25, OC31=-20
        // Block 48: tile_oc=1, ky=4, kw=3
        u_tb_common.write_wgt_word(6144, 32'h1f0702ea); // K[4,3]: OC16=-22, OC17=2, OC18=7, OC19=31
        u_tb_common.write_wgt_word(6145, 32'h41f5ffcd); // K[4,3]: OC20=-51, OC21=-1, OC22=-11, OC23=65
        u_tb_common.write_wgt_word(6146, 32'h0418e7f4); // K[4,3]: OC24=-12, OC25=-25, OC26=24, OC27=4
        u_tb_common.write_wgt_word(6147, 32'hfd10e0f5); // K[4,3]: OC28=-11, OC29=-32, OC30=16, OC31=-3
        // Block 49: tile_oc=1, ky=4, kw=4
        u_tb_common.write_wgt_word(6272, 32'h1217ef1e); // K[4,4]: OC16=30, OC17=-17, OC18=23, OC19=18
        u_tb_common.write_wgt_word(6273, 32'h22fb1eef); // K[4,4]: OC20=-17, OC21=30, OC22=-5, OC23=34
        u_tb_common.write_wgt_word(6274, 32'h0c1af7f6); // K[4,4]: OC24=-10, OC25=-9, OC26=26, OC27=12
        u_tb_common.write_wgt_word(6275, 32'h0106e5fb); // K[4,4]: OC28=-5, OC29=-27, OC30=6, OC31=1
